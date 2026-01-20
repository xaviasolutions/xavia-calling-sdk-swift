import Foundation
import WebRTC
import SocketIO

/// WebRTC Service - Complete implementation matching backend
/// Handles all WebRTC signaling, peer connections, and media streams
class WebRTCService {
    static let shared = WebRTCService()
    
    // MARK: - Properties
    private var socket: SocketIOClient?
    private var manager: SocketManager?
    
    private var peerConnections: [String: RTCPeerConnection] = [:] // participantId -> RTCPeerConnection
    private var localStream: RTCMediaStream?
    private var remoteStreams: [String: RTCMediaStream] = [:] // participantId -> MediaStream
    private var currentCallId: String?
    private var currentParticipantId: String?
    private var userId: String?
    private var userName: String?
    private var iceServers: [RTCIceServer]?
    private var baseUrl: String?
    
    // MARK: - Event Callbacks
    var onConnectionChange: ((Bool) -> Void)?
    var onLocalStream: ((RTCMediaStream) -> Void)?
    var onRemoteStream: ((String, RTCMediaStream) -> Void)?
    var onRemoteStreamRemoved: ((String) -> Void)?
    var onOnlineUsers: (([OnlineUser]) -> Void)?
    var onIncomingCall: ((IncomingCallData) -> Void)?
    var onCallAccepted: ((CallAcceptedData) -> Void)?
    var onCallRejected: ((CallRejectedData) -> Void)?
    var onParticipantJoined: ((ParticipantData) -> Void)?
    var onParticipantLeft: ((ParticipantLeftData) -> Void)?
    var onError: ((String) -> Void)?
    
    private let factory: RTCPeerConnectionFactory
    
    // MARK: - Initialization
    init() {
        RTCInitializeSSL()
        let encoderFactory = RTCDefaultVideoEncoderFactory()
        let decoderFactory = RTCDefaultVideoDecoderFactory()
        factory = RTCPeerConnectionFactory(encoderFactory: encoderFactory, decoderFactory: decoderFactory)
    }
    
    deinit {
        disconnect()
        RTCShutdownInternalTracer()
        RTCCleanupSSL()
    }
    
    // MARK: - Connection Management
    
    /// Initialize connection to backend
    func connect(serverUrl: String, userId: String, userName: String) async throws {
        self.baseUrl = serverUrl
        
        // Validate inputs
        if userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw WebRTCError.validationError("Username is required")
        }
        
        // If already connected with same user, don't reconnect
        if let socket = self.socket, socket.status == .connected, self.userId == userId {
            print("⚠️ Already connected, skipping reconnection")
            return
        }
        
        // Disconnect existing connection if different user
        if let socket = self.socket, self.userId != userId {
            print("🔄 Disconnecting previous connection")
            disconnect()
        }
        
        self.userId = userId
        self.userName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        print("🔌 Connecting to server: \(serverUrl)")
        
        guard let url = URL(string: serverUrl) else {
            throw WebRTCError.invalidURL
        }
        
        let manager = SocketManager(socketURL: url, config: [
            .log(false),
            .compress,
            .forceWebsockets(true),
            .reconnects(true),
            .reconnectAttempts(5),
            .reconnectWait(1000)
        ])
        
        self.manager = manager
        self.socket = manager.defaultSocket
        
