import Foundation
import WebRTC

// MARK: - Data Models

@objc public class CallParticipant: NSObject {
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

@objc public class ICEConfig: NSObject {
    @objc public let iceServers: [RTCIceServer]
    
    @objc public init(iceServers: [RTCIceServer]) {
        self.iceServers = iceServers
    }
}

@objc public class CallResponse: NSObject {
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
        CallResponse(
            success: dictionary["success"] as? Bool ?? false,
            callId: dictionary["callId"] as? String,
            error: dictionary["error"] as? String,
            participantId: dictionary["participantId"] as? String
        )
    }
}

@objc public class IncomingCallData: NSObject {
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
        return IncomingCallData(callerId: callerId, callerName: callerName, callId: callId, callType: callType)
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