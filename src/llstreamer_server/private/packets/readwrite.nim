import msgpack4nim
import std/[asyncnet, asyncdispatch, strformat]
import objects as packet_objects, enums, server, client
import ".."/[utils, idgen, exceptions]

# Packet header size defined here for clarity and convenience
const PACKET_HEADER_SIZE* = 1 + 4 + 4 + 2

proc deserializePacketBody*(pktType: ClientPacketType, id: NonBlankPacketId, reply: PacketId, bodyBytes: seq[uint8]): ClientPacket {.raises: MalformedPacketError.} =
    ## Deserializes a packet body
    
    let body = bodyBytes.asStr()
    
    # Parse body based on packet type
    try:
        case pktType:
        of ClientPacketType.Protocol:
            return ClientPacket(
                id: id,
                reply: reply,
                kind: pktType,
                protocolBody: body.unpack(CProtocol)
            )
        of ClientPacketType.Capabilities:
            return ClientPacket(
                id: id,
                reply: reply,
                kind: pktType,
                capabilitiesBody: body.unpack(CCapabilities)
            )
        of ClientPacketType.AuthRequest:
            return ClientPacket(
                id: id,
                reply: reply,
                kind: pktType,
                authRequestBody: body.unpack(CAuthRequest)
            )
        of ClientPacketType.SelfInfoRequest:
            return ClientPacket(
                id: id,
                reply: reply,
                kind: pktType,
                selfInfoRequestBody: body.unpack(CSelfInfoRequest)
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

proc deserializePacketBody*(pktType: ServerPacketType, id: NonBlankPacketId, reply: PacketId, body: string): ServerPacket {.raises: MalformedPacketError.} =
    ## Deserializes a packet body
    
    # Parse body based on packet type
    try:
        case pktType:
        of ServerPacketType.Upgrade:
            return ServerPacket(
                id: id,
                reply: reply,
                kind: pktType,
                upgradeBody: body.unpack(SUpgrade)
            )
        of ServerPacketType.ProtocolInfo:
            return ServerPacket(
                id: id,
                reply: reply,
                kind: pktType,
                protocolInfoBody: body.unpack(SProtocolInfo)
            )
        of ServerPacketType.CapabilitiesInfo:
            return ServerPacket(
                id: id,
                reply: reply,
                kind: pktType,
                capabilitiesInfoBody: body.unpack(SCapabilitiesInfo)
            )
        of ServerPacketType.Acknowledged:
            return ServerPacket(
                id: id,
                reply: reply,
                kind: pktType,
                acknowledgedBody: body.unpack(SAcknowledged)
            )
        of ServerPacketType.Disconnect:
            return ServerPacket(
                id: id,
                reply: reply,
                kind: pktType,
                disconnectBody: body.unpack(SDisconnect)
            )
        of ServerPacketType.TooManyRequests:
            return ServerPacket(
                id: id,
                reply: reply,
                kind: pktType,
                tooManyRequestsBody: body.unpack(STooManyRequests)
            )
        of ServerPacketType.Denied:
            return ServerPacket(
                id: id,
                reply: reply,
                kind: pktType,
                deniedBody: body.unpack(SDenied)
            )
        of ServerPacketType.PlaintextMessage:
            return ServerPacket(
                id: id,
                reply: reply,
                kind: pktType,
                plaintextMessageBody: body.unpack(SPlaintextMessage)
            )
        of ServerPacketType.SelfInfo:
            return ServerPacket(
                id: id,
                reply: reply,
                kind: pktType,
                selfInfoBody: body.unpack(SSelfInfo)
            )
        of ServerPacketType.StreamCreated:
            return ServerPacket(
                id: id,
                reply: reply,
                kind: pktType,
                streamCreatedBody: body.unpack(SStreamCreated)
            )
        of ServerPacketType.PublishedStreams:
            return ServerPacket(
                id: id,
                reply: reply,
                kind: pktType,
                publishedStreamsBody: body.unpack(SPublishedStreams)
            )
    except ObjectConversionDefect:
        raise newMalformedPacketError("Got malformed packet body")

proc serializePacket*(pkt: ClientPacket): string =
    ## Serializes a packet

    # Serialize body
    var body: string
    case pkt.kind:
    of ClientPacketType.Protocol:
        body = pkt.protocolBody.pack()
    of ClientPacketType.Capabilities:
        body = pkt.capabilitiesBody.pack()
    of ClientPacketType.AuthRequest:
        body = pkt.authRequestBody.pack()
    of ClientPacketType.SelfInfoRequest:
        body = pkt.selfInfoRequestBody.pack()
    of ClientPacketType.CreateStream:
        body = pkt.createStreamBody.pack()
    of ClientPacketType.SendStreamData:
        body = pkt.sendStreamDataBody.pack()
    of ClientPacketType.ViewStreamRequest:
        body = pkt.viewStreamRequestBody.pack()
    of ClientPacketType.PublishedStreamsRequest:
        body = pkt.publishedStreamsRequestBody.pack()

    ## Packet layout:
    ## type: uint8
    ## id: uint32
    ## reply: uint32
    ## size: uint16
    ## body: ...
    var buf = newStringOfCap(PACKET_HEADER_SIZE+body.len)

    buf &= (char) pkt.kind
    buf &= intToBytesSeq[PacketId](pkt.id).asStr()
    buf &= intToBytesSeq[PacketId](pkt.reply).asStr()
    buf &= intToBytesSeq[uint16]((uint16) body.len).asStr()
    buf &= body

    return buf

proc serializePacket*(pkt: ServerPacket): string =
    ## Serializes a packet

    # Serialize body
    var body: string
    case pkt.kind:
    of ServerPacketType.Upgrade:
        body = pkt.upgradeBody.pack()
    of ServerPacketType.ProtocolInfo:
        body = pkt.protocolInfoBody.pack()
    of ServerPacketType.CapabilitiesInfo:
        body = pkt.capabilitiesInfoBody.pack()
    of ServerPacketType.Acknowledged:
        body = pkt.acknowledgedBody.pack()
    of ServerPacketType.Disconnect:
        body = pkt.disconnectBody.pack()
    of ServerPacketType.TooManyRequests:
        body = pkt.tooManyRequestsBody.pack()
    of ServerPacketType.Denied:
        body = pkt.deniedBody.pack()
    of ServerPacketType.PlaintextMessage:
        body = pkt.plaintextMessageBody.pack()
    of ServerPacketType.SelfInfo:
        body = pkt.selfInfoBody.pack()
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
    var buf = newStringOfCap(PACKET_HEADER_SIZE+body.len)

    buf &= (char) pkt.kind
    buf &= intToBytesSeq[PacketId](pkt.id).asStr()
    buf &= intToBytesSeq[PacketId](pkt.reply).asStr()
    buf &= intToBytesSeq[uint16]((uint16) body.len).asStr()
    buf &= body

    return buf

proc sendPacket*(sock: AsyncSocket, pkt: ServerPacket) {.async.} =
    ## Sends a packet to an AsyncSocket

    await sock.send(serializePacket(pkt))

proc sendPacket*(sock: AsyncSocket, pkt: ClientPacket) {.async.} =
    ## Sends a packet to an AsyncSocket

    await sock.send(serializePacket(pkt))

proc sendPacketWithTimeout*(sock: AsyncSocket, pkt: ServerPacket, timeoutMs: int, raiseError: bool = true) {.async.} =
    ## Sends a packet to an AsyncSocket, optionally raising PacketTimeoutError if the specified timeout is reached without any packet

    let fut = sock.send(serializePacket(pkt))
    if await fut.withTimeout(timeoutMs):
        await fut
    elif raiseError:
        raise newPacketTimeoutError("Timeout reached before packet was sent", timeoutMs)

proc sendPacketWithTimeout*(sock: AsyncSocket, pkt: ClientPacket, timeoutMs: int, raiseError: bool = true) {.async.} =
    ## Sends a packet to an AsyncSocket, optionally raising PacketTimeoutError if the specified timeout is reached without any packet
    
    let fut = sock.send(serializePacket(pkt))
    if await fut.withTimeout(timeoutMs):
        await fut
    elif raiseError:
        raise newPacketTimeoutError("Timeout reached before packet was sent", timeoutMs)

proc readPacketHeader*(sock: AsyncSocket, typeHigh: uint8, discardBodyOnError: bool): Future[PacketHeader] {.async, raises: [ShortPacketHeaderError, UnknownPacketTypeError, MalformedPacketError, Exception].} =
    ## Reads a packet header (works on client and server packets)

    # Read header
    let header = (await sock.recv(PACKET_HEADER_SIZE)).asBytes()

    # If empty or less than the defined packet header size, the socket has most likely disconnected
    let headerLen = header.len
    if headerLen < PACKET_HEADER_SIZE:
        raise newShortPacketHeaderError(fmt"Tried to parse packet header, got {headerLen} bytes instead of {PACKET_HEADER_SIZE} bytes (socket likely disconnected)", (uint8) headerLen)
    
    # Parse packet header
    let typeByte = (uint8) header[0]
    let id = bytesToInt[uint32](header.slice(1, 4))
    let reply = bytesToInt[uint32](header.slice(5, 8))
    let size = bytesToInt[uint16](header.slice(9, 10))

    # Check if ID is valid
    if id < 1:
        if discardBodyOnError:
            discard await sock.recv((int) size)

        raise newMalformedPacketError("Got packet with 0 as its ID, but 0 signifies no ID and cannot be used as an actual packet ID")

    # Check if type byte is invalid
    if typeByte > typeHigh:
        if discardBodyOnError:
            discard await sock.recv((int) size)

        raise newUnknownPacketTypeError(fmt"Got invalid client packet type ID {typeByte}", typeByte)

    # Return header
    return PacketHeader(
        typeByte: typeByte,
        id: id,
        reply: reply,
        size: size
    )

proc readPacketBody*(sock: AsyncSocket, header: PacketHeader): Future[seq[uint8]] {.async, raises: [ShortPacketBodyError, Exception].} =
    ## Reads a packet body (works on client and server packets)
    
    # Read bytes
    let body = (await sock.recv((int) header.size)).asBytes()

    # If empty or less than the requested packet body size, the socket has most likely disconnected
    let bodyLen = (uint16) body.len
    if bodyLen < header.size:
        raise newShortPacketBodyError(fmt"Tried to read packet body, got {bodyLen} bytes instead of {header.size} bytes (socket likely disconnected)", (uint16) bodyLen)

    # Return body
    return body

proc discardPacketBody*(sock: AsyncSocket, header: PacketHeader) {.async.} =
    ## Discards a packet body
    
    discard await sock.recv((int) header.size)

proc readPacket*(sock: AsyncSocket): Future[ClientPacket] {.async, raises: [ShortPacketHeaderError, UnknownPacketTypeError, MalformedPacketError, Exception].} =
    ## Reads a packet from an AsyncSocket

    # Read header
    let header = await sock.readPacketHeader(ClientPacketType.high.ord, true)

    # If all is well, read packet body and deserialize it
    let body = await sock.readPacketBody(header)
    return deserializePacketBody(ClientPacketType(header.typeByte), header.id, header.reply, body)

proc readPacketWithTimeout*(sock: AsyncSocket, timeoutMs: int): Future[ClientPacket] {.async, raises: [ShortPacketHeaderError, UnknownPacketTypeError, MalformedPacketError, PacketTimeoutError, Exception].} =
    ## Reads a packet from an AsyncSocket, raising PacketTimeoutError if the specified timeout is reached without any packet
    
    let fut = sock.readPacket()
    if await fut.withTimeout(timeoutMs):
        return await fut
    else:
        raise newPacketTimeoutError("Timeout reached before receiving a packet", timeoutMs)