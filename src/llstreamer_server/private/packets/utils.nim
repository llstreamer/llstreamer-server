import std/strformat
import ".."/exceptions
import objects, enums

proc expectType*(pkt: ServerPacket, pktType: ServerPacketType, beforeRaise: proc() = proc() = discard) {.raises: [WrongServerPacketTypeError, ValueError].} =
    ## Raises WrongServerPacketTypeError if the provided server packet is not the correct type.
    ## Optionally runs a provided proc before raising the error.
    
    if pkt.kind != pktType:
        beforeRaise()
        raise newWrongServerPacketTypeError(fmt"Expected packet of type {pktType} but received {pkt.kind}", pktType, pkt.kind)

proc expectType*(pkt: ClientPacket, pktType: ClientPacketType, beforeRaise: proc() = proc() = discard) {.raises: [WrongClientPacketTypeError, ValueError].} =
    ## Raises WrongServerPacketTypeError if the provided server packet is not the correct type.
    ## Optionally runs a provided proc before raising the error.
    
    if pkt.kind != pktType:
        beforeRaise()
        raise newWrongClientPacketTypeError(fmt"Expected packet of type {pktType} but received {pkt.kind}", pktType, pkt.kind)