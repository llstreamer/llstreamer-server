import std/[os, osproc, asyncfutures, strformat, strutils, base64, locks, sugar]
import argon2, random/urandom
import logging, exceptions, threadutils

let cpuThreads = (uint32) max(countProcessors(), 1)

type
    JobKind {.pure.} = enum
        Hash
        Verify

    Job = object
        case kind: JobKind
        of JobKind.Hash:
            passToHash: string
            hashResult: string
            hashFuture: Future[string]
        of JobKind.Verify:
            passToVerify: string
            hashToVerify: string
            verifyResult: bool
            verifyFuture: Future[bool]
    
    JobQueue = tuple[
        lock: Lock,
        jobs: seq[Job]
    ]
    
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

# Processing queue
var jobQueue: JobQueue
jobQueue.jobs = newSeq[Job]()

# Local thread executor
var threadExecutor = newLocalThreadExecutor()

var cryptoThread: Thread[(ptr JobQueue, ptr ref LocalThreadExecutor)]
proc cryptoThreadProc(queues: (ptr JobQueue, ptr ref LocalThreadExecutor)) {.thread.} =
    let queue = queues[0]
    let executor = queues[1][]

    proc fail[T](future: Future[T], jobKind: JobKind, ex: ref Exception, exMsg: string) =
        logError fmt"Failed to execute job crypto job of type {jobKind}", ex, exMsg
        future.fail(ex)

    while true:
        sleep(1)

        # Check if there are any new jobs in the queue
        while queue[].jobs.len > 0:
            var job: Job
            withLock queue[].lock:
                job = queue[].jobs[0]
                queue[].jobs.del(0)

            case job.kind:
            of JobKind.Hash:
                try:
                    # Generate salt
                    let salt = urandom(128)

                    # Hash password
                    let hash = argon2("id", job.passToHash, cast[string](salt), 1, uint16.high, cpuThreads, 24).enc

                    # Complete future
                    doInThread executor:
                        job.hashFuture.complete(hash)
                except:
                    doInThread executor:
                        job.hashFuture.fail(job.kind, getCurrentException(), getCurrentExceptionMsg())
            of JobKind.Verify:
                try:
                    # Parse hash string
                    let ogHash = job.hashToVerify.parseArgon2HashStr()

                    # Hash password
                    let passHash = argon2(ogHash.algoType, job.passToVerify, ogHash.salt, ogHash.iterations, ogHash.memory, ogHash.processorCount, (uint32) ogHash.hash.len).enc.parseArgon2HashStr()

                    # Compare and complete future
                    doInThread executor:
                        job.verifyFuture.complete(ogHash.hash == passHash.hash)
                except:
                    doInThread executor:
                        job.verifyFuture.fail(job.kind, getCurrentException(), getCurrentExceptionMsg())
                

proc initCryptoWorker*() =
    ## Initializes the crypto worker thread and associated components

    startLocalThreadExecutor(threadExecutor)
    createThread(cryptoThread, cryptoThreadProc, (addr jobQueue, addr threadExecutor))

proc hashPassword*(password: string): Future[string] =
    ## Hashes a password on a worker thread and completes the future with the hashed password once it has finished

    let future = newFuture[string]("crypto.hashPassword")

    withLock jobQueue.lock:
        jobQueue.jobs.add(Job(
            kind: JobKind.Hash,
            passToHash: password,
            hashFuture: future
        ))

    return future

proc verifyPassword*(password: string, hashStr: string): Future[bool] =
    ## Verifies a password against the provided hash
    
    let future = newFuture[bool]("crypto.verifyPassword")

    withLock jobQueue.lock:
        jobQueue.jobs.add(Job(
            kind: JobKind.Verify,
            passToVerify: password,
            hashToVerify: hashStr,
            verifyFuture: future
        ))
    
    return future