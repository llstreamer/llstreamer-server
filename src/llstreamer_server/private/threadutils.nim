import std/[asyncdispatch]
import logging

# Default local thread executor error handler
const defaultErrorHandler = proc(error: ref Exception) = logError "Failed to execute job on local thread executor", error, error.msg

type
    LocalThreadJob* = proc() ## A proc to be run on a LocalThreadExecutor

    LocalThreadExecutor* = object
        ## A LocalThreadExecutor object keeps track of a local thread executor's state
        
        errorHandler*: proc(error: ref Exception) ## The handler for errors that occur while executing queued jobs
        
        chan: Channel[LocalThreadJob]
        running: bool

proc newLocalThreadExecutor*(errorHandler: proc(error: ref Exception) = defaultErrorHandler): ref LocalThreadExecutor =
    ## Creates a new local thread executor.
    ## Local thread executors run jobs provided to them on the thread the executor was created, regardless of where it is called.

    var executor = new(LocalThreadExecutor)
    executor.errorHandler = errorHandler
    executor.running = false

    return executor

proc startLocalThreadExecutor*(executor: ref LocalThreadExecutor) {.async.} =
    ## Starts a local thread executor.
    ## The thread this is run in will be where all jobs are executed.
    
    executor.chan.open()
    executor.running = true
    
    # Run until executor.running is false (executor is shutdown)
    while executor.running:
        # Sleep to avoid high CPU usage
        await sleepAsync(1)

        # Check for job
        let jobRes = executor.chan.tryRecv()
        if jobRes.dataAvailable:
            let job = jobRes.msg

            # Execute job, passing any exceptions to the error handler
            try:
                if not job.isNil:
                    job()
            except Exception as e:
                executor.errorHandler(e)

proc stopLocalThreadExecutor*(executor: ref LocalThreadExecutor) =
    ## Stops a running local thread executor.
    ## Any currently executing jobs will be finished, but new jobs will not be executed until it is started again.

    executor.running = false
    executor.chan.close()

proc addJob*(executor: ref LocalThreadExecutor, job: LocalThreadJob) =
    ## Adds a job to be executed on a local thread executor
    
    executor.chan.send(job)

template doInThread*(executor: ref LocalThreadExecutor, body: auto) =
    ## Executes this statement's body in the provided local thread executor's thread

    executor.addJob(
        proc() =
            body
    )
