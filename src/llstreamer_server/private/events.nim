import std/[asyncdispatch]
import idgen, logging

type
    EventError* = object of CatchableError
        ## Raise when an event-related error occurs

    EventCanceledError* = object of EventError
        ## Raised when an event is marked as canceled after all handlers are completed
    
    EventInterruptedError* = object of EventError
        ## Raised if an event was interrupted by some other event or circumstance
    
    EventHandlerError* = object of EventError
        ## Raised if an error occurs while running an event handler proc
        
        handlerError*: ref Exception ## The error that occurred while running the handler proc

    Event* = object of RootObj
        ## A generic event
    
    CancelableEvent* = object of Event
        ## A generic cancelable event.
        ## Handlers for cancelable events must be awaited, or else cancelation will not not be meaningful since the event may have passed during an async operation.
        ## All handlers will be run, even if a previous handler has marked the event as canceled.
        ## The cancelation state of an event is evaluated after every handler has been called.
        
        isCanceled*: bool ## Whether the event has been marked as canceled

    EventHandler*[EventType] = object of RootObj
        ## A generic event handler.
        ## Event handlers may or may not be awaited and executed in their registration order, except in the case of cancelable event handlers which must be awaited.
        ## Additionally, event handlers may be marked as a "one time" handler which will be removed after handling an event.
        
        id*: HandlerId ## The handler's unique ID
        oneTime*: bool ## Whether this handler should only be run once and then will be removed
        handler*: proc(event: ref EventType) {.async.} ## The proc that is called for this handler
    
    FilterableEventHandler*[EventType, FilterType] = object of EventHandler[EventType]
        ## A generic filterable event handler.
        ## Filterable event handlers include a filter field that is used to determine what the handler applies to.
        ## For optional filtration, wrap your filter type in an Option object.
        
        filter*: FilterType

# CONSTRUCTORS #
proc newEventError*(msg: string): ref EventError =
    var e: ref EventError
    new(e)
    e.msg = msg
    return e

proc newEventCanceledError*(msg: string): ref EventCanceledError =
    var e: ref EventCanceledError
    new(e)
    e.msg = msg
    return e

proc newEventInterruptedError*(msg: string): ref EventInterruptedError =
    var e: ref EventInterruptedError
    new(e)
    e.msg = msg
    return e

proc newEventHandlerError*(msg: string, handlerError: ref Exception): ref EventHandlerError =
    var e: ref EventHandlerError
    new(e)
    e.msg = msg
    e.handlerError = handlerError
    return e

# UTILS #

proc raiseErrorIfCanceled*[T](event: T, msg: string) {.raises: EventCanceledError.} =
    ## Raises EventCanceledError if the provided event is marked as canceled
    
    if event.isCanceled:
        raise newEventCanceledError(msg)

proc execHandler*[T, E](handler: T, event: E, awaitHandler: bool, raiseErrors: bool, errMsg: string) {.async.} =
    ## Executes and handles the awaiting and error handling associated with an async event handler
    
    proc reportError(ex: ref Exception) =
        logError errMsg, ex, ex.msg

    try:
        # Run handler proc
        let fut = handler.handler(event)

        # If nil is not returned and the future isn't finished, then the handler must be treated like an async proc
        if not fut.isNil and not fut.finished:
            if awaitHandler:
                await handler.handler(event)
            else:
                fut.callback = proc() =
                    if fut.failed:
                        reportError(fut.error)
    except:
        if raiseErrors:
            raise newEventHandlerError(errMsg, getCurrentException())
        else:
            reportError(getCurrentException())