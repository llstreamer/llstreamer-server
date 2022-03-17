{.experimental: "codeReordering".}

import std/[options, asyncdispatch, asyncnet, nativesockets, sequtils, sugar, locks, strformat]
import idgen, objects, utils, constants, events, logging, exceptions
import packets/objects as packet_objects
import packets/enums as packet_enums
import packets/server as server_packets
import packets/client as client_packets
import packets/[enums, server, readwrite]

proc createClient*(server: ref Server, socket: AsyncSocket): ref Client =
    ## Configures a Client ref object with the provided AsyncSocket
    
    var inst = new(Client)

    let addrInfo = socket.getLocalAddr()

    inst.id = genClientId()
    inst.host = addrInfo[0]
    inst.port = addrInfo[1]
    inst.socket = socket
    inst.server = server

    return inst

proc readPacket*(client: ref Client): Future[ClientPacketHandle] {.async, inline.} =
    ## Reads a packet from a client

    return (await client.socket.readPacket(), client)

proc readPacketWithTimeout*(client: ref Client, timeoutMs: int): Future[ClientPacketHandle] {.async, inline.} =
    ## Reads a packet from a client, raising PacketTimeoutError if the specified timeout is reached without any packet

    return (await client.socket.readPacketWithTimeout(timeoutMs), client)

proc sendPacket*(client: ref Client, pkt: ServerPacket) {.async.} =
    ## Sends a packet to a client
    
    await client.socket.sendPacket(pkt)

proc sendPacketWithTimeout*(client: ref Client, pkt: ServerPacket, timeoutMs: int, raiseError: bool = true) {.async.} =
    ## Sends a packet to a client, optionally raising PacketTimeoutError if the specified timeout is reached without any packet
    
    await client.socket.sendPacketWithTimeout(pkt, timeoutMs, raiseError)

proc disconnect*(client: ref Client, reason: SDisconnectReason = SDisconnectReason.Unspecified, message: Option[string] = none[string](), ignoreCancelation: bool = false, clientDiscon: bool = false) {.async.} =
    ## Disconnects a client, optionally with the specified reason, and message.
    ## This proc is safe to call even if the client connection is already closed, because it checks the client socket state before trying to send anything.
    
    # Dispatch event, optionally ignoring cancelation
    await client.dispatchDisconnectEvent(clientDiscon, reason, message, true, false, not ignoreCancelation)
    
    # Mark as disconnected and remove from server's connected clients list
    withLock client.server.clientsLock:
        client.isConnected = false
        for i in 0..<client.server.clients.len:
            let cl = client.server.clients[i]
            if cl.id == client.id:
                client.server.clients.del(i)
                break

    if not client.socket.isClosed:
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

proc replyAcknowledged*(handle: ClientPacketHandle, timeoutMs: int = 0, timeoutRaiseError: bool = true): Future[PacketId] {.async.} =
    ## Replies to a client packet with an Acknowledged packet
    
    let id = genServerPacketId()

    let pkt = ServerPacket(
        kind: ServerPacketType.Acknowledged,
        id: id,
        reply: handle.packet.id
    )

    if timeoutMs > 0:
        await handle.client.sendPacketWithTimeout(pkt, timeoutMs, timeoutRaiseError)
    else:
        await handle.client.sendPacket(pkt)

proc replyDenied*(handle: ClientPacketHandle, reason: SDeniedReason, message: Option[string] = none[string](), timeoutMs: int = 0, timeoutRaiseError: bool = true): Future[PacketId] {.async.} =
    ## Replies to a client packet with a Denied packet
    
    let id = genServerPacketId()

    let pkt = ServerPacket(
        kind: ServerPacketType.Denied,
        id: id,
        reply: handle.packet.id,
        deniedBody: SDenied(
            reason: reason,
            message: message.orEmpty()
        )
    )

    if timeoutMs > 0:
        await handle.client.sendPacketWithTimeout(pkt, timeoutMs, timeoutRaiseError)
    else:
        await handle.client.sendPacket(pkt)
    
    return id

proc reply*[T](handle: ClientPacketHandle, packet: sink T, timeoutMs: int = 0, timeoutRaiseError: bool = true): Future[PacketId] {.async.} =
    ## Replies to a client packet.
    ## The provided ServerPacket will have its reply ID assigned to the ID in the ClientPacketHandle, and will be assigned a generated ID.
    
    let id = genServerPacketId()

    # Assign properties
    packet.id = id
    packet.reply = handle.packet.id

    if timeoutMs > 0:
        await handle.client.sendPacketWithTimeout(packet, timeoutMs)
    else:
        await handle.client.sendPacket(packet)

# EVENT HANDLERS #

