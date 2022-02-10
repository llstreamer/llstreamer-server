import std/[strformat, options]

type EpochSecond* = uint64 ## Reference to uint64, used for storing epoch seconds

proc flipInt*(integer: uint8): int8 {.inline.} =
    ## Flips an integer from signed to unsigned, or vise-versa
    return cast[int8](integer)
proc flipInt*(integer: uint16): int16 {.inline.} =
    ## Flips an integer from signed to unsigned, or vise-versa
    return cast[int16](integer)
proc flipInt*(integer: uint32): int32 {.inline.} =
    ## Flips an integer from signed to unsigned, or vise-versa
    return cast[int32](integer)
proc flipInt*(integer: uint64): int64 {.inline.} =
    ## Flips an integer from signed to unsigned, or vise-versa
    return cast[int64](integer)
proc flipInt*(integer: int8): uint8 {.inline.} =
    ## Flips an integer from signed to unsigned, or vise-versa
    return cast[uint8](integer)
proc flipInt*(integer: int16): uint16 {.inline.} =
    ## Flips an integer from signed to unsigned, or vise-versa
    return cast[uint16](integer)
proc flipInt*(integer: int32): uint32 {.inline.} =
    ## Flips an integer from signed to unsigned, or vise-versa
    return cast[uint32](integer)
proc flipInt*(integer: int64): uint64 {.inline.} =
    ## Flips an integer from signed to unsigned, or vise-versa
    return cast[uint64](integer)

proc toUnsigned*(integer: uint8): uint8 {.inline.} =
    ## Flips an integer from signed to unsigned
    return integer
proc toUnsigned*(integer: uint16): uint16 {.inline.} =
    ## Flips an integer from signed to unsigned
    return integer
proc toUnsigned*(integer: uint32): uint32 {.inline.} =
    ## Flips an integer from signed to unsigned
    return integer
proc toUnsigned*(integer: uint64): uint64 {.inline.} =
    ## Flips an integer from signed to unsigned
    return integer
proc toUnsigned*(integer: int8): uint8 {.inline.} =
    ## Flips an integer from signed to unsigned
    return cast[uint8](integer)
proc toUnsigned*(integer: int16): uint16 {.inline.} =
    ## Flips an integer from signed to unsigned
    return cast[uint16](integer)
proc toUnsigned*(integer: int32): uint32 {.inline.} =
    ## Flips an integer from signed to unsigned
    return cast[uint32](integer)
proc toUnsigned*(integer: int64): uint64 {.inline.} =
    ## Flips an integer from signed to unsigned
    return cast[uint64](integer)

proc bytesToInt*[T: SomeInteger](bytes: openArray[uint8]): T =
    ## Converts the provided bytes into an integer

    var num: T = low(T)

    for i in 0..<sizeof(T):
        num = num shl 8 + bytes[i].toUnsigned
    
    return num

proc intToBytes*[T: SomeInteger](integer: T): array[sizeof(T), uint8] =
    ## Converts the provided integer into bytes

    var arr: array[sizeof(T), uint8]
    for i in 0..<sizeof(T):
        arr[i] = (uint8) (integer shr (i*8))

    return arr

proc intToBytesSeq*[T: SomeInteger](integer: T): seq[uint8] =
    ## Converts the provided integer into bytes stored in a sequence

    var res = newSeq[uint8](sizeof(T))
    for i in 0..<sizeof(T):
        res[i] = (uint8) (integer shr (i*8))

    return res

proc slice*[T](s: openArray[T], startIndex: int, endIndex: int): seq[T] =
    ## Takes a slice out of a sequence. Works the same way as JavaScript's array slice menthod

    let realEnd = if endIndex < 0:
        s.len-1+endIndex
    else:
        endIndex
    
    let len = realEnd-startIndex+1
    if len < 0:
        raise newException(IndexDefect, fmt"The size between indexes {startIndex} and {realEnd} is less than 0")

    var res = newSeq[T](len)

    for i in startIndex..realEnd:
        res[i-startIndex] = s[i]

    return res

proc slice*[T](s: openArray[T], startIndex: int): seq[T] =
    ## Takes a slice out of a sequence. Works the same way as JavaScript's array slice menthod
    
    return s.slice(startIndex, s.len-1)

proc writeAtOffset*[T](s: openArray[T], data: openArray[T], offset: int) =
    ## Writes the provided data onto the specified array at an offset.
    ## It does not insert like the proc from sequtils, it directly writes into the array and can overwrite elements.
    ## Make sure your data length + offset does not exceed the source array length.

    for i in 0..<data.len:
        s[i+offset] = data[i]

proc asBytes*(str: string): seq[uint8] {.inline.} =
    ## Converts a string to a byte array

    return cast[seq[uint8]](str)

proc asStr*(bytes: openArray[uint8]): string {.inline.} =
    ## Converts a byte array to a string
    
    return cast[string](bytes)

proc orEmpty*(str: Option[string]): string =
    ## Returns the value of the optional string, or empty if none

    if str.isSome:
        return str.get
    else:
        return ""