{.experimental: "codeReordering".}

import std/[options, asyncnet, asyncdispatch, times, strformat, sequtils, sugar, tables, locks]
import packets/[enums]
import packets/objects as packet_objects
import packets/enums as packet_enums
import packets/client as client_packets
import logging, objects, simpletypes, client, constants, exceptions, timer, accounts, idgen, events

proc serverFromConfig*(inst: ref Server, config: Config): ref Server =
    ## Configures a Server ref object with the provided config

    inst.config = config

    return inst

proc getClientById*(inst: ref Server, id: ClientId): Option[ref Client] =
    ## Returns the client with the specified ID, or none if not found
    
    for client in inst.clients:
        if client.id == id:
            return some(client)
    
    return none[ref Client]()

proc getClientsByUsername*(inst: ref Server, username: string): seq[ref Client] =
    ## Returns all clients connected to a server using the specified username
    
    var clients = newSeq[ref Client]()

    for client in inst.clients:
        if client.account.username == username:
            clients.add(client)
    
    return clients

proc getClientByUsername*(inst: ref Server, username: string): Option[ref Client] =
    ## Returns the first client found using the specified username, or none if not found
    
    for client in inst.clients:
        if client.account.username == username:
            return some(client)
    
    return none[ref Client]()

proc getClientsByHost*(inst: ref Server, host: string): seq[ref Client] =
    ## Returns all clients connected to a server with the specified IP address
    
    var clients = newSeq[ref Client]()

    for client in inst.clients:
        if client.host == host:
            clients.add(client)
    
    return clients

proc getClientByHost*(inst: ref Server, host: string): Option[ref Client] =
    ## Returns the first client found with the specified IP address, or none if not found
    
    for client in inst.clients:
        if client.host == host:
            return some(client)
    
    return none[ref Client]()

# EVENT HANDLERS #

proc onClientAuth*(server: ref Server, oneTime: bool, handler: proc(event: ref ServerClientAuthEvent) {.async.}): HandlerId =
    ## Registers a new client authentication handler
    
    # Generate ID
    let id = genHandlerId()

    # Create handler
    var hdlr: ref ServerClientAuthHandler
    new(hdlr)
    hdlr.id = id
    hdlr.oneTime = oneTime
    hdlr.handler = handler

    # Add it
    withLock server.clientAuthHandlersLock:
        server.clientAuthHandlers.add(hdlr)

    return id

proc removeClientAuthHandler*(server: ref Server, id: HandlerId) =
    ## Removes the client authentication handler with the specified ID
    
    withLock server.clientAuthHandlersLock:
        for i in 0..<server.clientAuthHandlers.len:
            let hdlr = server.clientAuthHandlers[i]
            if hdlr.id == id:
                server.clientAuthHandlers.del(i)
                break

proc onClientAuth*(server: ref Server, handler: proc(event: ref ServerClientAuthEvent) {.async.}): HandlerId =
    ## Registers a new client authentication handler
    
    return onClientAuth(server, false, handler)

proc oncePacket*(server: ref Server, handler: proc(event: ref ServerClientAuthEvent) {.async.}): HandlerId =
    ## Registers a new one-time client authentication handler
    
    return onClientAuth(server, true, handler)

# EVENT-BOUND UTILS #

proc dispatchClientAuthEvent*(server: ref Server, client: ref Client, awaitHandlers: bool = false, raiseErrors: bool = true) {.async.} =
    ## Dispatches a new client authentication event, optionally awaiting all packet handlers instead of letting them run out of order.
    ## If awaitHandlers is false, then raiseErrors is ignored, since errors cannot be raised by handlers called with asyncCheck.
    
    # Create event
    var event: ref ServerClientAuthEvent
    new(event)
    event.client = client

    # Iterate over handlers
    for i in 0..<server.clientAuthHandlers.len:
        let hdlr = server.clientAuthHandlers[i]

        # If this is a one-time handler, remove it from handler list
        if hdlr.oneTime:
            server.removeClientAuthHandler(hdlr.id)

        await execHandler(hdlr, event, awaitHandlers, raiseErrors, "Error occurred while running registered client authentication event handler")

# TODO onClientAuth, onceClientAuth, removeClientAuthHandler, dispatchClientAuthEvent
# TODO Do them in the order that client.nim does them

