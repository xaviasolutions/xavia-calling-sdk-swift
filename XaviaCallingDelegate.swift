import Foundation
import webrtc_ios

/// Delegate protocol for XaviaCallingService events
public protocol XaviaCallingDelegate: AnyObject {
    /// Called when connection status changes
    func onConnectionChange(_ connected: Bool)
    
    /// Called when local media stream is obtained
    func onLocalStream(_ stream: RTCMediaStream)
    
    /// Called when remote stream is received from a participant
    func onRemoteStream(participantId: String, stream: RTCMediaStream)
    
    /// Called when remote stream is removed
    func onRemoteStreamRemoved(participantId: String)
    
    /// Called with list of online users
    func onOnlineUsers(_ users: [[String: Any]])
    
    /// Called when incoming call invitation is received
    func onIncomingCall(_ data: [String: Any])
    
    /// Called when call is accepted by recipient
    func onCallAccepted(_ data: [String: Any])
    
    /// Called when call is rejected by recipient
    func onCallRejected(_ data: [String: Any])
    
    /// Called when a new participant joins the call
    func onParticipantJoined(_ data: [String: Any])
    
    /// Called when a participant leaves the call
    func onParticipantLeft(_ data: [String: Any])
    
    /// Called when an error occurs
    func onError(_ message: String)
}

/// Optional delegate methods with default implementations
public extension XaviaCallingDelegate {
    func onConnectionChange(_ connected: Bool) {}
    func onLocalStream(_ stream: RTCMediaStream) {}
    func onRemoteStream(participantId: String, stream: RTCMediaStream) {}
    func onRemoteStreamRemoved(participantId: String) {}
    func onOnlineUsers(_ users: [[String: Any]]) {}
    func onIncomingCall(_ data: [String: Any]) {}
    func onCallAccepted(_ data: [String: Any]) {}
    func onCallRejected(_ data: [String: Any]) {}
    func onParticipantJoined(_ data: [String: Any]) {}
    func onParticipantLeft(_ data: [String: Any]) {}
    func onError(_ message: String) {}
}
