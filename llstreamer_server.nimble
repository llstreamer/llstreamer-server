# Package

version       = "1.0.0"
author        = "Termer"
description   = "Livestreaming server for low-latency video"
license       = "AGPL-3.0-or-later"
srcDir        = "src"
namedBin["llstreamer_server"] = "server"


# Dependencies

requires "nim >= 1.6.2"
requires "msgpack4nim == 0.3.1"
requires "argon2 == 1.0.1"
requires "random == 0.5.7"