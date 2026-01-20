import Foundation

// MARK: - Signaling Models
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

public struct CallJoinedData: Codable {
    public let callId: String
    public let participants: [Participant]
    public let iceServers: [ICEServer]
}

public struct ParticipantData: Codable {
    public let participantId: String
    public let userName: String
    
    public init(participantId: String, userName: String) {
        self.participantId = participantId
        self.userName = userName
    }
}

public struct ParticipantLeftData: Codable {
    public let participantId: String
    public let reason: String?
    
    public init(participantId: String, reason: String? = nil) {
        self.participantId = participantId
        self.reason = reason
    }
}

public struct IncomingCallData: Codable {
    public let callId: String
    public let callerId: String
    public let callerName: String
    public let callType: CallType
    
    public init(callId: String, callerId: String, callerName: String, callType: CallType) {
        self.callId = callId
        self.callerId = callerId
        self.callerName = callerName
        self.callType = callType
    }
}

public struct CallAcceptedData: Codable {
    public let callId: String
    public let acceptedById: String
    public let acceptedByName: String
    
    public init(callId: String, acceptedById: String, acceptedByName: String) {
        self.callId = callId
        self.acceptedById = acceptedById
        self.acceptedByName = acceptedByName
    }
}

public struct CallRejectedData: Codable {
    public let callId: String
    public let rejectedById: String
    public let rejectedByName: String
    
    public init(callId: String, rejectedById: String, rejectedByName: String) {
        self.callId = callId
        self.rejectedById = rejectedById
        self.rejectedByName = rejectedByName
    }
}

// MARK: - Socket Models
public struct JoinCallSocketData: Codable {
    let callId: String
    let participantId: String
    let userName: String
}

public struct CallInvitationData: Codable {
    let targetUserId: String
    let callId: String
    let callType: CallType
    let callerId: String
    let callerName: String
}

// MARK: - Signal Models
public enum SignalType: String, Codable {
    case offer
    case answer
    case iceCandidate = "ice-candidate"
}

public struct SignalData: Codable {
    public let fromId: String
    public let targetId: String?
    public let callId: String?
    public let signal: SignalPayload
    public let type: SignalType
    
    public init(fromId: String, targetId: String? = nil, callId: String? = nil, signal: SignalPayload, type: SignalType) {
        self.fromId = fromId
        self.targetId = targetId
        self.callId = callId
        self.signal = signal
        self.type = type
    }
}

public struct SignalPayload: Codable {
    public let sdp: String?
    public let type: String?
    public let candidate: String?
    public let sdpMid: String?
    public let sdpMLineIndex: Int?
    
    public init(sdp: String? = nil, type: String? = nil, candidate: String? = nil, sdpMid: String? = nil, sdpMLineIndex: Int? = nil) {
        self.sdp = sdp
        self.type = type
        self.candidate = candidate
        self.sdpMid = sdpMid
        self.sdpMLineIndex = sdpMLineIndex
    }
}