import std/[os, osproc, asyncdispatch, strformat, strutils, base64, options, tables]
import argon2, random/urandom
import logging, exceptions

# Get current CPU's processor (or thread) count
let cpuThreads = (uint32) max(countProcessors(), 1)

type
    JobKind {.pure.} = enum
        Hash
        Verify

    Job = object
        id: uint32
        case kind: JobKind
        of JobKind.Hash:
            passToHash: string
            hashResult: string
        of JobKind.Verify:
            passToVerify: string
            hashToVerify: string
            verifyResult: bool

    JobRes = object
        id: uint32
        error: Option[ref Exception]
        case kind: JobKind:
        of JobKind.Hash:
            hashRes: string
        of JobKind.Verify:
            verifyRes: bool
    
    JobFut = object
        case kind: JobKind
        of JobKind.Hash:
            hashFut: Future[string]
        of JobKind.Verify:
            verifyFut: Future[bool]
    
    Argon2Hash* = object
        ## Object representation of an argon2 hash string's contents
        
        original*: string ## The original argon2 hash string
        version*: uint32 ## The argon2 version used
        algoType*: string ## The algorithm type used (either "i", "d", or "id")
        memory*: uint32 ## The amount of memory used to create the hash
        iterations*: uint32 ## The iterations used when creating the hash
        processorCount*: uint32 ## The amount of processors used to create the hash
        salt*: string ## The salt to use with the hash (not base64 encoded)
        hash*: string ## The hash itself (not base64 encoded)

# Job ID generation
var id = (uint32) 0;
proc genId(): uint32 =
    inc id
    return id

proc parseArgon2HashStr*(str: string): Argon2Hash {.raises: [CannotParseHashError, ValueError].} =
    let parts = str.split("$")

    # Make sure there is a correct number of parts
    if parts.len < 6:
        raise newCannotParseHashError("Malformed Argon2 hash string")

    let algoStr = parts[1]
    let verStrRaw = parts[2]
    let metaStr = parts[3]
    let saltStr = parts[4]
    let hashStr = parts[5]

    # Check algorithm
    proc err() = 
        raise newCannotParseHashError(fmt"Unknown algorithm type '{algoStr}'")
    if algoStr.len < 7:
        err()
    let algoType = algoStr.substr(6)
    if algoType != "i" and algoType != "d" and algoType != "id":
        err()
    
    # Parse version string
    var verStr = verStrRaw.split("=")[1]
    
    # Parse meta string
    var memStr: string
    var iterStr: string
    var procStr: string
    var metaParts = metaStr.split(",")
    for part in metaParts:
        let keyVal = part.split("=")
        case keyVal[0]:
        of "m":
            memStr = keyVal[1]
        of "t":
            iterStr = keyVal[1]
        of "p":
            procStr = keyVal[1]
    
    # Return object with parsed values
    return Argon2Hash(
        original: str,
        version: (uint32) parseInt(verStr),
        algoType: algoType,
        memory: (uint32) parseInt(memStr),
        iterations: (uint32) parseInt(iterStr),
        processorCount: (uint32) parseInt(procStr),
        salt: saltStr.decode(),
        hash: hashStr.decode()
    )

# Channels for passing jobs/results to/from the worker thread
var jobChan: ptr Channel[Job]
var resChan: ptr Channel[JobRes]

# Table of job IDs and their corresponding Futures
var futsTable = new Table[uint32, JobFut]

