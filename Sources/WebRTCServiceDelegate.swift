import Foundation
import WebRTC

public protocol WebRTCServiceDelegate: AnyObject {

    // Socket
    func onConnectionChange(_ connected: Bool)
    func onError(_ message: String)

    // Users
    func onOnlineUsers(_ users: [[String: Any]])

    // Calls
    func onIncomingCall(_ data: [String: Any])
    func onCallAccepted(_ data: [String: Any])
    func onCallRejected(_ data: [String: Any])

    // Participants
    func onParticipantJoined(_ data: [String: Any])
    func onParticipantLeft(_ data: [String: Any])

    // Media
    func onLocalStream(_ stream: RTCMediaStream)
    func onRemoteStream(participantId: String, stream: RTCMediaStream)
    func onRemoteStreamRemoved(participantId: String)
}
