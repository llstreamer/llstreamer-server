import std/[options, asyncnet, nativesockets]

import idgen, utils

## Objects

type
    Config* = ref object of RootObj
        ## Object representation of the server configuration
        
        host*: string ## The host to bind to
        port*: Port ## The port to bind to
        password*: Option[string] ## The password required to connect to the server, or none for an open server
        allowPublishStreams*: bool ## Whether clients are allowed to publish their streams
        authTimeoutSeconds*: uint16 ## The timeout in seconds before unauthorized clients will be disconnected
        maxClients*: uint32 ## The maximum amount of concurrent clients allowed, or 0 for unlimited
        maxStreams*: uint32 ## The maximum amount of concurrent streams allowed, or 0 for unlimited
        maxClientsPerHost*: uint32 ## The maximum amount of concurrent clients per IP address, or 0 for unlimited
        enableManagement*: bool ## Whether to enable server management
        streamKeepAliveSeconds*: uint16 ## How long to preserve a stream in seconds while there is no input before it is deleted
        managerPassword*: Option[string] ## The password required for clients to become managers, or none to not require one
        managerWhitelist*: Option[seq[string]] ## The list of IP addresses allowed to become managers, or none to not enable the whitelist

    Client* = object
        ## Client, either connected or not
        
        id*: ClientId ## The client ID
        host*: string ## The host
        port*: Port ## The port
        socket*: AsyncSocket ## The underlying socket
        connectedOn*: float ## The epoch time of when the client connected
        isConnected*: bool ## Whether the client currently connected
        isAuthorized*: bool ## Whether the client has been authorized
        isStreaming*: bool ## Whether the client is streaming (which means the connection is dedicated)
        isViewingStream*: bool ## Whether the client is viewing a stream (which means the connection is dedicated)
        custodianStreams*: seq[StreamId] ## IDs of all streams the client is a custodian over

        username*: string ## The client's username
        password*: string ## The client's password used to login (should be ephemeral since it will not be saved)

    Account* = object
        ## A user account
        
        id*: AccountId ## The account ID
        username*: string ## The username
        passwordHash*: string ## The account's password hash string
        ephemeral*: bool ## Whether the account is ephemeral and should be deleted on startup/shutdown
        creationDate*: EpochSecond ## The epoch second when the account was created
