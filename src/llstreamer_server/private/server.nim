import std/[options, asyncnet, asyncdispatch, times, strformat]

import logging, objects, client, utils, constants

type
    Server* = object
        ## Server state

        host*: string ## The host the server is currently bound to
        port*: Port ## The port the server is currently bound to
        password*: Option[string] ## The server's password, or none for an open server
        allowPublishStreams*: bool ## Whether clients are allowed to publish their streams
        authTimeoutSeconds*: uint16 ## The timeout in seconds before unauthorized clients will be disconnected
        maxClients*: uint32 ## The maximum amount of concurrent clients allowed, or 0 for unlimited
        maxStreams*: uint32 ## The maximum amount of concurrent streams allowed, or 0 for unlimited
        maxClientsPerHost*: uint32 ## The maximum amount of concurrent clients per IP address, or 0 for unlimited
        enableManagement*: bool ## Whether to enable server management
        managerPassword*: Option[string] ## The password required for clients to become managers, or none to not require one
        managerWhitelist*: Option[seq[string]] ## The list of IP addresses allowed to become managers, or none to not enable the whitelist

        startedOn*: float ## When the server started
        acceptingConnections*: bool ## Whether the server is accepting new connections

        socket*: AsyncSocket ## The underlying server socket

        clients*: seq[ref Client] ## All connected clients
        authorizedClients*: seq[ref Client] ## All authorized clients
        streamingClients*: seq[ref Client] ## All currently streaming clients
        managerClients*: seq[ref Client] ## All clients which are server managers

proc serverFromConfig*(inst: ref Server, config: Config): ref Server =
    ## Configures a Server ref object with the provided config

    inst.host = config.host
    inst.port = config.port
    inst.password = config.password
    inst.allowPublishStreams = config.allowPublishStreams
    inst.authTimeoutSeconds = config.authTimeoutSeconds
    inst.maxClients = config.maxClients
    inst.maxStreams = config.maxStreams
    inst.maxClientsPerHost = config.maxClientsPerHost
    inst.enableManagement = config.enableManagement
    inst.managerPassword = config.managerPassword
    inst.managerWhitelist = config.managerWhitelist

    return inst

proc getClientsByUsername*(inst: ref Server, username: string): seq[ref Client] =
    ## Returns all clients connected to a server using the specified username
    
    var clients = newSeq[ref Client]()

    for client in inst.clients:
        if client.username == username:
            clients.add(client)
    
    return clients

proc getClientByUsername*(inst: ref Server, username: string): Option[ref Client] =
    ## Returns the first client found using the specified username, or none if not found
    
    for client in inst.clients:
        if client.username == username:
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
    
    # Check against connection limits
    # TODO

    # Disconnect when auth timeout has been reached
    # TODO

    # Socket is connected now
    client.connectedOn = epochTime()
    client.isConnected = true
    server.clients.add(client)

    logInfo "Connection from "&client.host

    # Loop and parse packets
    let sock = client.socket
    while client.isConnected:
        try:
            # Read packet header
            let header = (await sock.recv(PACKET_HEADER_SIZE)).asBytes

            # If empty or less than the defined packet header size, the client has disconnected
            if header.len < PACKET_HEADER_SIZE:
                client.isConnected = false
                break

            # Parse packet header
            let packetTypeByte = (uint8) header[0]
            let id = bytesToInt[uint32](header.slice(1, 4))
            let reply = bytesToInt[uint32](header.slice(5, 8))
            let len = bytesToInt[uint16](header.slice(9, 10))

            # Check if known type
            # if packetTypeByte > ClientPacketType.high.ord:
            #     logError fmt"Invalid client packet type ID {packetTypeByte}, discarding"

            #     # Read and discard the rest of the packet
            #     discard await sock.recv((int) len)
            # else:
            #     let packetType = ClientPacketType(packetTypeByte)
            #     echo packetType

            #     let body = (await sock.recv((int) len)).asBytes
            #     echo body

            #     echo "Now parsing packet..."
            #     let packet = parsePacket(packetType, id, reply, body)

            #     echo packet

        except:
            logError "Exception occurred during client read loop", getCurrentException(), getCurrentExceptionMsg()
    
    # Handle disconnect
    logInfo "Disconnection from "&client.host

proc serverAcceptLoop(server: ref Server) {.async.} =
    ## Server connection accepting loop

    while server.acceptingConnections:
        let conn = await server.socket.accept()

        # Create client object
        var client = (ref Client)().clientFromSocket(conn)

        # Start packet client handler loop
        asyncCheck server.initClientAndLoop(client)


proc startServer*(server: ref Server) {.async.} =
    ## Starts a server
    
    # Create socket and listen
    var sock = newAsyncSocket()
    sock.setSockOpt(OptReuseAddr, true)
    sock.bindAddr(server.port, server.host)
    sock.listen()

    echo "Listening on "&server.host&":"&($(uint16) server.port)

    # Assign properties
    server.socket = sock
    server.startedOn = epochTime()
    server.acceptingConnections = true

    await serverAcceptLoop(server)
