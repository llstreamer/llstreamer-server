import std/[tables, strformat]
import exceptions, utils, objects, enums

proc asSerializable*(val: int8): Serializable =
    ## Converts a value to a Serializable object
    return Serializable(kind: SerializableKind.Int8, int8Val: val)
proc asSerializable*(val: uint8): Serializable =
    ## Converts a value to a Serializable object
    return Serializable(kind: SerializableKind.Uint8, uint8Val: val)
proc asSerializable*(val: int16): Serializable =
    ## Converts a value to a Serializable object
    return Serializable(kind: SerializableKind.Int16, int16Val: val)
proc asSerializable*(val: uint16): Serializable =
    ## Converts a value to a Serializable object
    return Serializable(kind: SerializableKind.Uint16, uint16Val: val)
proc asSerializable*(val: int32): Serializable =
    ## Converts a value to a Serializable object
    return Serializable(kind: SerializableKind.Int32, int32Val: val)
proc asSerializable*(val: uint32): Serializable =
    ## Converts a value to a Serializable object
    return Serializable(kind: SerializableKind.Uint32, uint32Val: val)
proc asSerializable*(val: int64): Serializable =
    ## Converts a value to a Serializable object
    return Serializable(kind: SerializableKind.Int64, int64Val: val)
proc asSerializable*(val: uint64): Serializable =
    ## Converts a value to a Serializable object
    return Serializable(kind: SerializableKind.Uint64, uint64Val: val)
proc asSerializable*(val: string): Serializable =
    ## Converts a value to a Serializable object
    return Serializable(kind: SerializableKind.String, stringVal: val)
proc asSerializable*(val: Table[string, Serializable]): Serializable =
    ## Converts a value to a Serializable object
    return Serializable(kind: SerializableKind.Table, tableVal: val)
proc asSerializable*(val: seq[int8]): Serializable =
    ## Converts a value to a Serializable object
    return Serializable(kind: SerializableKind.SeqInt8, seqInt8Val: val)
proc asSerializable*(val: seq[uint8]): Serializable =
    ## Converts a value to a Serializable object
    return Serializable(kind: SerializableKind.SeqUint8, seqUint8Val: val)
proc asSerializable*(val: seq[int16]): Serializable =
    ## Converts a value to a Serializable object
    return Serializable(kind: SerializableKind.SeqInt16, seqInt16Val: val)
proc asSerializable*(val: seq[uint16]): Serializable =
    ## Converts a value to a Serializable object
    return Serializable(kind: SerializableKind.SeqUint16, seqUint16Val: val)
proc asSerializable*(val: seq[int32]): Serializable =
    ## Converts a value to a Serializable object
    return Serializable(kind: SerializableKind.SeqInt32, seqInt32Val: val)
proc asSerializable*(val: seq[uint32]): Serializable =
    ## Converts a value to a Serializable object
    return Serializable(kind: SerializableKind.SeqUint32, seqUint32Val: val)
proc asSerializable*(val: seq[int64]): Serializable =
    ## Converts a value to a Serializable object
    return Serializable(kind: SerializableKind.SeqInt64, seqInt64Val: val)
proc asSerializable*(val: seq[uint64]): Serializable =
    ## Converts a value to a Serializable object
    return Serializable(kind: SerializableKind.SeqUint64, seqUint64Val: val)
proc asSerializable*(val: seq[string]): Serializable =
    ## Converts a value to a Serializable object
    return Serializable(kind: SerializableKind.SeqString, seqStringVal: val)
proc asSerializable*(val: seq[Table[string, Serializable]]): Serializable =
    ## Converts a value to a Serializable object
    return Serializable(kind: SerializableKind.SeqTable, seqTableVal: val)

