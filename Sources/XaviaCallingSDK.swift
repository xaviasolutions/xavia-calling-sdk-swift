import Foundation
import GoogleWebRTC

/// Main SDK entry point - Production-ready iOS WebRTC calling SDK
public class XaviaCallingSDK {
    
    // MARK: - Singleton
    public static let shared = XaviaCallingSDK()
    
    // MARK: - Properties
    private let signaling: SignalingService
    private let webrtcManager: WebRTCCallManager
    private let mediaManager: MediaStreamManager
    
    private let operationQueue = DispatchQueue(label: "com.xavia.sdk", attributes: .concurrent)
    
    // SDK State
    private(set) var isConnected = false
    private(set) var currentCallId: String?
    private(set) var currentParticipantId: String?
    private(set) var localStream: RTCMediaStream?
    private(set) var remoteStreams: [String: RTCMediaStream] = [:]
    
    // MARK: - Public Event Delegates
    
    /// Called when connection state changes
    public var onConnectionStateChanged: ((Bool) -> Void)?
    
    /// Called when local media stream is ready
    public var onLocalStreamReady: ((RTCMediaStream) -> Void)?
    
    /// Called when remote stream is received
    public var onRemoteStreamReceived: ((String, RTCMediaStream) -> Void)?
    
    /// Called when remote stream is removed
    public var onRemoteStreamRemoved: ((String) -> Void)?
    
    /// Called when online users list is received
    public var onOnlineUsersUpdated: (([OnlineUser]) -> Void)?
    
    /// Called when incoming call is received
    public var onIncomingCall: ((IncomingCall) -> Void)?
    
    /// Called when call is accepted by remote peer
    public var onCallAccepted: ((CallAccepted) -> Void)?
    
    /// Called when call is rejected by remote peer
    public var onCallRejected: ((CallRejected) -> Void)?
    
    /// Called when participant joins call
    public var onParticipantJoined: ((ParticipantJoined) -> Void)?
    
    /// Called when participant leaves call
    public var onParticipantLeft: ((ParticipantLeft) -> Void)?
    
    /// Called when peer connection state changes
    public var onPeerConnectionStateChanged: ((String, RTCPeerConnectionState) -> Void)?
    
    /// Called when ICE connection state changes
    public var onICEConnectionStateChanged: ((String, RTCIceConnectionState) -> Void)?
    
    /// Called when error occurs
    public var onError: ((Error) -> Void)?
    
    // MARK: - Initialization
    private init() {
        self.signaling = SignalingService()
        self.webrtcManager = WebRTCCallManager()
        self.mediaManager = MediaStreamManager()
        
        setupEventHandlers()
        print("✅ XaviaCallingSDK initialized")
    }
    
    // MARK: - Setup
    
    private func setupEventHandlers() {
        // Signaling events
        signaling.onConnected = { [weak self] in
            self?.operationQueue.async(flags: .barrier) { [weak self] in
                self?.isConnected = true
                self?.onConnectionStateChanged?(true)
            }
        }
        
        signaling.onDisconnected = { [weak self] in
            self?.operationQueue.async(flags: .barrier) { [weak self] in
                self?.isConnected = false
                self?.onConnectionStateChanged?(false)
            }
        }
        
        signaling.onUsersOnline = { [weak self] users in
            self?.onOnlineUsersUpdated?(users)
        }
        
        signaling.onIncomingCall = { [weak self] call in
            self?.onIncomingCall?(call)
        }
        
        signaling.onCallAccepted = { [weak self] accepted in
            self?.onCallAccepted?(accepted)
        }
        
        signaling.onCallRejected = { [weak self] rejected in
            self?.onCallRejected?(rejected)
        }
        
        signaling.onCallJoined = { [weak self] response in
            self?.operationQueue.async(flags: .barrier) { [weak self] in
                self?.currentCallId = response.callId
                self?.currentParticipantId = response.participantId
                self?.webrtcManager.configureICEServers(response.config.iceServers)
                
                // Create peer connections for existing participants
                Task {
                    for participant in response.participants {
                        do {
                            _ = try await self?.webrtcManager.createPeerConnection(
                                participantId: participant.id,
                                isInitiator: true,
                                localStream: self?.localStream
                            )
                        } catch {
                            self?.onError?(error)
                        }
                    }
                }
            }
        }
        
        signaling.onParticipantJoined = { [weak self] joined in
            self?.operationQueue.async(flags: .barrier) { [weak self] in
                if joined.participantId != self?.currentParticipantId {
                    Task {
                        do {
                            _ = try await self?.webrtcManager.createPeerConnection(
                                participantId: joined.participantId,
                                isInitiator: false,
                                localStream: self?.localStream
                            )
                        } catch {
                            self?.onError?(error)
                        }
                    }
                }
            }
            self?.onParticipantJoined?(joined)
        }
        
        signaling.onParticipantLeft = { [weak self] left in
            self?.operationQueue.async(flags: .barrier) { [weak self] in
                self?.webrtcManager.removePeerConnection(participantId: left.participantId)
            }
            self?.onParticipantLeft?(left)
        }
        
        signaling.onSignal = { [weak self] signal in
            self?.handleSignal(signal)
        }
        
        signaling.onError = { [weak self] message in
            self?.onError?(NSError(domain: "SignalingError", code: -1, userInfo: [NSLocalizedDescriptionKey: message]))
        }
        
        // WebRTC events
        webrtcManager.onRemoteStream = { [weak self] participantId, stream in
            self?.operationQueue.async(flags: .barrier) { [weak self] in
                self?.remoteStreams[participantId] = stream
            }
            self?.onRemoteStreamReceived?(participantId, stream)
        }
        
        webrtcManager.onRemoteStreamRemoved = { [weak self] participantId in
            self?.operationQueue.async(flags: .barrier) { [weak self] in
                self?.remoteStreams.removeValue(forKey: participantId)
            }
            self?.onRemoteStreamRemoved?(participantId)
        }
        
        webrtcManager.onConnectionStateChange = { [weak self] participantId, state in
            self?.onPeerConnectionStateChanged?(participantId, state)
        }
        
        webrtcManager.onIceConnectionStateChange = { [weak self] participantId, state in
            self?.onICEConnectionStateChanged?(participantId, state)
        }
        
        webrtcManager.onICECandidate = { [weak self] participantId, candidate in
            guard let self = self, let callId = self.currentCallId else { return }
            
            let signalPayload = SignalPayload(
                sdp: nil,
                type: nil,
                candidate: candidate.candidate,
                sdpMid: candidate.sdpMid,
                sdpMLineIndex: candidate.sdpMLineIndex as? Int
            )
            
            self.signaling.sendSignal(
                callId: callId,
                targetId: participantId,
                signal: signalPayload,
                type: "ice-candidate"
            )
        }
    }
    