proc onPacket*(client: ref Client, packetType: Option[ClientPacketType], oneTime: bool, handler: proc(event: ref ClientPacketEvent) {.async.}): HandlerId =
    ## Registers a new client packet handler.
    ## If marked as oneTime, the handler will only be used once before it is removed.
    ## If packetType is none, the handler will be called for any packet type, otherwise it will only apply to a specific type.

    # Generate ID
    let id = genHandlerId()

    # Create handler
    var hdlr: ref ClientPacketHandler
    new(hdlr)
    hdlr.id = id
    hdlr.filter = packetType
    hdlr.oneTime = oneTime
    hdlr.handler = handler

    # Add it
    withLock client.packetHandlersLock:
        client.packetHandlers.add(hdlr)

    return id

proc removePacketHandler*(client: ref Client, id: HandlerId) =
    ## Removes the client packet handler with the specified ID
    
    withLock client.packetHandlersLock:
        for i in 0..<client.packetHandlers.len:
            let hdlr = client.packetHandlers[i]
            if hdlr.id == id:
                client.packetHandlers.del(i)
                break

proc onPacket*(client: ref Client, handler: proc(event: ref ClientPacketEvent) {.async.}): HandlerId =
    ## Registers a new client packet handler for any packet type
    
    return onPacket(client, none[ClientPacketType](), false, handler)

proc oncePacket*(client: ref Client, packetType: ClientPacketType, handler: proc(event: ref ClientPacketEvent) {.async.}): HandlerId =
    ## Registers a new one-time client packet handler for a specific packet type
    
    return onPacket(client, some(packetType), true, handler)

proc onPacket*(client: ref Client, packetType: ClientPacketType, handler: proc(event: ref ClientPacketEvent) {.async.}): HandlerId =
    ## Registers a new client packet handler for a specific packet type
    
    return onPacket(client, some(packetType), false, handler)

proc oncePacket*(client: ref Client, handler: proc(event: ref ClientPacketEvent) {.async.}): HandlerId =
    ## Registers a new one-time client packet handler for any packet type
    
    return onPacket(client, none[ClientPacketType](), true, handler)

proc onDisconnect*(client: ref Client, oneTime: bool, handler: proc(event: ref ClientDisconnectEvent) {.async.}): HandlerId =
    ## Registers a new client disconnection handler
    
    # Generate ID
    let id = genHandlerId()

    # Create handler
    var hdlr: ref ClientDisconnectHandler
    new(hdlr)
    hdlr.id = id
    hdlr.oneTime = oneTime
    hdlr.handler = handler

    # Add it
    withLock client.disconnectHandlersLock:
        client.disconnectHandlers.add(hdlr)
    
    return id

proc removeDisconnectHandler(client: ref Client, id: HandlerId) =
    ## Removes the client disconnection handler with the specified ID
    
    withLock client.disconnectHandlersLock:
        for i in 0..<client.disconnectHandlers.len:
            let hdlr = client.disconnectHandlers[i]
            if hdlr.id == id:
                client.disconnectHandlers.del(i)
                break

proc onDisconnect*(client: ref Client, handler: proc(event: ref ClientDisconnectEvent) {.async.}): HandlerId =
    ## Registers a new client disconnection handler
    
    onDisconnect(client, false, handler)

proc onceDisconnect*(client: ref Client, handler: proc(event: ref ClientDisconnectEvent) {.async.}): HandlerId =
    ## Registers a new one-time client disconnection handler
    
    onDisconnect(client, true, handler)

proc onBecomePipe*(client: ref Client, oneTime: bool, handler: proc(event: ref ClientBecomePipeEvent) {.async.}): HandlerId =
    ## Registers a new client become pipe handler
    
    # Generate ID
    let id = genHandlerId()

    # Create handler
    var hdlr: ref ClientBecomePipeHandler
    new(hdlr)
    hdlr.id = id
    hdlr.oneTime = oneTime
    hdlr.handler = handler

    # Add it
    withLock client.becomePipeHandlersLock:
        client.becomePipeHandlers.add(hdlr)
    
    return id

proc removeBecomePipeHandler(client: ref Client, id: HandlerId) =
    ## Removes the client become pipe handler with the specified ID
    
    withLock client.becomePipeHandlersLock:
        for i in 0..<client.becomePipeHandlers.len:
            let hdlr = client.becomePipeHandlers[i]
            if hdlr.id == id:
                client.becomePipeHandlers.del(i)
                break

proc onBecomePipe*(client: ref Client, handler: proc(event: ref ClientBecomePipeEvent) {.async.}): HandlerId =
    ## Registers a new client disconnection handler
    
    onBecomePipe(client, false, handler)

