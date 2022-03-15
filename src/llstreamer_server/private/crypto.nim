import std/[osproc, asyncfutures]
import argon2_highlevel/async

# Get current CPU's processor (or thread) count
let cpuThreads = max(countProcessors(), 1)

# The hasher instance
var hasher: ref AsyncArgon2

proc initCryptoWorker*() =
    ## Initializes the crypto worker

    hasher = createAsyncArgon2(cpuThreads)

proc hashPassword*(password: string): Future[string] =
    ## Hashes a password on a worker thread and completes the future with the hashed password once it has finished

    return hasher.hash(password)

proc verifyPassword*(password: string, hashStr: string): Future[bool] =
    ## Verifies a password against the provided hash
    
    return hasher.verify(password, hashStr)