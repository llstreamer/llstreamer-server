import msgpack4nim
import std/[asyncnet, asyncdispatch]
import objects as packet_objects, enums
import ".."/[utils, idgen, objects]

# proc deserializePacket()