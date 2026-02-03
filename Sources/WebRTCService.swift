import Foundation
import WebRTC
import SocketIO

// MARK: - Public API (Same as JavaScript)

public protocol WebRTCServiceDelegate: AnyObject {
    func onConnectionChange(_ isConnected: Bool)
    func onLocalStream(_ stream: RTCMediaStream)
    func onRemoteStream(_ participantId: String, stream: RTCMediaStream)
    func onRemoteStreamRemoved(_ participantId: String)
    func onOnlineUsers(_ users: [CallParticipant])
    func onIncomingCall(_ data: IncomingCallData)
    func onCallAccepted(_ data: CallResponse)
    func onCallRejected(_ data: CallResponse)
    func onParticipantJoined(_ participant: CallParticipant)
    func onParticipantLeft(_ participant: CallParticipant)
    func onError(_ message: String)
}

public final class WebRTCService {
    
    // MARK: - Singleton
    public static let shared = WebRTCService()
    private init() {}
    
    // MARK: - Public Properties
    public weak var delegate: WebRTCServiceDelegate?
    
    // Callback closures for flexibility (mirroring JavaScript)
    public var onConnectionChange: ((Bool) -> Void)?
    public var onLocalStream: ((RTCMediaStream) -> Void)?
    public var onRemoteStream: ((String, RTCMediaStream) -> Void)?
    public var onRemoteStreamRemoved: ((String) -> Void)?
    public var onOnlineUsers: (([CallParticipant]) -> Void)?
    public var onIncomingCall: ((IncomingCallData) -> Void)?
    public var onCallAccepted: ((CallResponse) -> Void)?
    public var onCallRejected: ((CallResponse) -> Void)?
    public var onParticipantJoined: ((CallParticipant) -> Void)?
    public var onParticipantLeft: ((CallParticipant) -> Void)?
    public var onError: ((String) -> Void)?
    
    // MARK: - Private Properties
    private var socket: SocketIOClient?
    private var manager: SocketManager?
    
    private var peerConnections: [String: RTCPeerConnection] = [:]
    private var remoteStreams: [String: RTCMediaStream] = [:]
    private var localStream: RTCMediaStream?
    private var currentCallId: String?
    private var currentParticipantId: String?
    private var userId: String?
    private var userName: String?
    private var iceServers: [RTCIceServer] = []
    private var baseUrl: String?
    
    // MARK: - Factory
    private lazy var factory: RTCPeerConnectionFactory = {
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        return RTCPeerConnectionFactory(
            encoderFactory: videoEncoderFactory,
            decoderFactory: videoDecoderFactory
        )
    }()
    
    // MARK: - Connection Management
    
    /// Connect to the signaling server
    /// - Parameters:
    ///   - serverUrl: The server URL
    ///   - userId: User identifier
    ///   - userName: User display name
    public func connect(serverUrl: String, userId: String, userName: String) async throws {
        // Validate username
        guard !userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WebRTCError.invalidUsername
        }
        
        // If already connected with same user, skip
        if let socket = socket, socket.status == .connected, self.userId == userId {
            print("⚠️ Already connected, skipping reconnection")
            return
        }
        
        // Cleanup if different user
        if socket != nil && self.userId != userId {
            disconnect()
        }
        
        self.baseUrl = serverUrl
        self.userId = userId
        self.userName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        print("🔌 Connecting to server: \(serverUrl)")
        
        // Create Socket.IO connection
        guard let url = URL(string: serverUrl) else {
            throw WebRTCError.invalidURL
        }
        
        await MainActor.run {
            self.manager = SocketManager(
                socketURL: url,
                config: [
                    .log(false),
                    .compress,
                    .reconnects(true),
                    .reconnectAttempts(5),
                    .reconnectWait(1000),
                    .connectParams([
                        "userId": userId,
                        "userName": userName
                    ])
                ]
            )
            
            self.socket = manager?.defaultSocket
            setupSocketListeners()
            self.socket?.connect()
        }
        
