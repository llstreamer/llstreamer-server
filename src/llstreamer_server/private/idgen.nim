import std/[locks]

type
    PacketId* = uint32 ## A packet ID
    ClientId* = uint32 ## A client ID
    StreamId* = uint32 ## A stream ID
    AccountId* = uint32 ## An account ID
    HandlerId* = uint32 ## A handler ID

    BlankPacketId* = range[((PacketId) 0)..(PacketId) 0] ## A blank packet ID
    BlankClientId* = range[((ClientId) 0)..(ClientId) 0] ## A blank client ID
    BlankStreamId* = range[((StreamId) 0)..(StreamId) 0] ## A blank stream ID
    BlankAccountId* = range[((AccountId) 0)..(AccountId) 0] ## A blank account ID
    BlankHandlerId* = range[((HandlerId) 0)..(HandlerId) 0] ## A blank handler ID

    NonBlankPacketId* = range[((PacketId) 1)..high(PacketId)] ## A non-blank packet ID
    NonBlankClientId* = range[((ClientId) 1)..high(ClientId)] ## A non-blank client ID
    NonBlankStreamId* = range[((StreamId) 1)..high(StreamId)] ## A non-blank stream ID
    NonBlankAccountId* = range[((AccountId) 1)..high(AccountId)] ## A non-blank account ID
    NonBlankHandlerId* = range[((HandlerId) 1)..high(HandlerId)] ## A non-blank handler ID

const blankPacketId*: PacketId = 0
const blankClientId*: ClientId = 0
const blankStreamId*: StreamId = 0
const blankAccountId*: AccountId = 0
const blankHandlerId*: HandlerId = 0

var serverPacketId: PacketId = 0
var clientPacketId: PacketId = 0
var clientId: ClientId = 0
var streamId: StreamId = 0
var accountId: AccountId = 0
var handlerId: HandlerId = 0

var serverPacketIdLock: Lock
var clientPacketIdLock: Lock
var clientIdLock: Lock
var streamIdLock: Lock
var accountIdLock: Lock
var handlerIdLock: Lock

proc genServerPacketId*(): PacketId =
    ## Generates and returns a new server packet ID

    withLock serverPacketIdLock:
        if serverPacketId == high(PacketId):
            serverPacketId += 2
        else:
            serverPacketId += 1

        return serverPacketId

proc genClientPacketId*(): PacketId =
    ## Generates and returns a new client packet ID

    withLock clientPacketIdLock:
        if clientPacketId == high(PacketId):
            clientPacketId += 2
        else:
            clientPacketId += 1
        
        return clientPacketId

proc genClientId*(): ClientId =
    ## Generates and returns a new client ID

    withLock clientIdLock:
        if clientId == high(ClientId):
            clientId += 2
        else:
            clientId += 1
        
        return clientId

proc genStreamId*(): StreamId =
    ## Generates and returns a new stream ID
    
    withLock streamIdLock:
        if streamId == high(StreamId):
            streamId += 2
        else:
            streamId += 1
        
        return streamId

proc genAccountId*(): AccountId =
    ## Generates and returns a new account ID
    
    withLock accountIdLock:
        if accountId == high(AccountId):
            accountId += 2
        else:
            accountId += 1
        
        return accountId

proc genHandlerId*(): HandlerId =
    ## Generates and returns a new handler ID
    
    withLock handlerIdLock:
        if handlerId == high(HandlerId):
            handlerId += 2
        else:
            handlerId += 1
        
        return handlerId