        return try await withCheckedThrowingContinuation { continuation in
            self.socket?.on(clientEvent: .connect) { [weak self] data, ack in
                guard let self = self else { return }
                print("✅ Socket connected")
                
                // Register user
                self.socket?.emit("register-user", with: [
                    ["userId": userId, "userName": self.userName ?? ""]
                ])
                
                self.onConnectionChange?(true)
                continuation.resume()
            }
            
            self.socket?.on(clientEvent: .disconnect) { [weak self] data, ack in
                print("❌ Socket disconnected")
                self?.onConnectionChange?(false)
            }
            
            self.socket?.on(clientEvent: .error) { [weak self] data, ack in
                let error = data.first as? String ?? "Unknown connection error"
                print("Connection error: \(error)")
                self?.onError?("Connection failed: \(error)")
                continuation.resume(throwing: WebRTCError.connectionError(error))
            }
            
            // Setup event listeners
            setupSocketListeners()
            
            self.socket?.connect()
        }
    }
    
    // MARK: - Socket Event Listeners
    
    /// Setup all socket event listeners
    private func setupSocketListeners() {
        // Online users list
        socket?.on("users-online") { [weak self] data, ack in
            guard let self = self,
                  let jsonData = try? JSONSerialization.data(withJSONObject: data),
                  let users = try? JSONDecoder().decode([OnlineUser].self, from: jsonData) else { return }
            
            print("📢 Online users: \(users.count)")
            self.onOnlineUsers?(users)
        }
        
        // Incoming call invitation
        socket?.on("incoming-call") { [weak self] data, ack in
            guard let self = self,
                  let jsonData = try? JSONSerialization.data(withJSONObject: data),
                  let callData = try? JSONDecoder().decode(IncomingCallData.self, from: jsonData) else { return }
            
            print("📞 Incoming call from: \(callData.callerName)")
            self.onIncomingCall?(callData)
        }
        
        // Call accepted
        socket?.on("call-accepted") { [weak self] data, ack in
            guard let self = self,
                  let jsonData = try? JSONSerialization.data(withJSONObject: data),
                  let acceptedData = try? JSONDecoder().decode(CallAcceptedData.self, from: jsonData) else { return }
            
            print("✅ Call accepted by: \(acceptedData.acceptedByName)")
            self.onCallAccepted?(acceptedData)
        }
        
        // Call rejected
        socket?.on("call-rejected") { [weak self] data, ack in
            guard let self = self,
                  let jsonData = try? JSONSerialization.data(withJSONObject: data),
                  let rejectedData = try? JSONDecoder().decode(CallRejectedData.self, from: jsonData) else { return }
            
            print("❌ Call rejected by: \(rejectedData.rejectedByName)")
            self.onCallRejected?(rejectedData)
        }
        
        // Call joined successfully
        socket?.on("call-joined") { [weak self] data, ack in
            Task { [weak self] in
                guard let self = self,
                      let jsonData = try? JSONSerialization.data(withJSONObject: data),
                      let joinData = try? JSONDecoder().decode(CallJoinedData.self, from: jsonData) else { return }
                
                print("✅ Joined call: \(joinData.callId)")
                print("Other participants: \(joinData.participants)")
                
                // Convert ICE servers
                self.iceServers = joinData.iceServers?.map { server in
                    if let urls = server.urls as? [String] {
                        return RTCIceServer(urlStrings: urls)
                    }
                    return RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])
                }
                
                // Create peer connections for existing participants
                for participant in joinData.participants {
                    try? await self.createPeerConnection(participantId: participant.id, isInitiator: true)
                }
            }
        }
        
        // New participant joined
        socket?.on("participant-joined") { [weak self] data, ack in
            Task { [weak self] in
                guard let self = self,
                      let jsonData = try? JSONSerialization.data(withJSONObject: data),
                      let participantData = try? JSONDecoder().decode(ParticipantData.self, from: jsonData) else { return }
                
                print("👤 Participant joined: \(participantData.userName)")
                
                if participantData.participantId != self.currentParticipantId {
                    try? await self.createPeerConnection(participantId: participantData.participantId, isInitiator: false)
                }
                
                self.onParticipantJoined?(participantData)
            }
        }
        
        // Participant left
        socket?.on("participant-left") { [weak self] data, ack in
            guard let self = self,
                  let jsonData = try? JSONSerialization.data(withJSONObject: data),
                  let leftData = try? JSONDecoder().decode(ParticipantLeftData.self, from: jsonData) else { return }
            
            print("👋 Participant left: \(leftData.participantId)")
            self.removePeerConnection(participantId: leftData.participantId)
            self.onParticipantLeft?(leftData)
        }
        
        // WebRTC signaling
        socket?.on("signal") { [weak self] data, ack in
            Task { [weak self] in
                guard let self = self,
                      let jsonData = try? JSONSerialization.data(withJSONObject: data),
                      let signalData = try? JSONDecoder().decode(SignalData.self, from: jsonData) else { return }
                
                await self.handleSignal(data: signalData)
            }
        }
        
        // Error handling
        socket?.on("error") { [weak self] data, ack in
            guard let self = self,
                  let jsonData = try? JSONSerialization.data(withJSONObject: data),
                  let errorData = try? JSONDecoder().decode(ErrorData.self, from: jsonData) else { return }
            
            print("❌ Server error: \(errorData.message)")
            self.onError?(errorData.message)
        }
    }
    
    // MARK: - Call Management
    
    /// Create a new call
    func createCall(callType: String = "video", isGroup: Bool = false, maxParticipants: Int = 1000) async throws -> CreateCallResponse {
        guard let serverUrl = baseUrl else {
            throw WebRTCError.invalidURL
        }
        
        let url = URL(string: "\(serverUrl)/api/calls")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = CreateCallRequest(
            callType: callType,
            isGroup: isGroup,
            maxParticipants: maxParticipants
        )
        
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(CreateCallResponse.self, from: data)
        
        if !response.success {
            throw WebRTCError.apiError(response.error ?? "Failed to create call")
        }
        
        print("✅ Call created: \(response.callId)")
        
        // Convert ICE servers
        self.iceServers = response.config?.iceServers?.map { server in
            if let urls = server.urls as? [String] {
                return RTCIceServer(urlStrings: urls)
            }
            return RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])
        }
        
        return response
    }
    
    /// Join an existing call
    func joinCall(callId: String) async throws -> JoinCallResponse {
        guard let serverUrl = baseUrl,
              let userId = userId,
              let userName = userName else {
            throw WebRTCError.notConnected
        }
        
        print("Server URL: \(serverUrl)")
        let joinUrl = URL(string: "\(serverUrl)/api/calls/\(callId)/join")!
        print("Join URL: \(joinUrl)")
        
        var request = URLRequest(url: joinUrl)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = JoinCallRequest(
            userName: userName,
            userId: userId
        )
        
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(JoinCallResponse.self, from: data)
        
        if !response.success {
            throw WebRTCError.apiError(response.error ?? "Failed to join call")
        }
        
        print("✅ Joined call via API: \(response.callId)")
        
        self.currentCallId = response.callId
        self.currentParticipantId = response.participantId
        
        // Convert ICE servers
        self.iceServers = response.config?.iceServers?.map { server in
            if let urls = server.urls as? [String] {
                return RTCIceServer(urlStrings: urls)
            }
            return RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])
        }
        
        // Get local media
        try await getLocalMedia()
        
        // Join via socket
        socket?.emit("join-call", with: [[
            "callId": response.callId,
            "participantId": response.participantId,
            "userName": userName
        ]])
        
        return response
    }
    
    // MARK: - Media Management
    
    /// Get local media stream
    func getLocalMedia(constraints: [String: Any]? = nil) async throws -> RTCMediaStream {
        let defaultConstraints: [String: Any] = [
            "video": [
                "width": ["min": 640, "ideal": 1280, "max": 1920],
                "height": ["min": 480, "ideal": 720, "max": 1080],
                "frameRate": ["ideal": 30, "max": 60]
            ],
            "audio": [
                "echoCancellation": true,
                "noiseSuppression": true,
                "autoGainControl": true
            ]
        ]
        
        let finalConstraints = constraints ?? defaultConstraints
        
        print("🎥 Getting local media...")
        
        let stream = factory.mediaStream(withStreamId: "localStream")
        
        // Add audio track
        let audioConstraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: nil
        )
        let audioSource = factory.audioSource(with: audioConstraints)
        let audioTrack = factory.audioTrack(with: audioSource, trackId: "audio0")
        stream.addAudioTrack(audioTrack)
        
        // Add video track
        if let videoConstraints = finalConstraints["video"] as? [String: Any] {
            let videoSource = factory.videoSource()
            let videoTrack = factory.videoTrack(with: videoSource, trackId: "video0")
            stream.addVideoTrack(videoTrack)
            
            // Start video capture (simplified - in real app you'd use AVCaptureSession)
            // This is a placeholder - you'd implement actual camera capture here
        }
        
        self.localStream = stream
        print("✅ Local media obtained")
        
        self.onLocalStream?(stream)
        return stream
    }
    
    // MARK: - Peer Connection Management
    
    /// Create peer connection
    func createPeerConnection(participantId: String, isInitiator: Bool) async throws -> RTCPeerConnection {
        print("🔗 Creating peer connection with \(participantId), initiator: \(isInitiator)")
        
        let config = RTCConfiguration()
        config.iceServers = self.iceServers ?? [
            RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])
        ]
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually
        
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "true",
                "OfferToReceiveVideo": "true"
            ],
            optionalConstraints: nil
        )
        
        let pc = factory.peerConnection(with: config, constraints: constraints, delegate: nil)
        
        peerConnections[participantId] = pc
        
        // Add local stream tracks
        if let localStream = localStream {
            for track in localStream.audioTracks {
                pc.add(track, streamIds: [localStream.streamId])
            }
            for track in localStream.videoTracks {
                pc.add(track, streamIds: [localStream.streamId])
            }
            print("➕ Added local tracks")
        }
        
        // Set delegate for events
        pc.delegate = self
        
        // If initiator, create and send offer
        if isInitiator {
            let offer = try await pc.offer(for: constraints)
            try await pc.setLocalDescription(offer)
            
            print("📤 Sending offer to \(participantId)")
            socket?.emit("signal", with: [[
                "callId": currentCallId as Any,
                "targetId": participantId,
                "signal": ["sdp": offer.sdp, "type": offer.type.stringValue],
                "type": "offer"
            ]])
        }
        
        return pc
    }
    
    /// Handle incoming signals
    private func handleSignal(data: SignalData) async {
        let fromId = data.fromId
        let signal = data.signal
        let type = data.type
        
        print("📡 Received signal from \(fromId): \(type)")
        
        var pc = peerConnections[fromId]
        
        // Create peer connection if doesn't exist
        if pc == nil {
            pc = try? await createPeerConnection(participantId: fromId, isInitiator: false)
        }
        
        guard let peerConnection = pc else { return }
        
        do {
            if type == "offer" {
                let remoteSdp = RTCSessionDescription(type: .offer, sdp: signal.sdp)
                try await peerConnection.setRemoteDescription(remoteSdp)
                
                let answer = try await peerConnection.answer(for: nil)
                try await peerConnection.setLocalDescription(answer)
                
                print("📤 Sending answer to \(fromId)")
                socket?.emit("signal", with: [[
                    "callId": currentCallId as Any,
                    "targetId": fromId,
                    "signal": ["sdp": answer.sdp, "type": answer.type.stringValue],
                    "type": "answer"
                ]])
            } else if type == "answer" {
                let remoteSdp = RTCSessionDescription(type: .answer, sdp: signal.sdp)
                try await peerConnection.setRemoteDescription(remoteSdp)
            } else if type == "ice-candidate" {
                if let candidate = signal.candidate {
                    let iceCandidate = RTCIceCandidate(
                        sdp: candidate,
                        sdpMLineIndex: Int32(signal.sdpMLineIndex ?? 0),
                        sdpMid: signal.sdpMid
                    )
                    try await peerConnection.add(iceCandidate)
                }
            }
        } catch {
            print("Handle signal error: \(error)")
        }
    }
    
    /// Remove peer connection
    func removePeerConnection(participantId: String) {
        if let pc = peerConnections[participantId] {
            pc.close()
            peerConnections.removeValue(forKey: participantId)
        }
        
        if remoteStreams.removeValue(forKey: participantId) != nil {
            onRemoteStreamRemoved?(participantId)
        }
    }
    
    // MARK: - Call Actions
    
    /// Send call invitation
    func sendCallInvitation(targetUserId: String, callId: String, callType: String) async throws -> CallInvitationResponse {
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
                if let responseData = data.first as? [String: Any],
                   let jsonData = try? JSONSerialization.data(withJSONObject: responseData),
                   let response = try? JSONDecoder().decode(CallInvitationResponse.self, from: jsonData) {
                    
                    if response.success {
                        continuation.resume(returning: response)
                    } else {
                        continuation.resume(throwing: WebRTCError.apiError(response.error ?? "Unknown error"))
                    }
                } else {
                    continuation.resume(throwing: WebRTCError.invalidResponse)
                }
            }
        }
    }
    
    /// Accept incoming call
    func acceptCall(callId: String, callerId: String) {
        socket?.emit("accept-call", with: [[
            "callId": callId,
            "callerId": callerId
        ]])
    }
    
    /// Reject incoming call
    func rejectCall(callId: String, callerId: String) {
        socket?.emit("reject-call", with: [[
            "callId": callId,
            "callerId": callerId
        ]])
    }
    
    /// Leave current call
    func leaveCall() {
        guard let callId = currentCallId else { return }
        
        print("👋 Leaving call: \(callId)")
        
        socket?.emit("leave-call", with: [[
            "callId": callId,
            "reason": "left"
        ]])
        
        // Close all peer connections
        for (_, pc) in peerConnections {
            pc.close()
        }
        peerConnections.removeAll()
        remoteStreams.removeAll()
        
        // Stop local stream
        localStream = nil
        
        currentCallId = nil
        currentParticipantId = nil
    }
    
    /// Toggle audio
    func toggleAudio(_ enabled: Bool) {
        localStream?.audioTracks.forEach { $0.isEnabled = enabled }
        print("🎤 Audio: \(enabled ? "enabled" : "disabled")")
    }
    
    /// Toggle video
    func toggleVideo(_ enabled: Bool) {
        localStream?.videoTracks.forEach { $0.isEnabled = enabled }
        print("📹 Video: \(enabled ? "enabled" : "disabled")")
    }
    
    /// Disconnect from server
    func disconnect() {
        leaveCall()
        socket?.disconnect()
        socket = nil
        manager = nil
    }
}