proc onceBecomePipe*(client: ref Client, handler: proc(event: ref ClientBecomePipeEvent) {.async.}): HandlerId =
    ## Registers a new one-time client disconnection handler
    
    onBecomePipe(client, true, handler)

# EVENT-BOUND UTILS #

proc dispatchPacketEvent*(client: ref Client, packet: ClientPacket, awaitHandlers: bool = false, raiseErrors: bool = true) {.async.} =
    ## Dispatches a new client packet event, optionally awaiting all packet handlers instead of letting them run out of order.
    ## If awaitHandlers is false, then raiseErrors is ignored, since errors cannot be raised by handlers called with asyncCheck.
    
    # Create event
    var event: ref ClientPacketEvent
    new(event)
    event.client = client
    event.packet = packet
    event.handle = (packet, client)

    # Iterate over handlers
    for i in 0..<client.packetHandlers.len:
        let hdlr = client.packetHandlers[i]

        # Check if handler applies to packet
        if hdlr.filter.isNone or hdlr.filter.get == packet.kind:
            # If this is a one-time handler, remove it from handler list
            if hdlr.oneTime:
                client.removePacketHandler(hdlr.id)

            await execHandler(hdlr, event, awaitHandlers, raiseErrors, "Error occurred while running registered client packet event handler")

proc dispatchDisconnectEvent*(client: ref Client, clientDiscon: bool, reason: SDisconnectReason, message: Option[string], awaitHandlers: bool = false, raiseErrors: bool = true, errorIfCanceled: bool = true) {.async.} =
    ## Dispatches a new client disconnect event, optionally awaiting all disconnect handlers and collecting their cancelation response instead of letting them run out of order.
    ## If awaitHandlers is false, then raiseErrors is ignored, since errors cannot be raised by handlers called with asyncCheck.
    ## If errorIfCanceled is true, then event handlers will all be awaited, and EventCanceledError will be raised if the event ends up being marked as canceled.
    
    # Create event
    var event: ref ClientDisconnectEvent
    new(event)
    event.client = client
    event.clientDisconnected = clientDiscon
    event.reason = reason
    event.message = message

    # Iterate over handlers
    for i in 0..<client.disconnectHandlers.len:
        let hdlr = client.disconnectHandlers[i]

        # If this is a one-time handler, remove it from handler list
        if hdlr.oneTime:
            client.removeDisconnectHandler(hdlr.id)

            await execHandler(hdlr, event, errorIfCanceled or awaitHandlers, raiseErrors, "Error occurred while running registered client disconnect event handler")

            if errorIfCanceled:
                raiseErrorIfCanceled(event, "The client was not disconnected because an event handler canceled the action")

proc dispatchBecomePipeEvent*(client: ref Client, uplPipe: bool, dlPipe: bool, reason: SDisconnectReason, message: Option[string], awaitHandlers: bool = false, raiseErrors: bool = true, errorIfCanceled: bool = true) {.async.} =
    ## Dispatches a new client become pipe event, optionally awaiting all disconnect handlers and collecting their cancelation response instead of letting them run out of order.
    ## If awaitHandlers is false, then raiseErrors is ignored, since errors cannot be raised by handlers called with asyncCheck.
    ## If errorIfCanceled is true, then event handlers will all be awaited, and EventCanceledError will be raised if the event ends up being marked as canceled.
    
    # Create event
    var event: ref ClientBecomePipeEvent
    new(event)
    event.client = client
    event.isUploadPipe = uplPipe
    event.isDownloadPipe = dlPipe

    # Iterate over handlers
    for i in 0..<client.becomePipeHandlers.len:
        let hdlr = client.becomePipeHandlers[i]

        # If this is a one-time handler, remove it from handler list
        if hdlr.oneTime:
            client.removeBecomePipeHandler(hdlr.id)

            await execHandler(hdlr, event, errorIfCanceled or awaitHandlers, raiseErrors, "Error occurred while running registered client become pipe event handler")

            if errorIfCanceled:
                raiseErrorIfCanceled(event, "The client was not able to become a pipe because an event handler canceled the action")


