import std/tables
import ".."/[idgen, simpletypes]

## Client packets
type
    CProtocol* = object
        ## A CProtocol packet should be sent in reply to an SProtocolInfo packet and chooses which protocol to use for the rest of the connection.
        
        protocolVersion*: uint16 ## The chosen protocol version
    
    CCapabilities* = object
        ## A CCapabilities packet should be sent in reply to an SCapabilitiesInfo packet and confirms which capabilities should be supported.
        ## Capabilities in this packet should not include anything that wasn't listed in the SCapabilitiesInfo packet this is in reply to.
        
        capabilities*: seq[string] ## The capabilities supported by the server
    
    CAuthRequest* = object
        ## An authentication request, required to be sent before sending other requests or actions.
        ## Username and password either need to be unique, or match existing username and password combination.
        ## Additionally, authentication may be handled by a different system entirely, or registration may be disabled.
        
        serverPass*: string ## THe password to use for connecting to the server
        username*: string ## The username to use
        password*: string ## The password to use
        ephemeral*: bool ## Whether this account should be marked as ephemeral (will fail if this value does not match an existing account's ephemeral value)
        queryInfoRequiresCommonStream*: bool ## Whether users must be watching or subscribed to the chat of a common stream to query the client's info
        privMsgRequiresCommonStream*: bool ## Whether users must be watching or subscribed to the chat of a common stream to send a private message to the client
        metadata*: Metadata ## Private metadata to pass to the server for this connection only (not the same as account metadata)
    
    CSelfInfoRequest* = object
        ## A request for information about the current connection and the account associated with it.
    
    CUpdateAccount* = object
        ## Updates information about the account associated with the current connection.
        ## "currentPassword" must not be blank if "password" is also not blank. If "password" is not blank but "currentPassword" is, the packet will be denied using the Unauthorized reason.
        
        password*: string ## The account's new password (can be blank to leave unchanged)
        metadata*: Metadata ## The account's new public metadata
        ephemeral*: bool ## Whether the account will now be ephemeral
        currentPassword*: string ## The account's current password (must not be blamk if "password" is specified)
    
    CCreateStream* = object
        ## A stream create request.
        ## Should include whether to publish, whether chat is enabled, whether to require custodial permission to watch, whether to require custodial permission to subscribe chat, whether to require custodial permission to send chat.
        
        name*: string ## The name of the stream (may be changed later)
        publish*: bool ## Whether the stream will be published publicly on the server (may be changed later)
        chatEnabled*: bool ## Whether the stream has chat enabled
        watchRequireCustodialPerm*: bool ## Whether watch requests must be approved by a stream custodian
        chatSubRequireCustodialPerm*: bool ## Whether requests to subscribe to stream chat messages must be approved by a stream custodian
        chatRequireCustodialPerm*: bool ## Whether each stream chat message needs to be approved by a stream custodian
        viewersCountAvailable*: bool ## Whether to make viewers count visible (will always show 0 if false)
        viewersListAvailable*: bool ## Whether to make a list of all viewers visible to other stream viewers
        publicMetadata*: Table[string, string] ## Public metadata available to other clients
        privateMetadata*: Table[string, string] ## Private metadata only available to the server
    
    CViewStreamRequest* = object
        ## A stream view request.
        ## If replied to with SAcknowledged, then the connection will thereafter be a video data pipe, and will be closed when the stream video data ends.
        
        key*: string ## The key of the stream to watch
    
    CPublishedStreamsRequest* = object
        ## A request to get a list of currently published streams.
        ## Pagination is achieved by specifying a "before" OR "after" cursor (both of which are a stream ID), and a "limit" specifying the amount of results to return.
        ## The server may return less results than requested by "limit", but it should never return more.
        ## "before" and "after" may both be 0 (blank) to start at the beginning.
        ## If both are provided, "before" is used, and "after" is discarded.
        
        before*: StreamId ## Return results before this stream (0 to start at the beginning)
        after*: StreamId ## Return results after this stream (0 to start at the beginning)
        limit*: uint8 ## The max amount of results to return
    
    CSendStreamData* = object
        ## Sent to convert the connection into a stream data input pipe.
        
        streamId*: StreamId ## The stream to send data to