// MARK: - RTCPeerConnectionDelegate
extension WebRTCService: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        print("Signaling state changed: \(stateChanged)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        guard let participantId = peerConnections.first(where: { $0.value == peerConnection })?.key else { return }
        
        print("📥 Received remote track from \(participantId)")
        remoteStreams[participantId] = stream
        onRemoteStream?(participantId, stream)
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        guard let participantId = peerConnections.first(where: { $0.value == peerConnection })?.key else { return }
        removePeerConnection(participantId: participantId)
    }
    
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        print("Should negotiate")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        print("ICE connection state changed: \(newState)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        print("ICE gathering state changed: \(newState)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        guard let participantId = peerConnections.first(where: { $0.value == peerConnection })?.key,
              let callId = currentCallId else { return }
        
        print("📡 Sending ICE candidate to \(participantId)")
        socket?.emit("signal", with: [[
            "callId": callId,
            "targetId": participantId,
            "signal": [
                "candidate": candidate.sdp,
                "sdpMid": candidate.sdpMid,
                "sdpMLineIndex": candidate.sdpMLineIndex
            ],
            "type": "ice-candidate"
        ]])
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        print("Removed ICE candidates")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        print("Data channel opened")
    }
}

// MARK: - Data Models
struct OnlineUser: Codable {
    let userId: String
    let userName: String
}

