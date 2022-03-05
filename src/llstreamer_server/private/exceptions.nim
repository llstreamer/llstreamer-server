import packets/enums

type
    ConfigError* = object of CatchableError
        ## Raised if a configuration-related error occurs

    PacketError* = object of CatchableError
        ## Raised if a packet-related error occurs

    UnknownPacketTypeError* = object of PacketError
        ## Raised if an unknown packet type is encountered
        
        packetType*: uint8 ## The packet type received

    MalformedPacketError* = object of PacketError
        ## Raised if a packet is malformed

    ShortPacketHeaderError* = object of PacketError
        ## Raised if a packet header is too short
        
        length*: uint8 ## The size of the header received
    
    ShortPacketBodyError* = object of PacketError
        ## Raised if a packet body is too short
        
        length*: uint16 ## The size of the body received
    
    PacketTimeoutError* = object of PacketError
        ## Raised if a packet timeout was reached before receiving a reply or successfully sending
        
        timeoutMs*: int ## The timeout duration in milliseconds
    
    WrongClientPacketTypeError* = object of PacketError
        ## Raised if the client was expecting a certain type of client packet but got another
        
        expected*: ClientPacketType ## The expected packet type
        received*: ClientPacketType ## The received packet type
    
    WrongServerPacketTypeError* = object of PacketError
        ## Raised if the client was expecting a certain type of server packet but got another
        
        expected*: ServerPacketType ## The expected packet type
        received*: ServerPacketType ## The received packet type
    
    CryptoError* = object of CatchableError
        ## Raised if a crypto-related error occurs
    
    CannotParseHashError* = object of CryptoError
        ## Raised if a hash string cannot be parsed
    
    DatabaseError* = object of CatchableError
        ## Raised if a database-related error occurs
    
    DatabaseMigrationError* = object of DatabaseError
        ## Raised if a database migration-related error occurs

# Constructors

proc newConfigError*(msg: string): ref ConfigError =
    var e: ref ConfigError
    new(e)
    e.msg = msg
    return e

proc newPacketError*(msg: string): ref PacketError =
    var e: ref PacketError
    new(e)
    e.msg = msg
    return e

proc newUnknownPacketTypeError*(msg: string, packetType: uint8): ref UnknownPacketTypeError =
    var e: ref UnknownPacketTypeError
    new(e)
    e.msg = msg
    e.packetType = packetType
    return e

proc newMalformedPacketError*(msg: string): ref MalformedPacketError =
    var e: ref MalformedPacketError
    new(e)
    e.msg = msg
    return e

proc newShortPacketHeaderError*(msg: string, length: uint8): ref ShortPacketHeaderError =
    var e: ref ShortPacketHeaderError
    new(e)
    e.msg = msg
    e.length = length
    return e

proc newShortPacketBodyError*(msg: string, length: uint16): ref ShortPacketBodyError =
    var e: ref ShortPacketBodyError
    new(e)
    e.msg = msg
    e.length = length
    return e

proc newPacketTimeoutError*(msg: string, timeoutMs: int): ref PacketTimeoutError =
    var e: ref PacketTimeoutError
    new(e)
    e.msg = msg
    e.timeoutMs = timeoutMs
    return e

proc newWrongClientPacketTypeError*(msg: string, expected: ClientPacketType, received: ClientPacketType): ref WrongClientPacketTypeError =
    var e: ref WrongClientPacketTypeError
    new(e)
    e.msg = msg
    e.expected = expected
    e.received = received
    return e

proc newWrongServerPacketTypeError*(msg: string, expected: ServerPacketType, received: ServerPacketType): ref WrongServerPacketTypeError =
    var e: ref WrongServerPacketTypeError
    new(e)
    e.msg = msg
    e.expected = expected
    e.received = received
    return e

proc newCryptoError*(msg: string): ref CryptoError =
    var e: ref CryptoError
    new(e)
    e.msg = msg
    return e

proc newCannotParseHashError*(msg: string): ref CannotParseHashError =
    var e: ref CannotParseHashError
    new(e)
    e.msg = msg
    return e

proc newDatabaseError*(msg: string): ref DatabaseError =
    var e: ref DatabaseError
    new(e)
    e.msg = msg
    return e

proc newDatabaseMigrationError*(msg: string): ref DatabaseMigrationError =
    var e: ref DatabaseMigrationError
    new(e)
    e.msg = msg
    return e