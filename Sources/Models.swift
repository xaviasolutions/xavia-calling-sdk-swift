import Foundation
import WebRTC

// MARK: - Data Models

public struct CallParticipant: Codable {
    public let id: String
    public let userName: String
    public let userId: String
    
    public init(id: String, userName: String, userId: String) {
        self.id = id
        self.userName = userName
        self.userId = userId
    }
    
    static func from(dictionary: [String: Any]) -> CallParticipant? {
        guard let id = dictionary["id"] as? String,
              let userName = dictionary["userName"] as? String,
              let userId = dictionary["userId"] as? String else {
            return nil
        }
        return CallParticipant(id: id, userName: userName, userId: userId)
    }
}

public struct ICEConfig: Codable {
    public let iceServers: [RTCIceServer]
    
    public init(iceServers: [RTCIceServer]) {
        self.iceServers = iceServers
    }
    
    enum CodingKeys: String, CodingKey {
        case iceServers
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let serversData = try container.decode([[String: [String]]].self, forKey: .iceServers)
        
        iceServers = serversData.compactMap { serverDict in
            guard let urls = serverDict["urls"] else { return nil }
            return RTCIceServer(urlStrings: urls)
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let serversData = iceServers.map { ["urls": $0.urlStrings] }
        try container.encode(serversData, forKey: .iceServers)
    }
}

public struct CallResponse: Codable {
    public let success: Bool
    public let callId: String?
    public let error: String?
    public let config: ICEConfig?
    public let participantId: String?
    
    public init(success: Bool, callId: String? = nil, error: String? = nil, 
                config: ICEConfig? = nil, participantId: String? = nil) {
        self.success = success
        self.callId = callId
        self.error = error
        self.config = config
        self.participantId = participantId
    }
    
    static func from(dictionary: [String: Any]) -> CallResponse {
        CallResponse(
            success: dictionary["success"] as? Bool ?? false,
            callId: dictionary["callId"] as? String,
            error: dictionary["error"] as? String,
            participantId: dictionary["participantId"] as? String
        )
    }
}

public struct IncomingCallData: Codable {
    public let callerId: String
    public let callerName: String
    public let callId: String
    public let callType: String
    
    public init(callerId: String, callerName: String, callId: String, callType: String) {
        self.callerId = callerId
        self.callerName = callerName
        self.callId = callId
        self.callType = callType
    }
    
    static func from(dictionary: [String: Any]) -> IncomingCallData? {
        guard let callerId = dictionary["callerId"] as? String,
              let callerName = dictionary["callerName"] as? String,
              let callId = dictionary["callId"] as? String,
              let callType = dictionary["callType"] as? String else {
            return nil
        }
        return IncomingCallData(
            callerId: callerId,
            callerName: callerName,
            callId: callId,
            callType: callType
        )
    }
}

public struct SignalData {
    public let fromId: String
    public let signal: SignalContent
    public let type: SignalType
    
    public init(fromId: String, signal: SignalContent, type: SignalType) {
        self.fromId = fromId
        self.signal = signal
        self.type = type
    }
    
    static func from(dictionary: [String: Any]) -> SignalData? {
        guard let fromId = dictionary["fromId"] as? String,
              let signalDict = dictionary["signal"] as? [String: Any],
              let typeString = dictionary["type"] as? String,
              let type = SignalType(rawValue: typeString) else {
            return nil
        }
        
        let signal = SignalContent(
            sdp: signalDict["sdp"] as? String,
            type: signalDict["type"] as? String,
            candidate: signalDict["candidate"] as? String,
            sdpMid: signalDict["sdpMid"] as? String,
            sdpMLineIndex: signalDict["sdpMLineIndex"] as? Int32
        )
        
        return SignalData(fromId: fromId, signal: signal, type: type)
    }
}

public struct SignalContent {
    public let sdp: String?
    public let type: String?
    public let candidate: String?
    public let sdpMid: String?
    public let sdpMLineIndex: Int32?
    
    public init(sdp: String? = nil, type: String? = nil, candidate: String? = nil, 
                sdpMid: String? = nil, sdpMLineIndex: Int32? = nil) {
        self.sdp = sdp
        self.type = type
        self.candidate = candidate
        self.sdpMid = sdpMid
        self.sdpMLineIndex = sdpMLineIndex
    }
}

public enum SignalType: String {
    case offer
    case answer
    case iceCandidate = "ice-candidate"
}

// MARK: - Errors

public enum WebRTCError: LocalizedError {
    case invalidUsername
    case notConnected
    case invalidURL
    case networkError
    case serverError(String)
    case invalidResponse
    case connectionTimeout
    case invalidSignal
    case permissionDenied
    
    public var errorDescription: String? {
        switch self {
        case .invalidUsername:
            return "Username is required"
        case .notConnected:
            return "Not connected to server"
        case .invalidURL:
            return "Invalid server URL"
        case .networkError:
            return "Network error occurred"
        case .serverError(let message):
            return message
        case .invalidResponse:
            return "Invalid response from server"
        case .connectionTimeout:
            return "Connection timeout"
        case .invalidSignal:
            return "Invalid signal received"
        case .permissionDenied:
            return "Camera or microphone permission denied"
        }
    }
}