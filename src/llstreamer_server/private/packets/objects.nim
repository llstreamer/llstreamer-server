import ".."/[idgen]
import server, client, enums

type
    ServerPacket* = object of RootObj
        ## A server packet
        
        id*: PacketId ## The ID
        reply*: PacketId ## The ID of the packet this is a reply to

        case kind*: ServerPacketType
        of ServerPacketType.ProtocolInfo:
            protocolInfoBody*: SProtocolInfo
        of ServerPacketType.Acknowledged:
            acknowledgedBody*: SAcknowledged
        of ServerPacketType.Disconnect:
            disconnectBody*: SDisconnect
        of ServerPacketType.TooManyRequests:
            tooManyRequestsBody*: STooManyRequests
        of ServerPacketType.Denied:
            deniedBody*: SDenied
        of ServerPacketType.Capabilities:
            capabilitiesBody*: SCapabilities
        of ServerPacketType.PlaintextMessage:
            plaintextMessageBody*: SPlaintextMessage
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
        of ClientPacketType.AuthRequest:
            authRequestBody*: CAuthRequest
        of ClientPacketType.CreateStream:
            createStreamBody*: CCreateStream
        of ClientPacketType.ViewStreamRequest:
            viewStreamRequestBody*: CViewStreamRequest
        of ClientPacketType.PublishedStreamsRequest:
            publishedStreamsRequestBody*: CPublishedStreamsRequest
        of ClientPacketType.SendStreamData:
            sendStreamDataBody*: CSendStreamData