import Foundation
import WebRTC

// MARK: - Data Models

@objc public class CallParticipant: NSObject, Codable {
    @objc public let id: String
    @objc public let userName: String
    @objc public let userId: String
    
    @objc public init(id: String, userName: String, userId: String) {
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

@objc public class ICEConfig: NSObject, Codable {
    @objc public let iceServers: [RTCIceServer]
    
    @objc public init(iceServers: [RTCIceServer]) {
        self.iceServers = iceServers
    }
    
    enum CodingKeys: String, CodingKey {
        case iceServers
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let serversData = try container.decode([[String: Any]].self, forKey: .iceServers)
        
        iceServers = serversData.compactMap { serverDict in
            guard let urlsValue = serverDict["urls"] else { return nil }
            
            if let urlString = urlsValue as? String {
                return RTCIceServer(urlStrings: [urlString])
            } else if let urlArray = urlsValue as? [String] {
                let username = serverDict["username"] as? String
                let credential = serverDict["credential"] as? String
                return RTCIceServer(urlStrings: urlArray, username: username, credential: credential)
            }
            return nil
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let serversData = iceServers.map { server -> [String: Any] in
            var dict: [String: Any] = ["urls": server.urlStrings]
            if let username = server.username {
                dict["username"] = username
            }
            if let credential = server.credential {
                dict["credential"] = credential
            }
            return dict
        }
        
        // Custom encoding for RTCIceServer
        var nestedContainer = container.nestedUnkeyedContainer(forKey: .iceServers)
        for server in iceServers {
            var serverContainer = nestedContainer.nestedContainer(keyedBy: DynamicCodingKey.self)
            let urlsKey = DynamicCodingKey(stringValue: "urls")!
            try serverContainer.encode(server.urlStrings, forKey: urlsKey)
            
            if let username = server.username {
                let usernameKey = DynamicCodingKey(stringValue: "username")!
                try serverContainer.encode(username, forKey: usernameKey)
            }
            
            if let credential = server.credential {
                let credentialKey = DynamicCodingKey(stringValue: "credential")!
                try serverContainer.encode(credential, forKey: credentialKey)
            }
        }
    }
}

// Helper for dynamic coding keys
private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    
    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }
    
    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

@objc public class CallResponse: NSObject, Codable {
    @objc public let success: Bool
    @objc public let callId: String?
    @objc public let error: String?
    @objc public let config: ICEConfig?
    @objc public let participantId: String?
    
    @objc public init(success: Bool, callId: String? = nil, error: String? = nil, 
                config: ICEConfig? = nil, participantId: String? = nil) {
        self.success = success
        self.callId = callId
        self.error = error
        self.config = config
        self.participantId = participantId
    }
    
    static func from(dictionary: [String: Any]) -> CallResponse {
        var config: ICEConfig? = nil
        if let configDict = dictionary["config"] as? [String: Any],
           let iceServersData = configDict["iceServers"] as? [[String: Any]] {
            let iceServers = iceServersData.compactMap { serverDict -> RTCIceServer? in
                guard let urlsValue = serverDict["urls"] else { return nil }
                if let urlString = urlsValue as? String {
                    return RTCIceServer(urlStrings: [urlString])
                } else if let urlArray = urlsValue as? [String] {
                    let username = serverDict["username"] as? String
                    let credential = serverDict["credential"] as? String
                    return RTCIceServer(urlStrings: urlArray, username: username, credential: credential)
                }
                return nil
            }
            config = ICEConfig(iceServers: iceServers)
        }
        
        return CallResponse(
            success: dictionary["success"] as? Bool ?? false,
            callId: dictionary["callId"] as? String,
            error: dictionary["error"] as? String,
            config: config,
            participantId: dictionary["participantId"] as? String
        )
    }
}

@objc public class IncomingCallData: NSObject, Codable {
    @objc public let callerId: String
    @objc public let callerName: String
    @objc public let callId: String
    @objc public let callType: String
    
    @objc public init(callerId: String, callerName: String, callId: String, callType: String) {
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

@objc public class SignalData: NSObject {
    @objc public let fromId: String
    @objc public let signal: SignalContent
    @objc public let type: SignalType
    
    @objc public init(fromId: String, signal: SignalContent, type: SignalType) {
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

@objc public class SignalContent: NSObject {
    @objc public let sdp: String?
    @objc public let type: String?
    @objc public let candidate: String?
    @objc public let sdpMid: String?
    @objc public let sdpMLineIndex: Int32?
    
    @objc public init(sdp: String? = nil, type: String? = nil, candidate: String? = nil, 
                sdpMid: String? = nil, sdpMLineIndex: Int32? = nil) {
        self.sdp = sdp
        self.type = type
        self.candidate = candidate
        self.sdpMid = sdpMid
        self.sdpMLineIndex = sdpMLineIndex
    }
}

@objc public enum SignalType: Int {
    case offer
    case answer
    case iceCandidate
    
    var rawValue: String {
        switch self {
        case .offer: return "offer"
        case .answer: return "answer"
        case .iceCandidate: return "ice-candidate"
        }
    }
    
    init?(rawValue: String) {
        switch rawValue {
        case "offer": self = .offer
        case "answer": self = .answer
        case "ice-candidate": self = .iceCandidate
        default: return nil
        }
    }
}

// MARK: - Errors

@objc public enum WebRTCError: Int, LocalizedError {
    case invalidUsername
    case notConnected
    case invalidURL
    case networkError
    case serverError
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
        case .serverError:
            return "Server error"
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
    
    public static func serverError(_ message: String) -> NSError {
        return NSError(domain: "WebRTCService", 
                      code: WebRTCError.serverError.rawValue, 
                      userInfo: [NSLocalizedDescriptionKey: message])
    }
}