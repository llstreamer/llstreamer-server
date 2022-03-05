import std/[asyncdispatch, os]
import llstreamer_server/private/[server, objects, constants, crypto, config, accounts]
import llstreamer_server/private/db/db

when isMainModule:
    echo "LLStreamer Server "&SERVER_VER

    # Create default config if none exists
    let confPath = "config.json"
    if not fileExists(confPath):
        writeDefaultConfig(confPath)

    # Load configuration
    let conf = createConfigFromFile(confPath)

    # Initialize crypto worker thread
    initCryptoWorker()

    # Initialize database connection
    waitFor initDb(conf.databaseConfig)

    # Initialize accounts system
    # Sleep in background to make sure event loop has something to do
    asyncCheck sleepAsync(5000)
    waitFor initAccounts()

    # Configure server
    var serverInst = (ref Server)().serverFromConfig(conf)

    # Start server
    waitFor startServer(serverInst)