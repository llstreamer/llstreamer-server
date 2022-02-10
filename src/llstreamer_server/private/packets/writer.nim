import msgpack4nim
import std/[asyncnet, asyncdispatch]
import objects as packet_objects, enums
import ".."/[utils, idgen, objects]

proc serializePacket*(pkt: ServerPacket): string =
    ## Serializes a packet

    # Serialize body
    var body: string
    case pkt.kind:
    of ServerPacketType.ProtocolInfo:
        body = pkt.protocolInfoBody.pack()
    of ServerPacketType.Acknowledged:
        body = pkt.acknowledgedBody.pack()
    of ServerPacketType.Disconnect:
        body = pkt.disconnectBody.pack()
    of ServerPacketType.TooManyRequests:
        body = pkt.tooManyRequestsBody.pack()
    of ServerPacketType.Denied:
        body = pkt.deniedBody.pack()
    of ServerPacketType.Capabilities:
        body = pkt.capabilitiesBody.pack()
    of ServerPacketType.PlaintextMessage:
        body = pkt.plaintextMessageBody.pack()
    of ServerPacketType.StreamCreated:
        body = pkt.streamCreatedBody.pack()
    of ServerPacketType.PublishedStreams:
        body = pkt.publishedStreamsBody.pack()

    ## Packet layout:
    ## type: uint8
    ## id: uint32
    ## reply: uint32
    ## size: uint16
    ## body: ...
    var buf = newStringOfCap(1+4+4+2+body.len)

    buf &= (char) pkt.kind
    buf &= intToBytesSeq[PacketId](pkt.id).asStr()
    buf &= intToBytesSeq[PacketId](pkt.reply).asStr()
    buf &= intToBytesSeq[uint16]((uint16) body.len).asStr()
    buf &= body

    return buf

proc sendPacket*(sock: AsyncSocket, pkt: ServerPacket) {.async.} =
    ## Sends a packet to an AsyncSocket

    await sock.send(serializePacket(pkt))

proc sendPacket*(client: Client, pkt: ServerPacket) {.async.} =
    ## Sends a packet to a client
    
    await client.socket.sendPacket(pkt)