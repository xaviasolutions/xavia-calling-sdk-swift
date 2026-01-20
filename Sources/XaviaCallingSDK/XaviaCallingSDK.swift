import Foundation
import WebRTC

public class XaviaCallingSDK {
    public static let shared = XaviaCallingSDK()
    
    private let webRTCService = WebRTCService()
    
    private init() {}
    
    /// Configure the SDK with server URL
    public func configure(serverUrl: String) {
        webRTCService.baseUrl = serverUrl
    }
    
    /// Connect to the server and register user
    public func connect(userId: String, userName: String) async throws {
        try await webRTCService.connect(userId: userId, userName: userName)
    }
    
    /// Disconnect from server
    public func disconnect() {
        webRTCService.disconnect()
    }
    
    /// Create a new call
    public func createCall(callType: CallType, isGroup: Bool = false, maxParticipants: Int = 1000) async throws -> CreateCallResponse {
        try await webRTCService.createCall(callType: callType, isGroup: isGroup, maxParticipants: maxParticipants)
    }
    
    /// Join an existing call
    public func joinCall(callId: String) async throws -> JoinCallResponse {
        try await webRTCService.joinCall(callId: callId)
    }
    
    /// Send call invitation
    public func sendCallInvitation(targetUserId: String, callId: String, callType: CallType) async throws {
        try await webRTCService.sendCallInvitation(targetUserId: targetUserId, callId: callId, callType: callType)
    }
    
    /// Accept incoming call
    public func acceptCall(callId: String, callerId: String) {
        webRTCService.acceptCall(callId: callId, callerId: callerId)
    }
    
    /// Reject incoming call
    public func rejectCall(callId: String, callerId: String) {
        webRTCService.rejectCall(callId: callId, callerId: callerId)
    }
    
    /// Leave current call
    public func leaveCall() {
        webRTCService.leaveCall()
    }
    
    /// Toggle local audio
    public func toggleAudio(enabled: Bool) {
        webRTCService.toggleAudio(enabled: enabled)
    }
    
    /// Toggle local video
    public func toggleVideo(enabled: Bool) {
        webRTCService.toggleVideo(enabled: enabled)
    }
    
    /// Set delegates
    public func setDelegates(_ delegates: WebRTCServiceDelegates) {
        webRTCService.delegates = delegates
    }
    
    /// Get local media stream
    public func getLocalMediaStream(constraints: MediaConstraints? = nil) async throws -> RTCMediaStream {
        try await webRTCService.getLocalMediaStream(constraints: constraints)
    }
}