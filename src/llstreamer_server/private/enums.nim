type
    PacketTypeNum = uint8

type
    DisconnectReason* {.pure.} = enum
        ## The reason a client was disconnected
        
        Unspecified = (uint8) 0 ## No reason specified
        TooManyClients = (uint8) 1 ## There are too many clients connected, either from the same host or as a whole
        Unauthorized = (uint8) 2 ## The client is not authorized to connect
        Kicked = (uint8) 3 ## The client was kicked
        ServerShutdown = (uint8) 4 ## The server is being shutdown
    
    AuthRejectReason* {.pure.} = enum
        ## The reason an auth request was rejected
        
        Unauthorized = (uint8) 0 ## The client is not authorized to connect
        TooManyClients = (uint8) 1 ## Too many clients are currently connected
        InvalidCredentials = (uint8) 2 ## The requested username is already taken by another client, or the provided password is incorrect
        UnsupportedMetadata = (uint8) 3 ## All or part of the client's provided metadata is unsupported
    
    CreateStreamRejectReason* {.pure.} = enum
        ## The reason a create stream request was rejected
        
        Unauthorized = (uint8) 0 ## The client is not authorized to create streams
        InvalidOptions = (uint8) 1 ## The provided stream options were invalid or not allowed

    ViewStreamRejectReason* {.pure.} = enum
        ## The reason a view stream request was rejected
        
        InvalidKey = (uint8) 0 ## The stream key was invalid
        CustodianRejected = (uint8) 1 ## A stream custodian rejected the request
    
    SubscribeChatRejectReason* {.pure.} = enum
        ## The reason a subscribe chat request was rejected
        
        InvalidKey = (uint8) 0 ## The stream key was invalid
        CustodianRejected = (uint8) 1 ## A stream custodian rejected the request

    ChatMessageRejectReason* {.pure.} = enum
        ## The reason a chat message was rejected
        
        InvalidKey = (uint8) 0 ## The stream key was invalid
        CustodianRejected = (uint8) 1 ## A stream custodian rejected the request
    
    SerializableKind* {.pure.} = enum
        ## Kinds of SerializableKind.serializable data

        Int8 = (uint8) 0
        Uint8 = (uint8) 1
        Int16 = (uint8) 2
        Uint16 = (uint8) 3
        Int32 = (uint8) 4
        Uint32 = (uint8) 5
        Int64 = (uint8) 6
        Uint64 = (uint8) 7
        String = (uint8) 8
        Table = (uint8) 9
        SeqInt8 = (uint8) 10
        SeqUint8 = (uint8) 11
        SeqInt16 = (uint8) 12
        SeqUint16 = (uint8) 13
        SeqInt32 = (uint8) 14
        SeqUint32 = (uint8) 15
        SeqInt64 = (uint8) 16
        SeqUint64 = (uint8) 17
        SeqString = (uint8) 18
        SeqTable = (uint8) 19