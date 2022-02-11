type
    PacketError* = object of CatchableError
        ## Raised if a packet-related error occurs

    UnknownPacketTypeError* = object of PacketError
        ## Raised if an unknown packet type is encountered
        
        packetType*: uint8 ## The packet type received

    MalformedPacketError* = object of PacketError
        ## Raised if a packet is malformed
    
    ShortPacketHeaderError* = object of PacketError
        ## Raised if a packet header is too short
        
        length*: int ## The size of the header received
    
    CannotSerializeError* = object of PacketError
        ## Raised if a packet or part of it cannot be serialized
    
    CryptoError* = object of CatchableError
        ## Raised if a crypto-related error occurs
    
    CannotParseHashError* = object of CryptoError
        ## Raised if a hash string cannot be parsed
    
    DatabaseError* = object of CatchableError
        ## Raised if a database-related error occurs
    
    DatabaseMigrationError* = object of DatabaseError
        ## Raised if a database migration-related error occurs

# Constructors

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

proc newShortPacketHeaderError*(msg: string, length: int): ref ShortPacketHeaderError =
    var e: ref ShortPacketHeaderError
    new(e)
    e.msg = msg
    e.length = length
    return e

proc newCannotSerializeError*(msg: string): ref CannotSerializeError =
    var e: ref CannotSerializeError
    new(e)
    e.msg = msg
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