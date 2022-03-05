import std/[options, asyncnet, nativesockets, tables, json]

import idgen, utils, timer

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
    
    Server* = object
        ## Server state

        config*: Config ## The server config

        startedOn*: float ## When the server started
        acceptingConnections*: bool ## Whether the server is accepting new connections

        socket*: AsyncSocket ## The underlying server socket

        clients*: seq[ref Client] ## All connected clients
        authorizedClients*: seq[ref Client] ## All authorized clients
        streamingClients*: seq[ref Client] ## All currently streaming clients
        managerClients*: seq[ref Client] ## All clients which are server managers

        timer*: ref Timer ## The Timer instance used by the server

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
        capabilities*: seq[string] ## The capabilities negociated with the server

        server*: Server ## The Server instance that the client belongs to
        account*: Account ## The client's username

    Account* = object
        ## A user account
        
        id*: AccountId ## The account ID
        username*: string ## The username
        passwordHash*: string ## The account's password hash string
        isEphemeral*: bool ## Whether the account is ephemeral and should be deleted on startup/shutdown
        creationDate*: EpochSecond ## The epoch second when the account was created

    Metadata* = Table[string, string]
        ## Metadata stored in database and sent in packets (for accounts, streams, etc)