import std/[asyncdispatch, locks, times]
import logging

type
    TimerJob = object
        id: uint64
        time: float
        callback: proc ()
        forever: bool
        interval: int64
    Timer* = object
        ## A Timer object that keeps track of timer information
        
        running: bool
        idCounter: uint64
        idCounterLock: Lock
        jobs: seq[TimerJob]
        jobsLock: Lock
        execLock: Lock

proc timerLoop(timer: ref Timer) {.async.} =
    proc findJob(id: uint64): int =
        for i in 0..<timer.jobs.len:
            if timer.jobs[i].id == id:
                return i
        return -1

    while timer.running:
        await sleepAsync(1)

        # Iterate through jobs, executing ones past or on their execution time
        let time = epochTime()
        var i = 0
        while i < timer.jobs.len:
            let job = timer.jobs[i]
                
            # Execute job
            if time >= job.time:
                try:
                    withLock timer.execLock:
                        job.callback()
                except:
                    logError "Exception occurred while trying to execute timeout callback", getCurrentException(), getCurrentExceptionMsg()
                finally:
                    let idx = findJob(job.id)
                    
                    # Check if job still exists
                    if idx > -1:
                        withLock timer.jobsLock:
                            # Remove job or extend its time, depending on whether "forever" is set to true
                            if job.forever:
                                timer.jobs[idx].time = time+(((int) job.interval)/1000)
                            else:
                                withLock timer.jobsLock:
                                    timer.jobs.delete(idx)

                                if i > 0:
                                    dec i

            inc i

proc startTimer*(timer: ref Timer) =
    ## Starts a timer

    timer.running = true
    asyncCheck timerLoop(timer)

proc stopTimer*(timer: ref Timer) =
    ## Stops a timer (although if there are currently executing jobs, they will be finished first)
    
    withLock timer.execLock:
        timer.running = false

proc setTimer*(timer: ref Timer, callback: proc (), ms: int, forever: bool = false): uint64 =
    ## Sets a callback to be run after the specified number of milliseconds, and returns its ID.
    ## Works the same way as JavaScript's "setTimeout", except it can also be infinite (equivalent to JS "setInterval").
    
    # Generate ID
    var id: uint64
    withLock timer.idCounterLock:
        id = timer.idCounter
        inc timer.idCounter

    # Figure out what time the job needs to expire
    let time = epochTime()+(ms/1000)

    # Create and add job
    withLock timer.jobsLock:
        timer.jobs.add(TimerJob(
            id: id,
            time: time,
            callback: callback,
            forever: forever,
            interval: ms
        ))
    
    return id

proc clearTimer*(timer: ref Timer, timeoutId: uint64) =
    ## Clears (cancels) a timer that has not been run yet.
    ## Works the same way as JavaScript's "clearTimeout" or "clearInterval".
    
    withLock timer.jobsLock:
        for i in 0..<timer.jobs.len:
            if timer.jobs[i].id == timeoutId:
                timer.jobs.delete(i)
                return

proc clearAllTimers*(timer: ref Timer) =
    ## Clears (cancels) all timers.
    
    withLock timer.jobsLock:
        timer.jobs = @[]

proc newTimer*(): ref Timer =
    ## Creates a new timer

    var timer: ref Timer
    new(timer)
    return timer