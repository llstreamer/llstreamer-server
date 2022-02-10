type
    ServerClientCapabilities* {.pure.} = enum
        ## Types of capabilities a server can have
        PublishStream = "PUBLISH_STREAM" ## Streams can be published
        StreamChat = "STREAM_CHAT" ## Stream chat
        StreamCustodian = "STREAM_CUSTODIAN" ## Custodial codes for managing streams

    ServerPacketType* {.pure.} = enum
        ## Types of packets the server can send
        
        ProtocolInfo = (uint8) 0 ## Protocol info, such as protocol version and supported protocol versions
        Acknowledged = (uint8) 1 ## The client's packet was acknowledged
        Disconnect = (uint8) 2 ## Client was disconnected for some reason
        TooManyRequests = (uint8) 3 ## Returned when a client is sending too many requests
        Denied = (uint8) 4 ## Sent as a reply to a request or action that was denied
        Capabilities = (uint8) 5 ## Server capabilities, such as whether clients can broadcast streams
        PlaintextMessage = (uint8) 6 ## Plaintext message
        StreamCreated = (uint8) 9 ## Sent as a reply to a create stream request when the stream was successfully created
        PublishedStreams = (uint8) 11 ## Sent as a reply to a fetch published streams request
        # TODO: SubscribeChatAccepted - A chat subscription request was accepted
        # TODO: SubscribeChatRejected - A chat subscription request was rejected
        # TODO: ChatMessageAccepted - A chat message request was accepted
        # TODO: ChatMessageRejected - A chat message request was rejected
        # TODO: ChatMessage - A chat message was sent in a subscribed channel (don't send self messages)
        # TODO: UnsubscribeChat - Notifies a client that it was unsubscribed from a chat
        # TODO: SubscribePublishAccepted - A stream publish subscription request was accepted
        # TODO: SubscribePublishRejected - A stream publish subscription request was rejected

    ClientPacketType* {.pure.} = enum
        ## Type of packets clients can send

        Protocol = (uint8) 0 ## Selects which protocol version to use for a connection
        AuthRequest = (uint8) 1 # Should include username and optionally password (server password), along with public and private metadata
        CreateStream = (uint8) 2 # Should include whether to publish, whether chat is enabled, whether to require custodial permission to watch, whether to require custodial permission to subscribe chat, whether to require custodial permission to send chat
        SendStreamData = (uint8) 3 ## Dedicates the connection as a video data upload pipe
        ViewStreamRequest = (uint8) 4 ## Requests to view a stream by piping its video data to the connection
        PublishedStreamsRequest = (uint8) 5 ## Requests a list of published streams

    SDeniedReason* {.pure.} = enum
        Unspecified ## No reason specified
        Unauthorized ## The client is not authorized to perform the request or action
        Unsupported ## The server does not support the request or action
        NotEnabled ## The feature the client is trying to interact with is not enabled
        InvalidParameters ## Parameters provided were invalid
        InvalidCredentials ## The credentials provided were invalid
        InvalidStreamKey ## The provided stream key was invalid
        CustodianRejected ## The request or action required authorization from a stream custodian and it was denied
        LimitReached ## A limit has been reached the request or action cannot be completed
    SDisconnectReason* {.pure.} = enum
        Unspecified ## No reason specified
        Unsupported ## An action or choice by the client is not supported
        TooManyClients ## There are too many clients connected, either from the same host or as a whole
        Unauthorized ## The client is not authorized to connect
        Kicked ## The client was kicked
        ServerShutdown ## The server is being shutdown