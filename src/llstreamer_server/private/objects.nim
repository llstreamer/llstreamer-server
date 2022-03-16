import std/[options, asyncnet, nativesockets, json, locks]
import packets/[objects, enums]
import idgen, utils, timer, events, simpletypes

## Objects

type
    DatabaseConfigKind* {.pure.} = enum
        ## Types of database configurations
        
        Memory
        Sqlite
        Postgres
        MySql

    DatabaseConfig* = object
        ## Database configuration

        case kind*: DatabaseConfigKind
        of DatabaseConfigKind.Memory:
            useQueryThread*: bool
        of DatabaseConfigKind.Sqlite:
            sqliteDbPath*: string
        of DatabaseConfigKind.Postgres:
            pgDb*: string
            pgAddress*: string
            pgPort*: Natural
            pgUser*: string
            pgPass*: string
            pgPoolSize*: Natural
        of DatabaseConfigKind.MySql:
            mysqlDb*: string
            mysqlAddress*: string
            mysqlPort*: Natural
            mysqlUser*: string
            mysqlPass*: string
            mysqlPoolSize*: Natural
    
    BaseConfig* = ref object of RootObj
        ## Object representation of the server configuration, without parsed database configuration
        
        host*: string ## The host to bind to
        port*: Port ## The port to bind to
        password*: Option[string] ## The password required to connect to the server, or none for an open server
        allowCreateAccounts*: bool ## Whether clients are freely allowed to create accounts
        allowPublishStreams*: bool ## Whether clients are allowed to publish their streams
        authTimeoutSeconds*: uint16 ## The timeout in seconds before unauthorized clients will be disconnected
        maxClients*: uint32 ## The maximum amount of concurrent clients allowed, or 0 for unlimited
        maxStreams*: uint32 ## The maximum amount of concurrent streams allowed, or 0 for unlimited
        maxClientsPerHost*: uint32 ## The maximum amount of concurrent clients per IP address, or 0 for unlimited
        enableManagement*: bool ## Whether to enable server management
        streamKeepAliveSeconds*: uint16 ## How long to preserve a stream in seconds while there is no input before it is deleted
        managerPassword*: Option[string] ## The password required for clients to become managers, or none to not require one
        managerWhitelist*: Option[seq[string]] ## The list of IP addresses allowed to become managers, or none to not enable the whitelist
        databaseType*: string ## The database type name
        database*: JsonNode ## The raw database configuration (may not match databaseConfig, is only present for JSON serialization purposes)

    Config* = ref object of BaseConfig
        ## Object representation of the server configuration
        
        databaseConfig*: DatabaseConfig ## The database configuration
    
    ServerClientAuthEvent* = object of Event
        ## An event used when a client authenticates with the server
        
        client*: ref Client ## The client that authenticated
    
    ServerClientAuthHandler* = object of EventHandler[ServerClientAuthEvent]
        ## A server client authentication event handler

    Server* = object
        ## Server state

        config*: Config ## The server config

        startedOn*: float ## When the server started
        acceptingConnections*: bool ## Whether the server is accepting new connections

        socket*: AsyncSocket ## The underlying server socket

        clients*: seq[ref Client] ## All connected clients
        clientsLock*: Lock ## The lock that governs the clients seq
        authorizedClients*: seq[ref Client] ## All authorized clients
        streamingClients*: seq[ref Client] ## All currently streaming clients
        managerClients*: seq[ref Client] ## All clients which are server managers

        # Event handlers
        clientAuthHandlers*: seq[ref ServerClientAuthHandler] ## Handlers that are used when a client authenticates with the server
        clientAuthHandlersLock*: Lock ## The lock that governs the clientAuthHandlers seq

        timer*: ref Timer ## The Timer instance used by the server

    ClientPacketHandle* = tuple[packet: ClientPacket, client: ref Client]
        ## Handle for client packets (used to reply)

    ClientPacketEvent* = object of Event
        ## A client packet event
        
        client*: ref Client ## The client
        packet*: ClientPacket ## The packet
        handle*: ClientPacketHandle ## The client packet handle
    
    ClientPacketHandler* = object of FilterableEventHandler[ClientPacketEvent, Option[ClientPacketType]]
        ## A client packet event handler.
        ## Client packet handlers are filtered by a packet type enum, or none to handle all packet types.
    
    ClientDisconnectEvent* = object of CancelableEvent
        ## A client disconnection event.
        ## This event is soft-cancelable, meaning being marked as canceled may not cancel the event if the originator of the event chooses to override cancelations.
        
        client*: ref Client ## The client
        clientDisconnected*: bool ## Whether the client disconnected by itself, not by the server disconnecting it
        reason*: SDisconnectReason ## The reason why the client was disconnected
        message*: Option[string] ## The plaintext reason why the client was disconnected, if any
    
    ClientDisconnectHandler* = object of EventHandler[ClientDisconnectEvent]
        ## A client disconnection handler
    
    ClientBecomePipeEvent* = object of CancelableEvent
        ## A client become pipe event.
        ## This event is soft-cancelable, meaning being marked as canceled may not cancel the event if the originator of the event chooses to override cancelations.
        
        client*: ref Client ## The client
        isUploadPipe*: bool ## Whether the client is uploading to the server
        isDownloadPipe*: bool ## Whether the client is downloading from the server
    
    ClientBecomePipeHandler* = object of EventHandler[ClientBecomePipeEvent]
        ## A client become pipe handler

    Client* = object
        ## Client, either connected or not
        
        id*: ClientId ## The client ID
        host*: string ## The host
        port*: Port ## The port
        socket*: AsyncSocket ## The underlying socket
        connectedOn*: float ## The epoch time of when the client connected
        isConnected*: bool ## Whether the client currently connected
        isAuthorized*: bool ## Whether the client has been authorized
        isPipe*: bool ## Whether the client is currently function as a pipe (sending or receiving raw data)
        isStreaming*: bool ## Whether the client is streaming (which means the connection is dedicated)
        isViewingStream*: bool ## Whether the client is viewing a stream (which means the connection is dedicated)
        custodianStreams*: seq[StreamId] ## IDs of all streams the client is a custodian over
        protocolVersion*: uint16 ## The protocol version the client is using
        capabilities*: seq[string] ## The capabilities negociated with the server
        metadata*: Metadata ## The metadata attached to this specific client that was passed on authentication

        server*: ref Server ## The Server instance that the client belongs to
        account*: Account ## The client's username

        # Event handlers
        packetHandlers*: seq[ref ClientPacketHandler] ## Handlers that are used when the client sends a packet
        packetHandlersLock*: Lock ## The lock that governs the packetHandlers seq

        disconnectHandlers*: seq[ref ClientDisconnectHandler] ## Handlers that are used when the client disconnects
        disconnectHandlersLock*: Lock ## The lock that governs the disconnectHandlers seq

        becomePipeHandlers*: seq[ref ClientBecomePipeHandler] ## Handlers that are used when the client becomes a pipe
        becomePipeHandlersLock*: Lock ## The lock that governs the becomePipeHandlers seq

        # [X] TODO Add listener properties
        # [X Probably not necessary] There should be the main listener which is private,
        # [X Fulfilled with packetHandlers] and then private listener arrays that are either wildcard or match a specific packet type
        # through this, also create methods to await certain packets
        # [X] Listeners should have an ID, and be marked as either for one-time use (will be deleted after received), or always
        # Listeners can be removed via their ID
        # [X] There should also be a listener lock of course
        # IMPORTANT One-time handlers should have Futures associated with them
        # If the client is disconnected, fail all Futures for one-time handlers
        # Multiple one-time handlers should be able to be resolved for the same packet
        # IMPORTANT add onDisconnect handlers here too
        # IMPORTANT add onBecomePipe handlers here too
        # IMPORTANT add onLoopError handlers here too, to handle errors raised in main read loop
        # Fail all one-time handlers when client becomes a pipe

    Account* = object
        ## A user account
        
        id*: AccountId ## The account ID
        username*: string ## The username
        passwordHash*: string ## The account's password hash string
        isEphemeral*: bool ## Whether the account is ephemeral and should be deleted on startup/shutdown
        creationDate*: EpochSecond ## The epoch second when the account was created