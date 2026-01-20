import Foundation
import GoogleWebRTC

public struct WebRTCServiceDelegates {
    public var onConnectionChange: ((Bool) -> Void)?
    public var onLocalStream: ((RTCMediaStream) -> Void)?
    public var onRemoteStream: ((String, RTCMediaStream) -> Void)?
    public var onRemoteStreamRemoved: ((String) -> Void)?
    public var onOnlineUsers: (([OnlineUser]) -> Void)?
    public var onIncomingCall: ((IncomingCallData) -> Void)?
    public var onCallAccepted: ((CallAcceptedData) -> Void)?
    public var onCallRejected: ((CallRejectedData) -> Void)?
    public var onParticipantJoined: ((ParticipantData) -> Void)?
    public var onParticipantLeft: ((ParticipantLeftData) -> Void)?
    public var onError: ((String) -> Void)?
    
    public init() {}
}

class WebRTCService: NSObject {
    var delegates: WebRTCServiceDelegates?
    
    // Properties matching JS implementation
    private var socketService: SocketService?
    private var webRTCManager: WebRTCManager?
    private var apiClient: APIClient?
    
    private(set) var currentCallId: String?
    private(set) var currentParticipantId: String?
    private(set) var userId: String?
    private(set) var userName: String?
    var baseUrl: String?
    
    private let mediaManager = MediaManager()
    
    override init() {
        super.init()
        self.webRTCManager = WebRTCManager(webRTCService: self)
    }
    
    /// Initialize connection to backend
    func connect(userId: String, userName: String) async throws {
        guard let baseUrl = baseUrl else {
            throw WebRTCError.missingConfiguration("Base URL not configured")
        }
        
        guard !userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WebRTCError.validationError("Username is required")
        }
        
        // If already connected with same user, don't reconnect
        if socketService?.isConnected == true && self.userId == userId {
            Logger.log("⚠️ Already connected, skipping reconnection")
            return
        }
        
        // Disconnect existing connection if different user
        if socketService?.isConnected == true && self.userId != userId {
            Logger.log("🔄 Disconnecting previous connection")
            disconnect()
        }
        
        self.userId = userId
        self.userName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Initialize services
        self.apiClient = APIClient(baseUrl: baseUrl)
        self.socketService = SocketService(baseUrl: baseUrl, webRTCService: self)
        
        // Connect socket
        try await socketService?.connect(userId: userId, userName: self.userName)
        
