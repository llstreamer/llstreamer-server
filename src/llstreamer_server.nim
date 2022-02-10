import std/[asyncdispatch, db_sqlite]

import llstreamer_server/private/[server, objects, constants, crypto]
import llstreamer_server/private/db/[migrations]

let db = open("lol.db", "", "", "")
db.applyMigrations()

when isMainModule:
    echo "LLStreamer Server "&SERVER_VER

    # Initialize crypto worker thread
    initCryptoWorker()

    # Configure server
    let conf = Config(host: "0.0.0.0", port: Port(9009))
    var serverInst = (ref Server)().serverFromConfig(conf)

    # Start server
    waitFor startServer(serverInst)