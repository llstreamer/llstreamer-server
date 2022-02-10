proc logInfo*(msg: string) =
    ## Logs an info message

    stdout.writeLine("[INF] "&msg)

proc logError*(msg: string) =
    ## Logs an error message

    stderr.writeLine("[ERR] "&msg)

proc logError*(msg: string, exception: ref Exception, exceptionMsg: string) =
    ## Logs an error message with an exception
    
    logError(msg)
    logError("\tException: "&repr(exception))
    logError("\tMessage: "&exceptionMsg)