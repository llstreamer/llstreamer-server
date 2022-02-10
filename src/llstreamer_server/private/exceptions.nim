type
    PacketError* = object of CatchableError
        ## Raised if a packet-related error occurs

    UnknownPacketTypeError* = object of PacketError
        ## Raised if an unknown packet type is encountered

    MalformedPacketError* = object of PacketError
        ## Raised if a packet is malformed
    
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