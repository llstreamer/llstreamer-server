import std/[asyncdispatch, locks]
import logging

# Default local thread executor error handler
const defaultErrorHandler = proc(error: ref Exception) = logError "Failed to execute job on local thread executor", error, error.msg

type
    LocalThreadJob* = proc() ## A proc to be run on a LocalThreadExecutor

    LocalThreadExecutor* = object
        ## A LocalThreadExecutor object keeps track of a local thread executor's state
        
        errorHandler*: proc(error: ref Exception) ## The handler for errors that occur while executing queued jobs
        
        queue: seq[LocalThreadJob]
        lock: Lock
        running: bool

proc newLocalThreadExecutor*(errorHandler: proc(error: ref Exception) = defaultErrorHandler): ref LocalThreadExecutor =
    ## Creates a new local thread executor.
    ## Local thread executors run jobs provided to them on the thread the executor was created, regardless of where it is called.
    
    var lock = Lock()
    lock.initLock()

    var executor = new(LocalThreadExecutor)
    executor.errorHandler = errorHandler
    executor.queue = newSeq[LocalThreadJob]()
    executor.lock = lock
    executor.running = false

    return executor

proc startLocalThreadExecutor*(executor: ref LocalThreadExecutor) =
    ## Starts a local thread executor.
    ## The thread this is run in will be where all jobs are executed.
    
    proc loop() {.async.} =
        # Run until executor.running is false (executor is shutdown)
        while executor.running:
            # Sleep to avoid high CPU usage
            await sleepAsync(1)

            # Only manipulate queue when lock is acquired
            withLock executor.lock:
                # Execute all jobs
                while executor.queue.len > 0:
                    # Fetch and remove job
                    let job = executor.queue[0]
                    executor.queue.del(0)

                    # Execute job, passing any exceptions to the error handler
                    try:
                        job()
                    except Exception as e:
                        executor.errorHandler(e)
    
    executor.running = true
    asyncCheck loop()

proc stopLocalThreadExecutor*(executor: ref LocalThreadExecutor) =
    ## Stops a running local thread executor.
    ## Any currently executing jobs will be finished, but new jobs will not be executed until it is started again.

    executor.running = false

proc addJob*(executor: ref LocalThreadExecutor, job: LocalThreadJob) =
    ## Adds a job to be executed on a local thread executor
    
    withLock executor.lock:
        executor.queue.add(job)

template doInThread*(executor: ref LocalThreadExecutor, body: auto) =
    ## Executes this statement's body in the provided local thread executor's thread

    executor.addJob(
        proc() =
            body
    )
