import std/[options, asyncdispatch, asyncnet, nativesockets, sequtils, sugar]
import idgen, objects, utils, constants
import packets/objects as packet_objects
import packets/enums as packet_enums
import packets/server as server_packets
import packets/client as client_packets
import packets/[enums, server, readwrite]

type
    ClientPacketHandle* = tuple[packet: ClientPacket, client: ref Client]
        ## Handle for client packets (used to reply)

proc clientFromSocket*(inst: ref Client, socket: AsyncSocket): ref Client =
    ## Configures a Client ref object with the provided AsyncSocket
    
    let addrInfo = socket.getLocalAddr()

    inst.id = genClientId()
    inst.host = addrInfo[0]
    inst.port = addrInfo[1]
    inst.socket = socket

    return inst

proc readPacket*(client: ref Client): Future[ClientPacketHandle] {.async, inline.} =
    ## Reads a packet from a client

    return (await client.socket.readPacket(), client)

proc readPacketWithTimeout*(client: ref Client, timeout: int): Future[ClientPacketHandle] {.async, inline.} =
    ## Reads a packet from a client, raising PacketTimeoutError if the specified timeout is reached without any packet

    return (await client.socket.readPacketWithTimeout(timeout), client)

proc sendPacket*(client: ref Client, pkt: ServerPacket) {.async.} =
    ## Sends a packet to a client
    
    await client.socket.sendPacket(pkt)

proc sendPacketWithTimeout*(client: ref Client, pkt: ServerPacket, timeoutMs: int, raiseError: bool = true) {.async.} =
    ## Sends a packet to a client, optionally raising PacketTimeoutError if the specified timeout is reached without any packet
    
    await client.socket.sendPacketWithTimeout(pkt, timeoutMs, raiseError)

proc disconnect*(client: ref Client, reason: SDisconnectReason = SDisconnectReason.Unspecified, message: Option[string] = none[string]()) {.async.} =
    ## Disconnects a client, optionally with the specified reason, and message
    
    # Mark as disconnected and remove from server's connected clients list
    client.isConnected = false
    for i in 0..<client.server.clients.len:
        let cl = client.server.clients[i]
        if cl.id == client.id:
            client.server.clients.del(i)
            break

    # Try to send disconnect packet, but don't wait forever
    discard await withTimeout(client.sendPacket(ServerPacket(
        kind: ServerPacketType.Disconnect,
        id: genServerPacketId(),
        reply: blankPacketId,
        disconnectBody: SDisconnect(
            reason: reason,
            message: message.orEmpty()
        )
    )), DISCONNECT_MSG_TIMEOUT_MS)

    # Close client socket
    client.socket.close()

proc acknowledge*(pkt: ClientPacketHandle) {.async.} =
    ## Replies to a client packet with an Acknowledged packet
    
    let client = pkt.client
    let id = pkt.packet.id

    await client.sendPacket(ServerPacket(
        kind: ServerPacketType.Acknowledged,
        id: genServerPacketId(),
        reply: id
    ))

proc sendProtocolInfo*(client: ref Client): Future[PacketId] {.async.} =
    ## Sends a ProtocolInfo packet to the client and returns the packet ID
    
    let id = genServerPacketId()
    await client.sendPacket(ServerPacket(
        kind: ServerPacketType.ProtocolInfo,
        id: id,
        reply: blankPacketId,
        protocolInfoBody: SProtocolInfo(
            protocolVersion: PROTOCOL_VER,
            supportedProtocolVersions: @[PROTOCOL_VER]
        )
    ))
    return id

proc sendCapabilitiesInfo*(client: ref Client, capabilities: seq[ServerClientCapability]): Future[PacketId] {.async.} =
    ## Sends a CapabilitiesInfo packet with the specified capabilities to the client and returns the packet ID
    
    let id = genServerPacketId()
    await client.sendPacket(ServerPacket(
        kind: ServerPacketType.CapabilitiesInfo,
        id: id,
        reply: blankPacketId,
        capabilitiesInfoBody: SCapabilitiesInfo(
            capabilities: capabilities.map(cap => $cap),
            serverCapabilities: SERVER_CAPABILITIES
        )
    ))
    return id

# REPLIES #

proc replyDenied*(packetHandle: ClientPacketHandle, reason: SDeniedReason, message: Option[string] = none[string](), timeoutMs: int = 0, timeoutRaiseError: bool = true) {.async.} =
    ## Replies to a client packet with Denied
    
    let pkt = ServerPacket(
        kind: ServerPacketType.Denied,
        id: genServerPacketId(),
        reply: packetHandle.packet.id,
        deniedBody: SDenied(
            reason: reason,
            message: message.orEmpty()
        )
    )

    if timeoutMs > 0:
        await packetHandle.client.sendPacketWithTimeout(pkt, timeoutMs, timeoutRaiseError)
    else:
        await packetHandle.client.sendPacket(pkt)