# MAIN INTERNAL CLIENT HANDLER LOOP #

proc initClientAndLoop(server: ref Server, client: ref Client) {.async.} =
    ## Initializes the provided client and starts a read loop for it
    
    # Check against global connection limit if maxClients > 0
    let maxClients = (int) server.config.maxClients
    if maxClients > 0 and server.clients.len >= maxClients:
        await client.disconnect(SDisconnectReason.TooManyClients)
        return

    # Check against per-host connection limit if maxClientsPerHost > 0
    let maxClientsPerHost = (int) server.config.maxClientsPerHost
    if maxClientsPerHost > 0:
        let host = client.host
        var hostClientCount = 0
        for c in server.clients:
            if c.host == host:
                inc hostClientCount
                if hostClientCount >= maxClientsPerHost:
                    await client.disconnect(SDisconnectReason.TooManyClients)
                    return

    logInfo "Connection from "&($client.host)

    # Handle new connection
    client.connectedOn = epochTime()
    client.isConnected = true
    server.clients.add(client)

    try:
        # Send protocol info
        let protoInfoId = await client.sendProtocolInfo()

        # Read protocol packet
        let protoPktHandle = await client.readPacketWithTimeout(CLIENT_PROTO_TIMEOUT_MS)
        let protoPkt = protoPktHandle.packet

        # Validate packet
        if protoPkt.reply != protoInfoId or protoPkt.kind != ClientPacketType.Protocol:
            await client.disconnect()
            return

        # Check protocol version
        # Right now, only one protocol version is supported
        if protoPkt.protocolBody.protocolVersion != PROTOCOL_VER:
            await client.disconnect()
            return

        # Send capabilities info
        # TODO If some of these features are disabled, do not include them
        let supportedCaps = @[
            ServerClientCapability.PublishStream,
            ServerClientCapability.StreamChat,
            ServerClientCapability.StreamCustodian
        ]
        let capsInfoId = await client.sendCapabilitiesInfo(supportedCaps)

        # Read capabilities packet
        let capsPktHandle = await client.readPacketWithTimeout(CLIENT_CAPS_TIMEOUT_MS)
        let capsPkt = capsPktHandle.packet

        # Validate packet
        if capsPkt.reply != capsInfoId or capsPkt.kind != ClientPacketType.Capabilities:
            await client.disconnect()
            return

        # Check capabilities
        let clientCaps = capsPkt.capabilitiesBody.capabilities
        let supportedCapsStrs = supportedCaps.map(cap => $cap)
        for cap in clientCaps:
            if cap notin supportedCapsStrs:
                await client.disconnect(SDisconnectReason.Unsupported, some(fmt"The capability '{cap}' is not supported"))
                return
        
        # Attach capabilities if all is well
        client.capabilities = clientCaps

        # Wait for authentication packet
        let authReqHandle = await client.readPacketWithTimeout(CLIENT_AUTH_TIMEOUT_MS)
        let authReq = authReqHandle.packet
        let authReqBody = authReq.authRequestBody

        # Collect info
        let username = authReqBody.username
        let password = authReqBody.password
        let isEphemeral = authReqBody.ephemeral
        let metadata = authReqBody.metadata

        # Fetch account with the same username
        let accRes = await fetchAccountByUsername(username)

        # If it exists, check if they share the same ephemeral value and credentials
        if accRes.isSome:
            let acc = accRes.get

            if acc.isEphemeral != isEphemeral:
                # Denying with reason "InvalidCredentials" is intentional here
                # If another reason was used here, a malicious individual attempting to discover whether an account exists could use different "isEphemeral" values while authenticating with an account to check whether it exists or not
                # It's best to be opaque about authentication errors to protect privacy of users
                discard await authReqHandle.replyDenied(
                    reason = SDeniedReason.InvalidCredentials,
                    timeoutMs = DISCONNECT_MSG_TIMEOUT_MS,
                    timeoutRaiseError = false
                )
                await client.disconnect(SDisconnectReason.Unauthorized)
                return
            
            # Verify password
            if await acc.verifyPassword(password):
                # Success, assign account
                client.account = acc
            else:
                discard await authReqHandle.replyDenied(
                    reason = SDeniedReason.InvalidCredentials,
                    timeoutMs = DISCONNECT_MSG_TIMEOUT_MS,
                    timeoutRaiseError = false
                )
                await client.disconnect(SDisconnectReason.Unauthorized)
                return
        else:
            # Create account and assign it
            var metadataOps: Option[Metadata]
            if metadata.len > 0:
                metadataOps = some(metadata)
            else:
                metadataOps = none[Metadata]()
            client.account = await createAccount(username, password, metadataOps, isEphemeral)

        # Acknowledge auth packet
        await authReqHandle.replyAcknowledged()

        # TODO When modifying Client object, make sure to add protocol version, etc (stuff that was negociated)

        # Socket is authorized now
        client.isAuthorized = true
        registerConnect(client)

        logInfo fmt"Client with IP {client.host} authenticated as {username}"

        # Run client auth hook
        await server.clientAuthHandler(client)

        # Dispatch client auth events
        await server.dispatchClientAuthEvent(client, false, false)

        # Loop and parse packets
        while client.isConnected and not client.isPipe:
            # Break out of loop if client is pipe
            if client.isPipe:
                break

            try:
                try:
                    # Read packet
                    let packet = await client.readPacket()

                    # Dispatch packet event
                    await client.dispatchPacketEvent(packet.packet)
                except ShortPacketHeaderError as e:
                    # TODO For any error here, dispatch client error event

                    if e.length > 0:
                        logWarn "Socket disconnected mid-way through packet transmission"
                    
                    registerDisconnect(client)
                    break
                except UnknownPacketTypeError as e:
                    logError e.msg
                except MalformedPacketError as e:
                    logError e.msg

            except:
                logError "Exception occurred during client read loop", getCurrentException(), getCurrentExceptionMsg()
        
        if client.isPipe:
            # TODO If client is streaming or watching stream, handle it here
            echo "TODO"
        
    except ShortPacketHeaderError:
        logWarn "Client disconnected before negociating a protocol version or authenticating"
    except ShortPacketBodyError:
        logWarn "Client disconnected before negociating a protocol version or authenticating"
    except PacketTimeoutError:
        logWarn "Protocol negociation or authentication could not be completed due to timeout"
    except PacketError as e:
        logError "Packet error occurred in client read loop", e, e.msg
    except Exception as e:
        logError "Error occurred in client read loop", e, e.msg
    finally:
        # Handle disconnect
        if not client.socket.isClosed:
            await client.disconnect(
                ignoreCancelation = true,
                clientDiscon = true
            )
        
        client.isConnected = false

        # TODO Remove from clients if finished authenticating

        logInfo "Disconnection from "&client.host