        // Wait for connection
        try await waitForConnection()
    }
    
    private func waitForConnection() async throws {
        for _ in 0..<50 { // 5 second timeout
            if socket?.status == .connected {
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        }
        throw WebRTCError.connectionTimeout
    }
    
    /// Disconnect from server
    public func disconnect() {
        leaveCall()
        
        socket?.disconnect()
        socket = nil
        manager = nil
        
        userId = nil
        userName = nil
        baseUrl = nil
        
        notifyConnectionChange(false)
    }
    
    // MARK: - Call Management
    
    /// Create a new call
    /// - Parameters:
    ///   - callType: "audio" or "video"
    ///   - isGroup: Whether it's a group call
    ///   - maxParticipants: Maximum participants allowed
    /// - Returns: Call response with call ID
    public func createCall(callType: String = "video", isGroup: Bool = false, maxParticipants: Int = 1000) async throws -> CallResponse {
        guard let baseUrl = baseUrl else {
            throw WebRTCError.notConnected
        }
        
        guard let url = URL(string: "\(baseUrl)/api/calls") else {
            throw WebRTCError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "callType": callType,
            "isGroup": isGroup,
            "maxParticipants": maxParticipants
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw WebRTCError.networkError
        }
        
        let decoder = JSONDecoder()
        let result = try decoder.decode(CallResponse.self, from: data)
        
        if !result.success {
            throw WebRTCError.serverError(result.error ?? "Failed to create call")
        }
        
        print("✅ Call created: \(result.callId ?? "unknown")")
        
        if let iceServers = result.config?.iceServers {
            self.iceServers = iceServers
        }
        
        return result
    }
    
    /// Join an existing call
    /// - Parameter callId: The call ID to join
    /// - Returns: Call response with participant details
    public func joinCall(callId: String) async throws -> CallResponse {
        guard let baseUrl = baseUrl,
              let userId = userId,
              let userName = userName else {
            throw WebRTCError.notConnected
        }
        
        guard let url = URL(string: "\(baseUrl)/api/calls/\(callId)/join") else {
            throw WebRTCError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "userName": userName,
            "userId": userId
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw WebRTCError.networkError
        }
        
        let decoder = JSONDecoder()
        let result = try decoder.decode(CallResponse.self, from: data)
        
        if !result.success {
            throw WebRTCError.serverError(result.error ?? "Failed to join call")
        }
        
        print("✅ Joined call via API: \(result.callId ?? "unknown")")
        
        currentCallId = result.callId
        currentParticipantId = result.participantId
        
        if let iceServers = result.config?.iceServers {
            self.iceServers = iceServers
        }
        
        // Get local media
        try await getLocalMedia()
        
        // Join via socket
        socket?.emit("join-call", [
            "callId": result.callId ?? "",
            "participantId": result.participantId ?? "",
            "userName": userName
        ])
        
        return result
    }
    
    /// Get local media stream
    /// - Returns: Local media stream
    public func getLocalMedia() async throws -> RTCMediaStream {
        let streamId = "local_stream_\(UUID().uuidString)"
        let stream = factory.mediaStream(withStreamId: streamId)
        
        // Add video track
        let videoSource = factory.videoSource()
        let videoTrack = factory.videoTrack(with: videoSource, trackId: "video_\(UUID().uuidString)")
        
        // Configure video constraints
        let videoConstraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "minWidth": "640",
                "minHeight": "480",
                "maxWidth": "1920",
                "maxHeight": "1080",
                "minFrameRate": "20",
                "maxFrameRate": "60"
            ],
            optionalConstraints: nil
        )
        
        // TODO: Configure video capturer here
        stream.addVideoTrack(videoTrack)
        
        // Add audio track
        let audioConstraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: [
                "googEchoCancellation": "true",
                "googNoiseSuppression": "true",
                "googAutoGainControl": "true"
            ]
        )
        
        let audioSource = factory.audioSource(with: audioConstraints)
        let audioTrack = factory.audioTrack(with: audioSource, trackId: "audio_\(UUID().uuidString)")
        stream.addAudioTrack(audioTrack)
        
        localStream = stream
        print("✅ Local media obtained")
        
        notifyLocalStream(stream)
        
        return stream
    }
    
    /// Send call invitation
    public func sendCallInvitation(targetUserId: String, callId: String, callType: String) async throws -> CallResponse {
        guard let userId = userId, let userName = userName else {
            throw WebRTCError.notConnected
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            socket?.emitWithAck("send-call-invitation", [
                "targetUserId": targetUserId,
                "callId": callId,
                "callType": callType,
                "callerId": userId,
                "callerName": userName
            ]).timingOut(after: 10) { data in
                if let dict = data.first as? [String: Any] {
                    let response = CallResponse(
                        success: dict["success"] as? Bool ?? false,
                        callId: dict["callId"] as? String,
                        error: dict["error"] as? String
                    )
                    
                    if response.success {
                        continuation.resume(returning: response)
                    } else {
                        continuation.resume(throwing: WebRTCError.serverError(response.error ?? "Invitation failed"))
                    }
                } else {
                    continuation.resume(throwing: WebRTCError.invalidResponse)
                }
            }
        }
    }
    
    /// Accept incoming call
    public func acceptCall(callId: String, callerId: String) {
        socket?.emit("accept-call", [
            "callId": callId,
            "callerId": callerId
        ])
    }
    
    /// Reject incoming call
    public func rejectCall(callId: String, callerId: String) {
        socket?.emit("reject-call", [
            "callId": callId,
            "callerId": callerId
        ])
    }
    
    /// Leave current call
    public func leaveCall() {
        guard let callId = currentCallId else { return }
        
        print("👋 Leaving call: \(callId)")
        
        socket?.emit("leave-call", [
            "callId": callId,
            "reason": "left"
        ])
        
        // Cleanup
        cleanupPeerConnections()
        
        currentCallId = nil
        currentParticipantId = nil
    }
    
    /// Toggle audio
    public func toggleAudio(enabled: Bool) {
        localStream?.audioTracks.forEach { $0.isEnabled = enabled }
        print("🎤 Audio: \(enabled ? "enabled" : "disabled")")
    }
    
    /// Toggle video
    public func toggleVideo(enabled: Bool) {
        localStream?.videoTracks.forEach { $0.isEnabled = enabled }
        print("📹 Video: \(enabled ? "enabled" : "disabled")")
    }
    
    // MARK: - Helper Properties
    
    public var isConnected: Bool {
        socket?.status == .connected
    }
    
    public var currentCall: String? {
        currentCallId
    }
}