struct IncomingCallData: Codable {
    let callerName: String
    let callerId: String
    let callId: String
    let callType: String
}

struct CallAcceptedData: Codable {
    let acceptedByName: String
    let callId: String
}

struct CallRejectedData: Codable {
    let rejectedByName: String
    let callId: String
}

struct CallJoinedData: Codable {
    let callId: String
    let participants: [ParticipantData]
    let iceServers: [ICEServer]?
}

struct ParticipantData: Codable {
    let id: String
    let participantId: String
    let userName: String
}

struct ParticipantLeftData: Codable {
    let participantId: String
}

struct SignalData: Codable {
    let fromId: String
    let signal: SignalInfo
    let type: String
}

struct SignalInfo: Codable {
    let sdp: String?
    let type: String?
    let candidate: String?
    let sdpMid: String?
    let sdpMLineIndex: Int?
}

struct ErrorData: Codable {
    let message: String
}

struct CreateCallRequest: Codable {
    let callType: String
    let isGroup: Bool
    let maxParticipants: Int
}

struct CreateCallResponse: Codable {
    let success: Bool
    let callId: String
    let error: String?
    let config: WebRTCConfig?
}

struct JoinCallRequest: Codable {
    let userName: String
    let userId: String
}

struct JoinCallResponse: Codable {
    let success: Bool
    let callId: String
    let participantId: String
    let error: String?
    let config: WebRTCConfig?
}