    // MARK: - Public API: Connection
    
    /// Initialize SDK connection to backend server
    /// - Parameters:
    ///   - serverUrl: Backend server URL
    ///   - userId: Unique user identifier
    ///   - userName: Display name for the user
    public func initialize(
        serverUrl: String,
        userId: String,
        userName: String
    ) async throws {
        try await signaling.connect(
            serverUrl: serverUrl,
            userId: userId,
            userName: userName
        )
    }
    
    /// Disconnect SDK from server and clean up resources
    public func disconnect() async {
        await leaveCall()
        await signaling.disconnect()
    }
    
    // MARK: - Public API: Call Management
    
    /// Create a new call
    /// - Parameters:
    ///   - callType: Type of call (video/audio)
    ///   - isGroup: Whether it's a group call
    ///   - maxParticipants: Maximum participants allowed
    /// - Returns: Call information with callId
    public func createCall(
        callType: String = "video",
        isGroup: Bool = false,
        maxParticipants: Int = 1000
    ) async throws -> Call {
        return try await signaling.createCall(
            callType: callType,
            isGroup: isGroup,
            maxParticipants: maxParticipants
        )
    }
    
    /// Join an existing call
    /// - Parameters:
    ///   - callId: ID of the call to join
    ///   - userId: Current user ID
    ///   - userName: Current user name
    public func joinCall(
        callId: String,
        userId: String,
        userName: String
    ) async throws {
        let response = try await signaling.joinCall(
            callId: callId,
            userId: userId,
            userName: userName
        )
        
        return await operationQueue.async(flags: .barrier) { [weak self] in
            self?.currentCallId = response.callId
            self?.currentParticipantId = response.participantId
            self?.webrtcManager.configureICEServers(response.config.iceServers)
            
            // Get local media
            Task {
                do {
                    let stream = try await self?.mediaManager.getLocalMedia() ?? RTCMediaStream(streamId: UUID().uuidString)
                    self?.operationQueue.async(flags: .barrier) { [weak self] in
                        self?.localStream = stream
                    }
                    self?.onLocalStreamReady?(stream)
                    
                    // Join via socket
                    await self?.signaling.joinCallSocket(
                        callId: response.callId,
                        participantId: response.participantId,
                        userName: userName
                    )
                    
                    // Create peer connections for existing participants
                    for participant in response.participants {
                        _ = try await self?.webrtcManager.createPeerConnection(
                            participantId: participant.id,
                            isInitiator: true,
                            localStream: stream
                        )
                    }
                } catch {
                    self?.onError?(error)
                }
            }
        }
    }
    
    /// End current call and leave
    public func endCall() async {
        await leaveCall()
    }
    
    private func leaveCall() async {
        await operationQueue.async(flags: .barrier) { [weak self] in
            guard let callId = self?.currentCallId else { return }
            
            self?.signaling.leaveCall(callId: callId)
            self?.webrtcManager.closeAllConnections()
            self?.mediaManager.stopLocalMedia()
            
            self?.currentCallId = nil
            self?.currentParticipantId = nil
            self?.localStream = nil
            self?.remoteStreams.removeAll()
        }
    }
    
    // MARK: - Public API: Call Actions
    