var cryptoThread: Thread[(ptr Channel[Job], ptr Channel[JobRes])]
proc cryptoThreadProc(args: (ptr Channel[Job], ptr Channel[JobRes])) {.thread.} =
    let jobs = args[0]
    let res = args[1]

    proc fail(job: Job, ex: ref Exception, exMsg: string) =
        logError fmt"Failed to execute job crypto job of type {job.kind}", ex, exMsg
        res[].send(JobRes(
            id: job.id,
            error: some(ex),
            kind: job.kind
        ))

    while true:
        sleep(1)

        # Check if there are any new jobs in the channel
        let jobRes = jobs[].tryRecv()
        if jobRes.dataAvailable:
            let job = jobRes.msg

            case job.kind:
            of JobKind.Hash:
                try:
                    # Generate salt
                    let salt = urandom(128)

                    # Hash password
                    let hash = argon2("id", job.passToHash, cast[string](salt), 1, uint16.high, cpuThreads, 24).enc

                    # Send result
                    res[].send(JobRes(
                        id: job.id,
                        error: none[ref Exception](),
                        kind: JobKind.Hash,
                        hashRes: hash
                    ))
                except:
                    job.fail(getCurrentException(), getCurrentExceptionMsg())
            of JobKind.Verify:
                try:
                    # Parse hash string
                    let ogHash = job.hashToVerify.parseArgon2HashStr()

                    # Hash password
                    let passHash = argon2(ogHash.algoType, job.passToVerify, ogHash.salt, ogHash.iterations, ogHash.memory, ogHash.processorCount, (uint32) ogHash.hash.len).enc.parseArgon2HashStr()

                    # Compare and complete future
                    res[].send(JobRes(
                        id: job.id,
                        error: none[ref Exception](),
                        kind: JobKind.Verify,
                        verifyRes: ogHash.hash == passHash.hash
                    ))
                except:
                    job.fail(getCurrentException(), getCurrentExceptionMsg())

proc resRecvLoop() {.async.} =
    ## Loop that checks for results and completes their corresponding futures

    while true:
        await sleepAsync(1)

        # Check for result
        let resRes = resChan[].tryRecv()
        if resRes.dataAvailable:
            let res = resRes.msg

            # Check for key in futures table
            if futsTable.hasKey(res.id):
                let val = futsTable[res.id]
                futsTable.del(res.id)

                # Fail future if error present, otherwise complete it
                if res.error.isSome:
                    case res.kind:
                    of JobKind.Hash:
                        val.hashFut.fail(res.error.get)
                    of JobKind.Verify:
                        val.verifyFut.fail(res.error.get)
                else:
                    case res.kind:
                    of JobKind.Hash:
                        val.hashFut.complete(res.hashRes)
                    of JobKind.Verify:
                        val.verifyFut.complete(res.verifyRes)

proc initCryptoWorker*() =
    ## Initializes the crypto worker thread and associated components

    # Allocate shared memory for storing channels
    jobChan = cast[ptr Channel[Job]](
        allocShared0(sizeof(Channel[Job]))
    )
    resChan = cast[ptr Channel[JobRes]](
        allocShared0(sizeof(Channel[JobRes]))
    )
    jobChan[].open()
    resChan[].open()

    # Start result receiver and worker thread
    asyncCheck resRecvLoop()
    createThread(cryptoThread, cryptoThreadProc, (jobChan, resChan))

proc hashPassword*(password: string): Future[string] =
    ## Hashes a password on a worker thread and completes the future with the hashed password once it has finished

    # Generate future and its ID, then put into futures table
    let future = newFuture[string]("crypto.hashPassword")
    let id = genId()
    futsTable[id] = JobFut(
        kind: JobKind.Hash,
        hashFut: future
    )

    # Send job
    jobChan[].send(Job(
        id: id,
        kind: JobKind.Hash,
        passToHash: password
    ))

    return future

proc verifyPassword*(password: string, hashStr: string): Future[bool] =
    ## Verifies a password against the provided hash

    # Generate future and its ID, then put into futures table
    let future = newFuture[bool]("crypto.verifyPassword")
    let id = genId()
    futsTable[id] = JobFut(
        kind: JobKind.Verify,
        verifyFut: future
    )

    jobChan[].send(Job(
        id: id,
        kind: JobKind.Verify,
        passToVerify: password,
        hashToVerify: hashStr
    ))
    
    return future