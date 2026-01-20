import Foundation

/// Data model for ICE server configuration
public struct ICEServer: Codable {
    public let urls: [String]
    public let username: String?
    public let credential: String?
    
    public init(urls: [String], username: String? = nil, credential: String? = nil) {
        self.urls = urls
        self.username = username
        self.credential = credential
    }
}

/// WebRTC configuration
public struct WebRTCConfig: Codable {
    public let iceServers: [ICEServer]
    
    public init(iceServers: [ICEServer] = [ICEServer(urls: ["stun:stun.l.google.com:19302"])]) {
        self.iceServers = iceServers
    }
}

/// Call information
public struct Call: Codable {
    public let callId: String
    public let callType: String
    public let isGroup: Bool
    public let maxParticipants: Int
    public let config: WebRTCConfig
    
    enum CodingKeys: String, CodingKey {
        case callId
        case callType
        case isGroup
        case maxParticipants
        case config
    }
    
    public init(
        callId: String,
        callType: String = "video",
        isGroup: Bool = false,
        maxParticipants: Int = 1000,
        config: WebRTCConfig = WebRTCConfig()
    ) {
        self.callId = callId
        self.callType = callType
        self.isGroup = isGroup
        self.maxParticipants = maxParticipants
        self.config = config
    }
}

/// Call join response
public struct JoinCallResponse: Codable {
    public let success: Bool
    public let callId: String
    public let participantId: String
    public let participants: [Participant]
    public let config: WebRTCConfig
    public let error: String?
    
    enum CodingKeys: String, CodingKey {
        case success
        case callId
        case participantId
        case participants
        case config
        case error
    }
}

/// Participant information
public struct Participant: Codable {
    public let id: String
    public let name: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case name = "userName"
    }
    
    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Online user information
public struct OnlineUser: Codable {
    public let userId: String
    public let userName: String
    
    enum CodingKeys: String, CodingKey {
        case userId
        case userName
    }
    
    public init(userId: String, userName: String) {
        self.userId = userId
        self.userName = userName
    }
}

/// Incoming call data
public struct IncomingCall: Codable {
    public let callId: String
    public let callerId: String
    public let callerName: String
    public let callType: String
    
    enum CodingKeys: String, CodingKey {
        case callId
        case callerId
        case callerName
        case callType
    }
}

/// Call accepted data
public struct CallAccepted: Codable {
    public let callId: String
    public let acceptedById: String
    public let acceptedByName: String
    
    enum CodingKeys: String, CodingKey {
        case callId
        case acceptedById
        case acceptedByName
    }
}

/// Call rejected data
public struct CallRejected: Codable {
    public let callId: String
    public let rejectedById: String
    public let rejectedByName: String
    
    enum CodingKeys: String, CodingKey {
        case callId
        case rejectedById
        case rejectedByName
    }
}

/// Participant joined data
public struct ParticipantJoined: Codable {
    public let callId: String
    public let participantId: String
    public let userName: String
    
    enum CodingKeys: String, CodingKey {
        case callId
        case participantId
        case userName
    }
}

/// Participant left data
public struct ParticipantLeft: Codable {
    public let callId: String
    public let participantId: String
    
    enum CodingKeys: String, CodingKey {
        case callId
        case participantId
    }
}

/// WebRTC signal data
public struct Signal: Codable {
    public let callId: String
    public let targetId: String?
    public let fromId: String?
    public let signal: SignalPayload
    public let type: String
    
    enum CodingKeys: String, CodingKey {
        case callId
        case targetId
        case fromId
        case signal
        case type
    }
}

/// Signal payload for SDP and ICE candidates
public struct SignalPayload: Codable {
    public let sdp: String?
    public let type: String?
    public let candidate: String?
    public let sdpMid: String?
    public let sdpMLineIndex: Int?
    
    enum CodingKeys: String, CodingKey {
        case sdp
        case type
        case candidate
        case sdpMid
        case sdpMLineIndex
    }
}

/// API Error response
public struct APIError: Codable {
    public let success: Bool
    public let error: String
}

/// Generic API response wrapper
public struct APIResponse<T: Codable>: Codable {
    public let success: Bool
    public let error: String?
    public let data: T?
}