// MARK: - Private Methods
private extension WebRTCService {
    
    // MARK: - Socket Listeners
    
    func setupSocketListeners() {
        guard let socket = socket else { return }
        
        socket.on(clientEvent: .connect) { [weak self] _, _ in
            print("✅ Socket connected")
            if let userId = self?.userId, let userName = self?.userName {
                socket.emit("register-user", [
                    "userId": userId,
                    "userName": userName
                ])
            }
            self?.notifyConnectionChange(true)
        }
        
        socket.on(clientEvent: .disconnect) { [weak self] _, _ in
            print("❌ Socket disconnected")
            self?.notifyConnectionChange(false)
        }
        
        socket.on("users-online") { [weak self] data, _ in
            guard let usersData = data.first as? [[String: Any]] else { return }
            let users = usersData.compactMap(CallParticipant.from(dictionary:))
            print("📢 Online users: \(users.count)")
            self?.notifyOnlineUsers(users)
        }
        
        socket.on("incoming-call") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any],
                  let callData = IncomingCallData.from(dictionary: dict) else { return }
            print("📞 Incoming call from: \(callData.callerName)")
            self?.notifyIncomingCall(callData)
        }
        
        socket.on("call-accepted") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any] else { return }
            let response = CallResponse.from(dictionary: dict)
            print("✅ Call accepted")
            self?.notifyCallAccepted(response)
        }
        
        socket.on("call-rejected") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any] else { return }
            let response = CallResponse.from(dictionary: dict)
            print("❌ Call rejected")
            self?.notifyCallRejected(response)
        }
        
        socket.on("signal") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any],
                  let signalData = SignalData.from(dictionary: dict) else { return }
            
            Task {
                await self?.handleSignal(signalData)
            }
        }
        
        socket.on("error") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any],
                  let message = dict["message"] as? String else { return }
            print("❌ Server error: \(message)")
            self?.notifyError(message)
        }
    }
    
    // MARK: - Peer Connection
    
    func createPeerConnection(participantId: String, isInitiator: Bool) async {
        print("🔗 Creating peer connection with \(participantId), initiator: \(isInitiator)")
        
        let config = RTCConfiguration()
        config.iceServers = iceServers.isEmpty ? 
            [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])] : 
            iceServers
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually
        
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue,
                kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueTrue
            ],
            optionalConstraints: nil
        )
        
        guard let pc = factory.peerConnection(with: config, 
                                            constraints: constraints, 
                                            delegate: self) else {
            print("❌ Failed to create peer connection")
            return
        }
        
        peerConnections[participantId] = pc
        
        // Add local stream
        if let localStream = localStream {
            for track in localStream.videoTracks {
                pc.add(track, streamIds: [localStream.streamId])
            }
            for track in localStream.audioTracks {
                pc.add(track, streamIds: [localStream.streamId])
            }
        }
        
        // Create offer if initiator
        if isInitiator {
            do {
                let offer = try await pc.offer(for: constraints)
                try await pc.setLocalDescription(offer)
                
                socket?.emit("signal", [
                    "callId": currentCallId ?? "",
                    "targetId": participantId,
                    "signal": [
                        "sdp": offer.sdp,
                        "type": offer.type.rawValue
                    ],
                    "type": "offer"
                ])
            } catch {
                print("Create offer error: \(error)")
                notifyError("Failed to create offer: \(error.localizedDescription)")
            }
        }
    }
    
    func handleSignal(_ data: SignalData) async {
        let fromId = data.fromId
        let signal = data.signal
        let type = data.type
        
        print("📡 Received signal from \(fromId): \(type)")
        
        var pc = peerConnections[fromId]
        
        // Create connection if doesn't exist
        if pc == nil {
            await createPeerConnection(participantId: fromId, isInitiator: false)
            pc = peerConnections[fromId]
        }
        
        guard let peerConnection = pc else {
            print("❌ Failed to get peer connection for \(fromId)")
            return
        }
        
        do {
            switch type {
            case .offer:
                guard let sdp = signal.sdp, let typeStr = signal.type,
                      let type = RTCSdpType(rawValue: typeStr) else {
                    throw WebRTCError.invalidSignal
                }
                
                let remoteSdp = RTCSessionDescription(type: type, sdp: sdp)
                try await peerConnection.setRemoteDescription(remoteSdp)
                
                let answer = try await peerConnection.answer(for: nil)
                try await peerConnection.setLocalDescription(answer)
                
                socket?.emit("signal", [
                    "callId": currentCallId ?? "",
                    "targetId": fromId,
                    "signal": [
                        "sdp": answer.sdp,
                        "type": answer.type.rawValue
                    ],
                    "type": "answer"
                ])
                
            case .answer:
                guard let sdp = signal.sdp, let typeStr = signal.type,
                      let type = RTCSdpType(rawValue: typeStr) else {
                    throw WebRTCError.invalidSignal
                }
                
                let remoteSdp = RTCSessionDescription(type: type, sdp: sdp)
                try await peerConnection.setRemoteDescription(remoteSdp)
                
            case .iceCandidate:
                guard let candidate = signal.candidate,
                      let sdpMid = signal.sdpMid,
                      let sdpMLineIndex = signal.sdpMLineIndex else {
                    throw WebRTCError.invalidSignal
                }
                
                let iceCandidate = RTCIceCandidate(
                    sdp: candidate,
                    sdpMLineIndex: Int32(sdpMLineIndex),
                    sdpMid: sdpMid
                )
                
                try await peerConnection.add(iceCandidate)
            }
        } catch {
            print("Handle signal error: \(error)")
            notifyError("Signal handling failed: \(error.localizedDescription)")
        }
    }
    
    func removePeerConnection(participantId: String) {
        peerConnections[participantId]?.close()
        peerConnections.removeValue(forKey: participantId)
        
        remoteStreams.removeValue(forKey: participantId)
        notifyRemoteStreamRemoved(participantId)
    }
    
    func cleanupPeerConnections() {
        peerConnections.values.forEach { $0.close() }
        peerConnections.removeAll()
        remoteStreams.removeAll()
        
        // Stop local stream
        localStream?.audioTracks.forEach { $0.isEnabled = false }
        localStream?.videoTracks.forEach { $0.isEnabled = false }
        localStream = nil
    }
    
    // MARK: - Notification Helpers
    
    func notifyConnectionChange(_ isConnected: Bool) {
        DispatchQueue.main.async {
            self.delegate?.onConnectionChange(isConnected)
            self.onConnectionChange?(isConnected)
        }
    }
    
    func notifyLocalStream(_ stream: RTCMediaStream) {
        DispatchQueue.main.async {
            self.delegate?.onLocalStream(stream)
            self.onLocalStream?(stream)
        }
    }
    
    func notifyRemoteStream(_ participantId: String, _ stream: RTCMediaStream) {
        DispatchQueue.main.async {
            self.delegate?.onRemoteStream(participantId, stream)
            self.onRemoteStream?(participantId, stream)
        }
    }
    
    func notifyRemoteStreamRemoved(_ participantId: String) {
        DispatchQueue.main.async {
            self.delegate?.onRemoteStreamRemoved(participantId)
            self.onRemoteStreamRemoved?(participantId)
        }
    }
    
    func notifyOnlineUsers(_ users: [CallParticipant]) {
        DispatchQueue.main.async {
            self.delegate?.onOnlineUsers(users)
            self.onOnlineUsers?(users)
        }
    }
    
    func notifyIncomingCall(_ data: IncomingCallData) {
        DispatchQueue.main.async {
            self.delegate?.onIncomingCall(data)
            self.onIncomingCall?(data)
        }
    }
    
    func notifyCallAccepted(_ data: CallResponse) {
        DispatchQueue.main.async {
            self.delegate?.onCallAccepted(data)
            self.onCallAccepted?(data)
        }
    }
    
    func notifyCallRejected(_ data: CallResponse) {
        DispatchQueue.main.async {
            self.delegate?.onCallRejected(data)
            self.onCallRejected?(data)
        }
    }
    
    func notifyError(_ message: String) {
        DispatchQueue.main.async {
            self.delegate?.onError(message)
            self.onError?(message)
        }
    }
}

