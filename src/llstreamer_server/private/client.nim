import std/[options, asyncdispatch, asyncnet, nativesockets]
import idgen, objects, utils
import packets/objects as packet_objects
import packets/[enums, server, readwrite]

proc clientFromSocket*(inst: ref Client, socket: AsyncSocket): ref Client =
    ## Configures a Client ref object with the provided AsyncSocket
    
    let addrInfo = socket.getLocalAddr()

    inst.id = genClientId()
    inst.host = addrInfo[0]
    inst.port = addrInfo[1]
    inst.socket = socket

    return inst
    
proc disconnect(client: Client, reason: SDisconnectReason, message: Option[string]) {.async.} =
    ## Disconnects a client with the specified reason, and optionally a message

    await client.sendPacket(ServerPacket(
        kind: ServerPacketType.Disconnect,
        id: genServerPacketId(),
        reply: 0,
        disconnectBody: SDisconnect(
            reason: reason,
            message: message.orEmpty()
        )
    ))