proc serialize*[
    StrMeasure: SomeUnsignedInt,
    SeqMeasure: SomeUnsignedInt,
    TableMeasure: SomeUnsignedInt,
    SeqStrMeasure: SomeUnsignedInt,
    SeqTableMeasure: SomeUnsignedInt
](data: Serializable, withTypeId: bool): seq[uint8] =
    ## Serializes a serializable datatype
    ## The proc's generics define what type of unsigned int to use for measuring various values
    ## The int types chosen will limit the length of these items
    
    proc mkBuf(size: uint8): seq[uint8] =
        if withTypeId:
            var buf = newSeqOfCap[uint8](1+size)
            buf.add((uint8) data.kind)
            return buf
        else:
            var buf = newSeqOfCap[uint8](size)
            return buf
    
    proc serializeInt(data: Serializable): seq[uint8] =
        case data.kind:
        of SerializableKind.Int8:
            var buf = mkBuf(1)
            buf.add(data.int8Val.toUnsigned)
            return buf
        of SerializableKind.Uint8:
            var buf = mkBuf(1)
            buf.add(data.uint8Val)
            return buf
        of SerializableKind.Int16:
            var buf = mkBuf(2)
            buf.add(data.int16Val.intToBytes)
            return buf
        of SerializableKind.Uint16:
            var buf = mkBuf(2)
            buf.add(data.uint16Val.intToBytes)
            return buf
        of SerializableKind.Int32:
            var buf = mkBuf(4)
            buf.add(data.int32Val.intToBytes)
            return buf
        of SerializableKind.Uint32:
            var buf = mkBuf(4)
            buf.add(data.uint32Val.intToBytes)
            return buf
        of SerializableKind.Int64:
            var buf = mkBuf(8)
            buf.add(data.int64Val.intToBytes)
            return buf
        of SerializableKind.Uint64:
            var buf = mkBuf(8)
            buf.add(data.uint64Val.intToBytes)
            return buf

    case data.kind:
    of SerializableKind.Int8:
        var buf = mkBuf(1)
        buf.add(data.int8Val.toUnsigned)
        return buf
    of SerializableKind.Uint8:
        var buf = mkBuf(1)
        buf.add(data.uint8Val)
        return buf
    of SerializableKind.Int16:
        var buf = mkBuf(2)
        buf.add(data.int16Val.intToBytes)
        return buf
    of SerializableKind.Uint16:
        var buf = mkBuf(2)
        buf.add(data.uint16Val.intToBytes)
        return buf
    of SerializableKind.Int32:
        var buf = mkBuf(4)
        buf.add(data.int32Val.intToBytes)
        return buf
    of SerializableKind.Uint32:
        var buf = mkBuf(4)
        buf.add(data.uint32Val.intToBytes)
        return buf
    of SerializableKind.Int64:
        var buf = mkBuf(8)
        buf.add(data.int64Val.intToBytes)
        return buf
    of SerializableKind.Uint64:
        var buf = mkBuf(8)
        buf.add(data.uint64Val.intToBytes)
        return buf
    of SerializableKind.String:
        let str = data.stringVal
        let strLen = str.len
        let maxLen = (int) StrMeasure.high

        if strLen > maxLen:
            raise newException(CannotSerializeError, fmt"Cannot serialize {StrMeasure}-measured string value with length higher than {maxLen}")

        var buf = mkBuf(sizeof(StrMeasure)+strLen)
        buf.add(strLen.intToBytes[StrMeasure]())
        buf.add(str.strToBytes())

        return buf
    of SerializableKind.Table:
        let tbl = data.tableVal
        let tblLen = tbl.len
        let maxLen = (int) TableMeasure.high

        if tblLen > maxLen:
            raise newException(CannotSerializeError, fmt"Cannot serialize {TableMeasure}-measured table value with more fields than {maxLen}")

        # Serialize field names and contents
        var bufs = newSeqOfCap[seq[uint8]](tblLen)
        var bufLen = sizeof(TableMeasure)
        for (key, val) in tbl:
            let keyBuf = key.asSerializable.serialize[StrMeasure: uint8](false)
            let valBuf = val.asSerializable.serialize[StrMeasure, SeqMeasure, TableMeasure, SeqStrMeasure, SeqTableMeasure](true)
            var final = newSeqOfCap[uint8](keyBuf.len+valBuf.len)
            final.add(keyBuf)
            final.add(valBuf)
            bufs.add(final)
        
        # Allocate buffer
        var buf = mkBuf(bufLen)

        # Write header and fields
        buf.add(intToBytes[TableMeasure](tblLen))
        for part in bufs:
            buf.add(part)
        
        return buf
    of SerializableKind.SeqInt8 or SerializableKind.SeqUint8 or SerializableKind.SeqInt16 or SerializableKind.SeqUint16 or SerializableKind.SeqInt32 or SerializableKind.SeqUint32 or SerializableKind.SeqInt64 or SerializableKind.SeqUint64:
        let seqVal = data.seqInt8Val
        let seqLen = seqVal.len
        let maxLen = (int) SeqMeasure.high

        if seqLen > maxLen:
            raise newException(CannotSerializeError, fmt"Cannot serialize {SeqMeasure}-measured sequence value with length higher than {maxLen}")

        # Serialize contents
        var contents = newSeqOfCap[seq[uint8]](seqLen)
        var bufLen = sizeof(SeqMeasure)
        for elem in seqVal:
            let buf = elem.asSerializable.serialize[StrMeasure, SeqMeasure, TableMeasure, SeqStrMeasure, SeqTableMeasure](false)
            bufLen += buf.len
            contents.add(buf)
        
        # Allocate buffer
        var buf = mkBuf(bufLen)

        # Write header and fields
        buf.add(intToBytes[SeqMeasure](seqLen))
        for content in contents:
            buf.add(content)
    # TODO seq types