proc serverAcceptLoop(server: ref Server) {.async.} =
    ## Server connection accepting loop

    while server.acceptingConnections:
        let conn = await server.socket.accept()

        # Create client object
        var client = createClient(server, conn)

        # Start packet client handler loop
        asyncCheck server.initClientAndLoop(client)

# CLIENT ACTIONS HANDLER #

proc clientAuthHandler(server: ref Server, client: ref Client) {.async.} =
    ## Called when a client authenticates with the server
    
    discard client.onPacket(ClientPacketType.SelfInfoRequest, proc(event: ref ClientPacketEvent) {.async.} =
        # Fetch account info and reply with it
        # TODO
        discard await event.handle.replyDenied(SDeniedReason.Unsupported)
    )

# SERVER CONTROL #

proc startServer*(server: ref Server) {.async.} =
    ## Starts a server
    
    # Start timer
    server.timer = newTimer()
    startTimer(server.timer)
    
    # Create socket and listen
    var sock = newAsyncSocket()
    sock.setSockOpt(OptReuseAddr, true)
    sock.bindAddr(server.config.port, server.config.host)
    sock.listen()

    logInfo fmt"Listening on {server.config.host}:{(uint16) server.config.port}"

    # Assign properties
    server.socket = sock
    server.startedOn = epochTime()
    server.acceptingConnections = true

    await serverAcceptLoop(server)

proc stopServer*(server: ref Server) {.async.} =
    stopTimer(server.timer)
    clearAllTimers(server.timer)
    echo "TODO"
    # TODO Disconnect all clients, clear their events (after making sure disconnects are dispatched of course)