        // Setup socket event handlers
        setupSocketEventHandlers()
    }
    
    /// Setup all socket event handlers
    private func setupSocketEventHandlers() {
        guard let socketService = socketService else { return }
        
        socketService.onOnlineUsers = { [weak self] users in
            Logger.log("📢 Online users: \(users.count)")
            self?.delegates?.onOnlineUsers?(users)
        }
        
        socketService.onIncomingCall = { [weak self] data in
            Logger.log("📞 Incoming call from: \(data.callerName)")
            self?.delegates?.onIncomingCall?(data)
        }
        
        socketService.onCallAccepted = { [weak self] data in
            Logger.log("✅ Call accepted by: \(data.acceptedByName)")
            self?.delegates?.onCallAccepted?(data)
        }
        
        socketService.onCallRejected = { [weak self] data in
            Logger.log("❌ Call rejected by: \(data.rejectedByName)")
            self?.delegates?.onCallRejected?(data)
        }
        
        socketService.onCallJoined = { [weak self] data in
            Task { [weak self] in
                await self?.handleCallJoined(data)
            }
        }
        
        socketService.onParticipantJoined = { [weak self] data in
            Task { [weak self] in
                await self?.handleParticipantJoined(data)
            }
        }
        
        socketService.onParticipantLeft = { [weak self] data in
            self?.handleParticipantLeft(data)
        }
        
        socketService.onSignal = { [weak self] data in
            Task { [weak self] in
                await self?.handleSignal(data)
            }
        }
        
        socketService.onError = { [weak self] errorMessage in
            Logger.error("❌ Server error: \(errorMessage)")
            self?.delegates?.onError?(errorMessage)
        }
        
        socketService.onConnectionChange = { [weak self] isConnected in
            self?.delegates?.onConnectionChange?(isConnected)
        }
    }
    
    /// Create a new call
    func createCall(callType: CallType, isGroup: Bool, maxParticipants: Int) async throws -> CreateCallResponse {
        guard let apiClient = apiClient else {
            throw WebRTCError.notConnected
        }
        
        let request = CreateCallRequest(
            callType: callType,
            isGroup: isGroup,
            maxParticipants: maxParticipants
        )
        
        let response = try await apiClient.createCall(request: request)
        
        guard response.success else {
            throw WebRTCError.apiError(response.error ?? "Failed to create call")
        }
        
        Logger.log("✅ Call created: \(response.callId)")
        
        // Update ICE servers
        webRTCManager?.updateICEServers(response.config.iceServers)
        
        return response
    }
    
    /// Join an existing call
    func joinCall(callId: String) async throws -> JoinCallResponse {
        guard let apiClient = apiClient,
              let userId = userId,
              let userName = userName else {
            throw WebRTCError.notConnected
        }
        
        let request = JoinCallRequest(
            userName: userName,
            userId: userId
        )
        
        let response = try await apiClient.joinCall(callId: callId, request: request)
        
        guard response.success else {
            throw WebRTCError.apiError(response.error ?? "Failed to join call")
        }
        
        Logger.log("✅ Joined call via API: \(response.callId)")
        
        self.currentCallId = response.callId
        self.currentParticipantId = response.participantId
        
        // Update ICE servers
        webRTCManager?.updateICEServers(response.config.iceServers)
        
        // Get local media
        let localStream = try await getLocalMediaStream()
        
        // Join via socket
        let joinData = JoinCallSocketData(
            callId: response.callId,
            participantId: response.participantId,
            userName: userName
        )
        socketService?.joinCall(joinData)
        
        return response
    }
    
    /// Get local media stream
    func getLocalMediaStream(constraints: MediaConstraints? = nil) async throws -> RTCMediaStream {
        let stream = try await mediaManager.getLocalMediaStream(constraints: constraints)
        
        // Add tracks to WebRTC manager
        webRTCManager?.addLocalStream(stream)
        
        delegates?.onLocalStream?(stream)
        
        return stream
    }
    
    /// Handle call joined event
    private func handleCallJoined(_ data: CallJoinedData) async {
        Logger.log("✅ Joined call: \(data.callId)")
        Logger.log("Other participants: \(data.participants)")
        
        // Update ICE servers
        webRTCManager?.updateICEServers(data.iceServers)
        
        // Create peer connections for existing participants
        for participant in data.participants {
            await webRTCManager?.createPeerConnection(
                participantId: participant.id,
                isInitiator: true
            )
        }
    }
    
    /// Handle participant joined event
    private func handleParticipantJoined(_ data: ParticipantData) async {
        Logger.log("👤 Participant joined: \(data.userName)")
        
        if data.participantId != currentParticipantId {
            await webRTCManager?.createPeerConnection(
                participantId: data.participantId,
                isInitiator: false
            )
        }
        
        delegates?.onParticipantJoined?(data)
    }
    
    /// Handle participant left event
    private func handleParticipantLeft(_ data: ParticipantLeftData) {
        Logger.log("👋 Participant left: \(data.participantId)")
        
        webRTCManager?.removePeerConnection(participantId: data.participantId)
        
        delegates?.onParticipantLeft?(data)
    }
    
    /// Handle incoming signals
    private func handleSignal(_ data: SignalData) async {
        Logger.log("📡 Received signal from \(data.fromId): \(data.type)")
        
        await webRTCManager?.handleSignal(data)
    }
    
    /// Send call invitation
    func sendCallInvitation(targetUserId: String, callId: String, callType: CallType) async throws {
        guard socketService?.isConnected == true,
              let userId = userId,
              let userName = userName else {
            throw WebRTCError.notConnected
        }
        
        let invitation = CallInvitationData(
            targetUserId: targetUserId,
            callId: callId,
            callType: callType,
            callerId: userId,
            callerName: userName
        )
        
        try await socketService?.sendCallInvitation(invitation)
    }
    
    /// Accept incoming call
    func acceptCall(callId: String, callerId: String) {
        socketService?.acceptCall(callId: callId, callerId: callerId)
    }
    
    /// Reject incoming call
    func rejectCall(callId: String, callerId: String) {
        socketService?.rejectCall(callId: callId, callerId: callerId)
    }
    
    /// Leave current call
    func leaveCall() {
        guard let currentCallId = currentCallId else { return }
        
        Logger.log("👋 Leaving call: \(currentCallId)")
        
        socketService?.leaveCall(callId: currentCallId, reason: "left")
        
        // Cleanup WebRTC
        webRTCManager?.cleanup()
        
        // Cleanup media
        mediaManager.cleanup()
        
        // Reset state
        self.currentCallId = nil
        self.currentParticipantId = nil
    }
    
    /// Toggle audio
    func toggleAudio(enabled: Bool) {
        mediaManager.toggleAudio(enabled: enabled)
        Logger.log("🎤 Audio: \(enabled ? "enabled" : "disabled")")
    }
    
    /// Toggle video
    func toggleVideo(enabled: Bool) {
        mediaManager.toggleVideo(enabled: enabled)
        Logger.log("📹 Video: \(enabled ? "enabled" : "disabled")")
    }
    
    /// Disconnect from server
    func disconnect() {
        leaveCall()
        socketService?.disconnect()
    }
    
    // MARK: - WebRTC Manager Callbacks
    
    func onRemoteStreamAdded(participantId: String, stream: RTCMediaStream) {
        delegates?.onRemoteStream?(participantId, stream)
    }
    
    func onRemoteStreamRemoved(participantId: String) {
        delegates?.onRemoteStreamRemoved?(participantId)
    }
    
    func sendSignal(_ signal: SignalData) {
        socketService?.sendSignal(signal)
    }
}