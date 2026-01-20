import Foundation

// MARK: - Call Models
public struct CreateCallRequest: Codable {
    let callType: CallType
    let isGroup: Bool
    let maxParticipants: Int
    
    public init(callType: CallType, isGroup: Bool = false, maxParticipants: Int = 1000) {
        self.callType = callType
        self.isGroup = isGroup
        self.maxParticipants = maxParticipants
    }
}

public struct CreateCallResponse: Codable {
    public let success: Bool
    public let callId: String
    public let error: String?
    public let config: CallConfig
    
    public struct CallConfig: Codable {
        public let iceServers: [ICEServer]
    }
}

public struct JoinCallRequest: Codable {
    let userName: String
    let userId: String
    
    public init(userName: String, userId: String) {
        self.userName = userName
        self.userId = userId
    }
}

public struct JoinCallResponse: Codable {
    public let success: Bool
    public let callId: String
    public let participantId: String
    public let error: String?
    public let config: CallConfig
    
    public struct CallConfig: Codable {
        public let iceServers: [ICEServer]
    }
}

// MARK: - Participant Models
public struct Participant: Codable, Identifiable {
    public let id: String
    public let userName: String
    
    public init(id: String, userName: String) {
        self.id = id
        self.userName = userName
    }
}

public struct OnlineUser: Codable, Identifiable {
    public let id: String
    public let userName: String
    
    public init(id: String, userName: String) {
        self.id = id
        self.userName = userName
    }
}