struct WebRTCConfig: Codable {
    let iceServers: [ICEServer]?
}

struct ICEServer: Codable {
    let urls: AnyCodableValue?
}

struct CallInvitationResponse: Codable {
    let success: Bool
    let error: String?
}

// MARK: - Error Types
enum WebRTCError: Error {
    case validationError(String)
    case connectionError(String)
    case apiError(String)
    case invalidURL
    case notConnected
    case invalidResponse
    
    var localizedDescription: String {
        switch self {
        case .validationError(let message):
            return message
        case .connectionError(let message):
            return "Connection error: \(message)"
        case .apiError(let message):
            return "API error: \(message)"
        case .invalidURL:
            return "Invalid server URL"
        case .notConnected:
            return "Not connected to server"
        case .invalidResponse:
            return "Invalid server response"
        }
    }
}

// MARK: - Helper Types
struct AnyCodableValue: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let stringArray = try? container.decode([String].self) {
            value = stringArray
        } else if let stringDict = try? container.decode([String: String].self) {
            value = stringDict
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let array = try? container.decode([AnyCodableValue].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodableValue].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let stringArray as [String]:
            try container.encode(stringArray)
        case let stringDict as [String: String]:
            try container.encode(stringDict)
        case let string as String:
            try container.encode(string)
        case let int as Int:
            try container.encode(int)
        case let bool as Bool:
            try container.encode(bool)
        case let double as Double:
            try container.encode(double)
        case let array as [Any]:
            try container.encode(array.map(AnyCodableValue.init))
        case let dict as [String: Any]:
            try container.encode(dict.mapValues(AnyCodableValue.init))
        default:
            try container.encodeNil()
        }
    }
}