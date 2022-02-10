import std/[tables]
import enums
import ".."/[utils, idgen]
import ".."/db/[objects]

## Server packets
type
    SSAccountInfo* = object
        ## Information about an account, not including sensitive data (not a full packet body)
        
        id*: AccountId ## The sequential account ID
        username*: string ## The account's username
        metadata*: Metadata ## The account's public metadata
        creationDate*: EpochSecond ## The epoch second of when the account was created

    SStreamInfo* = object
        ## Information about a stream, not including sensitive data (not a full packet body)
        
        id*: StreamId ## The sequential stream ID
        owner*: string ## The owner of the stream
        name*: string ## The stream name
        published*: bool ## Whether the stream is set to published
        key*: string ## The key requied to get further information about the stream, watch it, interact with it, etc
        metadata*: Table[string, string] ## The stream's public metadata (may be empty)
        creationDate*: EpochSecond ## The epoch second of when the stream was created

    SProtocolInfo* = object
        ## A SProtocolInfo packet should be the first type sent when a client connects, and is used to negociate which protocol version will be used for the rest of the connection.
        ## It defines which supported protocol version is the main version, and what other versions are supported.
        ## The client should reply with the protocol version it wants to use for the connected, and that should be what will be used.
        ## If the specified protocol version is not supported, the client's packet should be replied with a ServerDisconnect packet using the Unsupported reason.
        
        protocolVersion*: uint16 ## The main supported protocol version
        supportedProtocolVersions*: seq[uint16] ## All currently supported protocol versions
    
    SAcknowledged* = object
        ## Sent as a reply to a request or action to show it was received and handled.

    SDisconnect* = object
        ## An SDisconnect packet should be sent before a client is disconnected.
        ## It contains the reason why the disconnection occurred, and optionally a string message.
        
        reason*: SDisconnectReason ## The disconnection reason
        message*: string ## An optional plaintext message (empty if none provided)
    
    STooManyRequests* = object
        ## Sent as a reply to a request that cannot or will not be fulfilled because of the volume of requests sent by the client.
        
        resumeTime*: EpochSecond ## The epoch second when the client is allowed to resume sending requests (0 if none provided)

    SDenied* = object
        ## Sent as a reply to a request or action that was denied.
        
        reason*: SDeniedReason ## The denial reason
        message*: string ## An optional plaintext message (empty if none provided)
    
    SCapabilities* = object
        ## A ServerCapabilities packet should be sent after agreement on a protocol version, and is used to negociate supported client-server capabilities.
        ## It contains which capabilities are supported, including both negociable and behavior capabilities.
        ## Capabilities are defined using strings instead of enum values because they may represent protocol extensions which are not part of the original protocol.
        
        capabilities*: seq[string] ## General capabilities supported, which can be agreed upon by server and client
        serverCapabilities*: seq[string] ## Server-specific capabilities supported, does not directly affect communication between the client and server, but specifies certain behaviors the server may have
    
    SPlaintextMessage* = object
        ## Sends a plaintext message to a client.
        ## What is done with the message is entirely up to the client implementation.
        
        message*: string ## The plaintext message
    
    SStreamCreated* = object
        ## Sent as a reply to a create stream request when the stream was successfully created.
        
        info*: SStreamInfo ## The newly created stream's info
        custodialKey*: string ## The custodial key to manage the stream
    
    SPublishedStreams* = object
        ## Sent as a reply to a published streams request
        
        streams*: seq[SStreamInfo] ## The returned stream infos