    /// Send call invitation to another user
    /// - Parameters:
    ///   - targetUserId: ID of user to invite
    ///   - callId: ID of the call
    ///   - callType: Type of call (video/audio)
    ///   - callerId: ID of the caller
    ///   - callerName: Name of the caller
    public func sendCallInvitation(
        targetUserId: String,
        callId: String,
        callType: String,
        callerId: String,
        callerName: String
    ) async throws {
        try await signaling.sendCallInvitation(
            targetUserId: targetUserId,
            callId: callId,
            callType: callType,
            callerId: callerId,
            callerName: callerName
        )
    }
    
    /// Accept an incoming call
    /// - Parameters:
    ///   - callId: ID of the call to accept
    ///   - callerId: ID of the caller
    public func acceptCall(callId: String, callerId: String) async throws {
        // Get local media first
        do {
            let stream = try await mediaManager.getLocalMedia()
            await operationQueue.async(flags: .barrier) { [weak self] in
                self?.localStream = stream
            }
            onLocalStreamReady?(stream)
        } catch {
            onError?(error)
            throw error
        }
        
        signaling.acceptCall(callId: callId, callerId: callerId)
    }
    
    /// Reject an incoming call
    /// - Parameters:
    ///   - callId: ID of the call to reject
    ///   - callerId: ID of the caller
    public func rejectCall(callId: String, callerId: String) {
        signaling.rejectCall(callId: callId, callerId: callerId)
    }
    
    // MARK: - Public API: Media Control
    
    /// Enable or disable audio
    /// - Parameter enabled: True to enable audio, false to disable
    public func setAudioEnabled(_ enabled: Bool) {
        mediaManager.setAudioEnabled(enabled)
    }
    
    /// Enable or disable video
    /// - Parameter enabled: True to enable video, false to disable
    public func setVideoEnabled(_ enabled: Bool) {
        mediaManager.setVideoEnabled(enabled)
    }
    
    // MARK: - Public API: State Queries
    
    /// Get current connection state
    /// - Returns: True if connected to server, false otherwise
    public func getConnectionState() -> Bool {
        return isConnected
    }
    
    /// Get current call ID
    /// - Returns: Current call ID or nil if not in call
    public func getCurrentCallId() -> String? {
        return currentCallId
    }
    
    /// Get current participant ID
    /// - Returns: Current participant ID or nil if not in call
    public func getCurrentParticipantId() -> String? {
        return currentParticipantId
    }
    
    /// Get local media stream
    /// - Returns: Local RTCMediaStream or nil if not available
    public func getLocalStream() -> RTCMediaStream? {
        return localStream
    }
    
    /// Get remote stream for participant
    /// - Parameter participantId: ID of the participant
    /// - Returns: Remote RTCMediaStream or nil if not available
    public func getRemoteStream(participantId: String) -> RTCMediaStream? {
        return remoteStreams[participantId]
    }
    
    /// Get all active remote streams
    /// - Returns: Dictionary of participant ID to stream
    public func getAllRemoteStreams() -> [String: RTCMediaStream] {
        return remoteStreams
    }
    
    // MARK: - Private: Signal Handling
    
    private func handleSignal(_ signal: Signal) {
        guard let fromId = signal.fromId else { return }
        
        Task {
            do {
                switch signal.type {
                case "offer":
                    let offer = RTCSessionDescription(
                        type: .offer,
                        sdp: signal.signal.sdp ?? ""
                    )
                    
                    var peerConnection = webrtcManager.peerConnections[fromId]
                    if peerConnection == nil {
                        peerConnection = try await webrtcManager.createPeerConnection(
                            participantId: fromId,
                            isInitiator: false,
                            localStream: localStream
                        )
                    }
                    
                    try await webrtcManager.handleOffer(offer, from: fromId, peerConnection: peerConnection)
                    
                    let answer = RTCSessionDescription(
                        type: .answer,
                        sdp: peerConnection?.localDescription?.sdp ?? ""
                    )
                    
                    let signalPayload = SignalPayload(
                        sdp: answer.sdp,
                        type: answer.type.rawValue,
                        candidate: nil,
                        sdpMid: nil,
                        sdpMLineIndex: nil
                    )
                    
                    if let callId = currentCallId {
                        signaling.sendSignal(
                            callId: callId,
                            targetId: fromId,
                            signal: signalPayload,
                            type: "answer"
                        )
                    }
                    
                case "answer":
                    let answer = RTCSessionDescription(
                        type: .answer,
                        sdp: signal.signal.sdp ?? ""
                    )
                    try await webrtcManager.handleAnswer(answer, from: fromId)
                    
                case "ice-candidate":
                    if let candidate = signal.signal.candidate {
                        let iceCandidate = RTCIceCandidate(
                            sdp: candidate,
                            sdpMLineIndex: Int32(signal.signal.sdpMLineIndex ?? 0),
                            sdpMid: signal.signal.sdpMid
                        )
                        try await webrtcManager.addICECandidate(iceCandidate, from: fromId)
                    }
                    
                default:
                    print("⚠️ Unknown signal type: \(signal.type)")
                }
            } catch {
                print("❌ Error handling signal: \(error)")
                onError?(error)
            }
        }
    }
}
