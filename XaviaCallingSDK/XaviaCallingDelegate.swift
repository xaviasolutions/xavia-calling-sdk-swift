// XaviaCallingDelegate.swift

import Foundation
import WebRTC

/// Delegate protocol for receiving events from XaviaCallingService
public protocol XaviaCallingDelegate: AnyObject {
    /// Socket connection state changed
    func connectionChanged(connected: Bool)
    
    /// Local media stream is ready
    func didReceiveLocalStream(_ stream: RTCMediaStream)
    
    /// New remote stream received from participant
    func didReceiveRemoteStream(_ stream: RTCMediaStream, from participantId: String)
    
    /// Remote stream was removed
    func didRemoveRemoteStream(for participantId: String)
    
    /// List of currently online users
    func didReceiveOnlineUsers(_ users: [[String: Any]])
    
    /// Incoming call invitation received
    func didReceiveIncomingCall(_ data: [String: Any])
    
    /// Someone accepted the call
    func didReceiveCallAccepted(_ data: [String: Any])
    
    /// Someone rejected the call
    func didReceiveCallRejected(_ data: [String: Any])
    
    /// New participant joined the call
    func didReceiveParticipantJoined(_ data: [String: Any])
    
    /// Participant left the call
    func didReceiveParticipantLeft(_ data: [String: Any])
    
    /// Error occurred (connection, signaling, media, etc.)
    func didReceiveError(_ message: String)
}