// MARK: - RTCPeerConnectionDelegate
extension WebRTCService: RTCPeerConnectionDelegate {
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        guard let participantId = findParticipantId(for: peerConnection) else { return }
        
        print("📥 Received remote stream from \(participantId)")
        remoteStreams[participantId] = stream
        notifyRemoteStream(participantId, stream)
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        guard let participantId = findParticipantId(for: peerConnection) else { return }
        
        print("Removed remote stream from \(participantId)")
        remoteStreams.removeValue(forKey: participantId)
        notifyRemoteStreamRemoved(participantId)
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        guard let participantId = findParticipantId(for: peerConnection) else { return }
        
        socket?.emit("signal", [
            "callId": currentCallId ?? "",
            "targetId": participantId,
            "signal": [
                "candidate": candidate.sdp,
                "sdpMid": candidate.sdpMid ?? "",
                "sdpMLineIndex": candidate.sdpMLineIndex
            ],
            "type": "ice-candidate"
        ])
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        print("ICE connection state changed: \(newState.rawValue)")
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCSignalingState) {
        print("Signaling state changed: \(newState.rawValue)")
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        print("Peer connection state changed: \(newState.rawValue)")
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        print("ICE gathering state: \(newState.rawValue)")
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        // Not used in this implementation
    }
    
    public func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        // Trigger renegotiation if needed
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        print("Data channel opened")
    }
    
    private func findParticipantId(for peerConnection: RTCPeerConnection) -> String? {
        peerConnections.first { $0.value === peerConnection }?.key
    }
}