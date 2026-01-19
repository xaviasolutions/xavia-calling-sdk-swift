import Foundation
import WebRTC

// MARK: - Delegate Protocol

public protocol WebRTCServiceDelegate: AnyObject {
    func onConnectionChange(_ connected: Bool)
    func onLocalStream(_ stream: RTCMediaStream)
    func onRemoteStream(participantId: String, stream: RTCMediaStream)
    func onRemoteStreamRemoved(participantId: String)
    func onOnlineUsers(_ users: [[String: Any]])
    func onIncomingCall(_ data: [String: Any])
    func onCallAccepted(_ data: [String: Any])
    func onCallRejected(_ data: [String: Any])
    func onParticipantJoined(_ data: [String: Any])
    func onParticipantLeft(_ data: [String: Any])
    func onError(_ message: String)
}