proc nextPacket*(client: ref Client, packetType: Option[ClientPacketType], timeoutMs: Option[int] = none[int]()): Future[ClientPacketHandle] =
    ## Waits for the next packet (optionally of a specific type) from the client and returns it.
    ## The returned future fails if the client disconnects, becomes a pipe, or some other event occurs which would render the call obsolete.
    ## If a timeout is specified, a PacketTimeoutError will be raised.
    
    let future = newFuture[ClientPacketHandle]("client.nextPacket")
    
    # Handler IDs
    var recvPktId: HandlerId
    var disconId: HandlerId
    var becomePipeId: HandlerId

    proc removeHdlrs(includePktHdlr: bool) =
        if includePktHdlr:
            client.removePacketHandler(recvPktId)
        client.removeDisconnectHandler(disconId)
        client.removeBecomePipeHandler(becomePipeId)

    proc fail(msg: string) =
        # Remove handlers and fail future
        removeHdlrs(true)
        future.fail(newEventInterruptedError(msg))
    
    proc complete(handle: ClientPacketHandle) =
        # Remove handlers and complete future
        removeHdlrs(false)
        future.complete(handle)
    
    # Timeout if specified
    if timeoutMs.isSome:
        addTimer(timeoutMs.get, true, proc(fd: AsyncFD): bool =
            if not future.finished:
                removeHdlrs(true)
                future.fail(newPacketTimeoutError("The client packet timeout was reached before a packet was encountered", timeoutMs.get))
                return true
        )

    # Resolve future once a packet is received
    recvPktId = client.onPacket(packetType, true, proc(event: ref ClientPacketEvent) {.async.} = complete(event.handle))

    # Create handlers to watch for certain events that would render this call obsolete
    disconId = client.onceDisconnect(proc(event: ref ClientDisconnectEvent) {.async.} = fail("The client disconnected before a packet could be read"))
    becomePipeId = client.onceBecomePipe(proc(event: ref ClientBecomePipeEvent) {.async.} = fail("The client became a pipe before a packet could be read"))

    return future

proc nextPacket*(client: ref Client, timeoutMs: Option[int] = none[int]()): Future[ClientPacketHandle] =
    ## Waits for the next packet from the client and returns it.
    ## If a timeout is specified, a PacketTimeoutError will be raised.
    
    return nextPacket(client, none[ClientPacketType](), timeoutMs)

proc nextPacket*(client: ref Client, packetType: ClientPacketType, timeoutMs: Option[int] = none[int]()): Future[ClientPacketHandle] =
    ## Waits for the next packet of a specific type from the client and returns it.
    ## If a timeout is specified, a PacketTimeoutError will be raised.
    
    return nextPacket(client, some(packetType), timeoutMs)

proc nextReply*(client: ref Client, packetId: PacketId, packetType: Option[ClientPacketType], timeoutMs: Option[int] = none[int]()): Future[ClientPacketHandle] =
    ## Waits for the next packet replying to the specified packet ID.
    ## If packetType is some and a packet is received with a type that does not match, a WrongClientPacketTypeError error will be raised.
    ## If a timeout is specified, a PacketTimeoutError will be raised.
    
    let future = newFuture[ClientPacketHandle]("client.nextReply")
    
    # Handler IDs
    var recvPktId: HandlerId
    var disconId: HandlerId
    var becomePipeId: HandlerId

    proc removeHdlrs(includePktHdlr: bool) =
        if includePktHdlr:
            client.removePacketHandler(recvPktId)
        client.removeDisconnectHandler(disconId)
        client.removeBecomePipeHandler(becomePipeId)

    proc fail(msg: string) =
        # Remove handlers and fail future
        removeHdlrs(true)
        future.fail(newEventInterruptedError(msg))
    
    proc complete(handle: ClientPacketHandle) =
        # Remove handlers and complete future
        removeHdlrs(false)
        future.complete(handle)
    
    # Timeout if specified
    if timeoutMs.isSome:
        addTimer(timeoutMs.get, true, proc(fd: AsyncFD): bool =
            if not future.finished:
                removeHdlrs(true)
                future.fail(newPacketTimeoutError("The client packet timeout was reached before a packet was encountered", timeoutMs.get))
                return true
        )

    # Observe incoming packets
    recvPktId = client.onPacket(proc(event: ref ClientPacketEvent) {.async.} =
        let pkt = event.packet

        # Check reply ID and see if it matches the one specified
        if pkt.reply == packetId:
            # No matter the outcome from this point onward, handlers still need to be removed
            removeHdlrs(true)

            # If type is specified and the type doesn't match, raise error
            if packetType.isSome and pkt.kind != packetType.get:
                future.fail(newWrongClientPacketTypeError(fmt"Expected client's reply to packet ID {packetId} to be of type {packetType.get}, but instead got {pkt.kind}", packetType.get, pkt.kind))
            else:
                # If all is well, complete handler
                complete(event.handle)
    )

    # Create handlers to watch for certain events that would render this call obsolete
    disconId = client.onceDisconnect(proc(event: ref ClientDisconnectEvent) {.async.} = fail("The client disconnected before a packet could be read"))
    becomePipeId = client.onceBecomePipe(proc(event: ref ClientBecomePipeEvent) {.async.} = fail("The client became a pipe before a packet could be read"))

    return future