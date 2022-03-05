import ".."/[idgen]
import server, client, enums

type
    PacketHeader* = object
        ## A packet header
        
        typeByte*: uint8 ## The byte representing its type
        id*: PacketId ## The packet's unique ID
        reply*: PacketId ## The packet ID of the packet the packet is a reply to (or 0 if none)
        size*: uint16 ## The size of the packet body in bytes

    ServerPacket* = object of RootObj
        ## A server packet
        
        id*: PacketId ## The ID
        reply*: PacketId ## The ID of the packet this is a reply to

        case kind*: ServerPacketType
        of ServerPacketType.Upgrade:
            upgradeBody*: SUpgrade
        of ServerPacketType.ProtocolInfo:
            protocolInfoBody*: SProtocolInfo
        of ServerPacketType.CapabilitiesInfo:
            capabilitiesInfoBody*: SCapabilitiesInfo
        of ServerPacketType.Acknowledged:
            acknowledgedBody*: SAcknowledged
        of ServerPacketType.Disconnect:
            disconnectBody*: SDisconnect
        of ServerPacketType.TooManyRequests:
            tooManyRequestsBody*: STooManyRequests
        of ServerPacketType.Denied:
            deniedBody*: SDenied
        of ServerPacketType.PlaintextMessage:
            plaintextMessageBody*: SPlaintextMessage
        of ServerPacketType.SelfInfo:
            selfInfoBody*: SSelfInfo
        of ServerPacketType.StreamCreated:
            streamCreatedBody*: SStreamCreated
        of ServerPacketType.PublishedStreams:
            publishedStreamsBody*: SPublishedStreams

    ClientPacket* = object of RootObj
        ## A client packet
        
        id*: PacketId ## The ID
        reply*: PacketId ## The ID of the packet this is a reply to

        case kind*: ClientPacketType
        of ClientPacketType.Protocol:
            protocolBody*: CProtocol
        of ClientPacketType.Capabilities:
            capabilitiesBody*: CCapabilities
        of ClientPacketType.AuthRequest:
            authRequestBody*: CAuthRequest
        of ClientPacketType.SelfInfoRequest:
            selfInfoRequestBody*: CSelfInfoRequest
        of ClientPacketType.CreateStream:
            createStreamBody*: CCreateStream
        of ClientPacketType.ViewStreamRequest:
            viewStreamRequestBody*: CViewStreamRequest
        of ClientPacketType.PublishedStreamsRequest:
            publishedStreamsRequestBody*: CPublishedStreamsRequest
        of ClientPacketType.SendStreamData:
            sendStreamDataBody*: CSendStreamData