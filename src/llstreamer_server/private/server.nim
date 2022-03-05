import std/[options, asyncnet, asyncdispatch, times, strformat, sequtils, sugar, tables]
import packets/[readwrite, enums]
import packets/objects as packet_objects
import packets/enums as packet_enums
import packets/utils as packet_utils
import packets/client as client_packets
import packets/server as server_packets
import logging, objects, client, utils, constants, exceptions, timer, accounts, idgen, crypto

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
                await authReqHandle.replyDenied(
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
                echo "Denied"
                await authReqHandle.replyDenied(
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
        await authReqHandle.acknowledge()

        # TODO When modifying Client object, make sure to add capabilities, protocol version, etc (stuff that was negociated)
        # TODO After all of that is done, wait for packets and send them to handler.
        # TODO Use that system to facilitate things like waiting for replies, etc.

        # Socket is authorized now
        client.isAuthorized = true
        registerConnect(client)

        logInfo fmt"Client with IP {client.host} authenticated as {username}"

        # Loop and parse packets
        let sock = client.socket
        while client.isConnected:
            # Break out of loop if client is pipe
            if client.isPipe:
                break

            try:
                try:
                    # Read packet
                    let packet = await client.readPacket()

                    # TODO Handle packet
                except ShortPacketHeaderError as e:
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
        
        # TODO If client is streaming or watching stream, handle it here
        
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
            await client.disconnect()
        
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
