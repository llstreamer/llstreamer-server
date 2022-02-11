import msgpack4nim
import std/[asyncnet, asyncdispatch, strformat]
import objects as packet_objects, enums, server, client
import ".."/[constants, utils, idgen, objects, exceptions]

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

# TODO: Reply

proc readPacket*(sock: AsyncSocket): Future[ClientPacket] {.async, raises: [ShortPacketHeaderError, UnknownPacketTypeError, MalformedPacketError, Exception].} =
    ## Reads a packet from an AsyncSocket
    
    # Read header
    let header = (await sock.recv(PACKET_HEADER_SIZE)).asBytes()

    # If empty or less than the defined packet header size, the client has disconnected
    let headerLen = header.len
    if headerLen < PACKET_HEADER_SIZE:
        raise newShortPacketHeaderError(fmt"Tried to read packet header, got {headerLen} bytes instead of {PACKET_HEADER_SIZE} bytes (client likely disconnected)", headerLen)

    # Parse packet header
    let packetTypeByte = (uint8) header[0]
    let id = bytesToInt[uint32](header.slice(1, 4))
    let reply = bytesToInt[uint32](header.slice(5, 8))
    let len = bytesToInt[uint16](header.slice(9, 10))

    # Check if known type
    if packetTypeByte > ClientPacketType.high.ord:
        # Read and discard the rest of the packet
        discard await sock.recv((int) len)

        # Raise exception
        raise newUnknownPacketTypeError(fmt"Got invalid client packet type ID {packetTypeByte}", packetTypeByte)
    else:
        # Read packet body
        let body = await sock.recv((int) len)

        # Parse body based on packet type
        let pktType = ClientPacketType(packetTypeByte)
        try:
            case pktType:
            of ClientPacketType.Protocol:
                return ClientPacket(
                    id: id,
                    reply: reply,
                    kind: pktType,
                    protocolBody: body.unpack(CProtocol)
                )
            of ClientPacketType.AuthRequest:
                return ClientPacket(
                    id: id,
                    reply: reply,
                    kind: pktType,
                    authRequestBody: body.unpack(CAuthRequest)
                )
            of ClientPacketType.CreateStream:
                return ClientPacket(
                    id: id,
                    reply: reply,
                    kind: pktType,
                    createStreamBody: body.unpack(CCreateStream)
                )
            of ClientPacketType.SendStreamData:
                return ClientPacket(
                    id: id,
                    reply: reply,
                    kind: pktType,
                    sendStreamDataBody: body.unpack(CSendStreamData)
                )
            of ClientPacketType.ViewStreamRequest:
                return ClientPacket(
                    id: id,
                    reply: reply,
                    kind: pktType,
                    viewStreamRequestBody: body.unpack(CViewStreamRequest)
                )
            of ClientPacketType.PublishedStreamsRequest:
                return ClientPacket(
                    id: id,
                    reply: reply,
                    kind: pktType,
                    publishedStreamsRequestBody: body.unpack(CPublishedStreamsRequest)
                )
        except ObjectConversionDefect:
            raise newMalformedPacketError("Got malformed packet body")

proc deserializePacketBody(id: NonBlankPacketId, reply: PacketId, body: seq[uint8]): ServerPacket =
    ## Deserializes a packet 
    
    echo "TODO"

# Todo: Expect packet, expect specific packet type