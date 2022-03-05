const SERVER_VER* = "1.0.0"
const SERVER_VER_INT*: uint16 = 0
const PROTOCOL_VER*: uint16 = 0

const UINT8_SIZE* = sizeof(uint8)
const UINT16_SIZE* = sizeof(uint16)
const UINT32_SIZE* = sizeof(uint32)

const CLIENT_PROTO_TIMEOUT_MS* = 10_000
const CLIENT_CAPS_TIMEOUT_MS* = 10_000
const CLIENT_AUTH_TIMEOUT_MS* = 10_000
const DISCONNECT_MSG_TIMEOUT_MS* = 3_000

const SERVER_CAPABILITIES* = newSeq[string]() ## Nothing for now