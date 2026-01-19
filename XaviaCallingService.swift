import Foundation
import WebRTC
import SocketIO

/// XaviaCallingService - Complete iOS native WebRTC implementation
/// Singleton service for managing WebRTC peer connections and signaling
public class XaviaCallingService: NSObject {
    // MARK: - Singleton
    public static let shared = XaviaCallingService()
    
    // MARK: - Properties
    private var manager: SocketManager?
    private var socket: SocketIOClient?
    
    private var peerConnections: [String: RTCPeerConnection] = [:] // participantId -> RTCPeerConnection
    private var localStream: RTCMediaStream?
    private var remoteStreams: [String: RTCMediaStream] = [:] // participantId -> MediaStream
    
    private var currentCallId: String?
    private var currentParticipantId: String?
    private var userId: String?
    private var userName: String?
    private var iceServers: [RTCIceServer] = []
    private var baseUrl: String?
    
    // WebRTC factory
    private let peerConnectionFactory: RTCPeerConnectionFactory
    
    // Delegate
    public weak var delegate: XaviaCallingDelegate?
    
    // Audio/Video constraints
    private let audioConstraints: RTCMediaConstraints
    private let videoConstraints: RTCMediaConstraints
    
    // MARK: - Initialization
    private override init() {
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        self.peerConnectionFactory = RTCPeerConnectionFactory(
            encoderFactory: videoEncoderFactory,
            decoderFactory: videoDecoderFactory
        )
        
        // Setup audio constraints
        self.audioConstraints = RTCMediaConstraints(
            mandatoryConstraints: [
                kRTCMediaConstraintsEchoCancellation: kRTCMediaConstraintsValueTrue,
                kRTCMediaConstraintsNoiseSuppression: kRTCMediaConstraintsValueTrue,
                kRTCMediaConstraintsAutoGainControl: kRTCMediaConstraintsValueTrue
            ],
            optionalConstraints: nil
        )
        
        // Setup video constraints
        self.videoConstraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: nil
        )
        
        super.init()
    }
    
    // MARK: - Connection Management
    
    /// Initialize connection to backend
    public func connect(serverUrl: String, userId: String, userName: String) async throws {
        guard !userName.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw XaviaCallingError.invalidUsername
        }
        
        self.baseUrl = serverUrl
        
        // If already connected with same user, don't reconnect
        if let socket = socket, socket.status == .connected && self.userId == userId {
            print("⚠️ Already connected, skipping reconnection")
            return
        }
        
        // Disconnect existing connection if different user
        if socket != nil && self.userId != userId {
            print("🔄 Disconnecting previous connection")
            disconnect()
        }
        
        self.userId = userId
        self.userName = userName.trimmingCharacters(in: .whitespaces)
        
        print("🔌 Connecting to server: \(serverUrl)")
        
        return try await withCheckedThrowingContinuation { continuation in
            let socketURL = URL(string: serverUrl)!
            self.manager = SocketManager(socketURL: socketURL, config: [
                .log(false),
                .compress,
                .reconnects(true),
                .reconnectAttempts(5),
                .reconnectWait(1),
                .connectParams([:])
            ])
            
            guard let socket = self.manager?.defaultSocket else {
                continuation.resume(throwing: XaviaCallingError.socketInitializationFailed)
                return
            }
            
            self.socket = socket
            
            // Setup event listeners before connecting
            self.setupSocketListeners()
            
            socket.on("connect") { [weak self] _, ack in
                print("✅ Socket connected: \(socket.socketID ?? "unknown")")
                
                // Register user
                socket.emit("register-user", [
                    "userId": userId,
                    "userName": self?.userName ?? ""
                ])
                
                self?.delegate?.onConnectionChange(true)
                continuation.resume()
            }
            
            socket.on("connect_error") { [weak self] data, ack in
                let errorMessage = (data?.first as? String) ?? "Connection failed"
                print("❌ Connection error: \(errorMessage)")
                self?.delegate?.onError("Connection failed: \(errorMessage)")
                continuation.resume(throwing: XaviaCallingError.connectionFailed(errorMessage))
            }
            
            socket.connect()
        }
    }
    
    /// Setup all socket event listeners
    private func setupSocketListeners() {
        guard let socket = socket else { return }
        
        // Online users list
        socket.on("users-online") { [weak self] data, ack in
            if let users = data?.first as? [[String: Any]] {
                print("📢 Online users: \(users.count)")
                self?.delegate?.onOnlineUsers(users)
            }
        }
        
        // Incoming call invitation
        socket.on("incoming-call") { [weak self] data, ack in
            if let callData = data?.first as? [String: Any],
               let callerName = callData["callerName"] as? String {
                print("📞 Incoming call from: \(callerName)")
                self?.delegate?.onIncomingCall(callData)
            }
        }
        
        // Call accepted
        socket.on("call-accepted") { [weak self] data, ack in
            if let callData = data?.first as? [String: Any],
               let acceptedByName = callData["acceptedByName"] as? String {
                print("✅ Call accepted by: \(acceptedByName)")
                self?.delegate?.onCallAccepted(callData)
            }
        }
        
        // Call rejected
        socket.on("call-rejected") { [weak self] data, ack in
            if let callData = data?.first as? [String: Any],
               let rejectedByName = callData["rejectedByName"] as? String {
                print("❌ Call rejected by: \(rejectedByName)")
                self?.delegate?.onCallRejected(callData)
            }
        }
        
        // Call joined successfully
        socket.on("call-joined") { [weak self] data, ack in
            Task {
                await self?.handleCallJoined(data: data)
            }
        }
        
        // New participant joined
        socket.on("participant-joined") { [weak self] data, ack in
            Task {
                await self?.handleParticipantJoined(data: data)
            }
        }
        
        // Participant left
        socket.on("participant-left") { [weak self] data, ack in
            if let callData = data?.first as? [String: Any],
               let participantId = callData["participantId"] as? String {
                print("👋 Participant left: \(participantId)")
                self?.removePeerConnection(participantId: participantId)
                self?.delegate?.onParticipantLeft(callData)
            }
        }
        
        // WebRTC signaling
        socket.on("signal") { [weak self] data, ack in
            Task {
                await self?.handleSignal(data: data)
            }
        }
        
        // Error handling
        socket.on("error") { [weak self] data, ack in
            if let errorData = data?.first as? [String: Any],
               let message = errorData["message"] as? String {
                print("❌ Server error: \(message)")
                self?.delegate?.onError(message)
            }
        }
        
        socket.on("disconnect") { [weak self] _, _ in
            print("❌ Socket disconnected")
            self?.delegate?.onConnectionChange(false)
        }
    }
    
    // MARK: - Call Management
    
    /// Create a new call via REST API
    public func createCall(callType: String = "video", isGroup: Bool = false, maxParticipants: Int = 1000) async throws -> [String: Any] {
        guard let baseUrl = baseUrl else {
            throw XaviaCallingError.notConnected
        }
        
        let url = URL(string: "\(baseUrl)/api/calls")!
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
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw XaviaCallingError.apiError("Failed to create call")
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        
        guard let success = json["success"] as? Bool, success else {
            let error = json["error"] as? String ?? "Unknown error"
            throw XaviaCallingError.apiError(error)
        }
        
        if let config = json["config"] as? [String: Any],
           let iceServersArray = config["iceServers"] as? [[String: Any]] {
            self.iceServers = parseIceServers(iceServersArray)
        }
        
        print("✅ Call created: \(json["callId"] ?? "")")
        return json
    }
    
    /// Join an existing call
    public func joinCall(callId: String) async throws -> [String: Any] {
        guard let baseUrl = baseUrl else {
            throw XaviaCallingError.notConnected
        }
        guard let userId = userId, let userName = userName else {
            throw XaviaCallingError.notInitialized
        }
        
        let url = URL(string: "\(baseUrl)/api/calls/\(callId)/join")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "userName": userName,
            "userId": userId
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw XaviaCallingError.apiError("Failed to join call")
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        
        guard let success = json["success"] as? Bool, success else {
            let error = json["error"] as? String ?? "Unknown error"
            throw XaviaCallingError.apiError(error)
        }
        
        if let config = json["config"] as? [String: Any],
           let iceServersArray = config["iceServers"] as? [[String: Any]] {
            self.iceServers = parseIceServers(iceServersArray)
        }
        
        self.currentCallId = json["callId"] as? String
        self.currentParticipantId = json["participantId"] as? String
        
        // Get local media
        try await getLocalMedia()
        
        // Join via socket
        if let socket = socket, socket.status == .connected {
            socket.emit("join-call", [
                "callId": currentCallId ?? "",
                "participantId": currentParticipantId ?? "",
                "userName": userName
            ])
        }
        
        print("✅ Joined call via API: \(currentCallId ?? "")")
        return json
    }
    
    // MARK: - Media Management
    
    /// Get local media stream
    public func getLocalMedia(constraints: [String: Any]? = nil) async throws -> RTCMediaStream {
        print("🎥 Getting local media...")
        
        let audioTrack = peerConnectionFactory.audioTrack(withTrackId: UUID().uuidString)
        let videoTrack = peerConnectionFactory.videoTrack(
            withTrackId: UUID().uuidString,
            constraints: videoConstraints
        )
        
        let stream = peerConnectionFactory.mediaStream(withStreamId: UUID().uuidString)
        stream.addAudioTrack(audioTrack)
        stream.addVideoTrack(videoTrack)
        
        self.localStream = stream
        
        print("✅ Local media obtained")
        delegate?.onLocalStream(stream)
        
        return stream
    }
    
    // MARK: - Peer Connection Management
    
    /// Create peer connection with a participant
    public func createPeerConnection(participantId: String, isInitiator: Bool) async throws -> RTCPeerConnection {
        print("🔗 Creating peer connection with \(participantId), initiator: \(isInitiator)")
        
        let config = RTCConfiguration()
        config.iceServers = iceServers.isEmpty ? [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])] : iceServers
        config.sdpSemantics = .unifiedPlan
        
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: nil
        )
        
        guard let pc = peerConnectionFactory.peerConnection(with: config, constraints: constraints, delegate: self) else {
            throw XaviaCallingError.peerConnectionCreationFailed
        }
        
        peerConnections[participantId] = pc
        
        // Add local stream tracks
        if let localStream = localStream {
            for track in localStream.audioTracks {
                let rtcSender = pc.add(track, streamIds: [localStream.streamId])
            }
            for track in localStream.videoTracks {
                let rtcSender = pc.add(track, streamIds: [localStream.streamId])
            }
            print("➕ Added local tracks to peer connection")
        }
        
        // Store current participant for ICE candidate handling
        let userData: [String: String] = ["participantId": participantId]
        pc.userObject = userData as NSObject
        
        // If initiator, create and send offer
        if isInitiator {
            let offer = try await pc.offer(for: RTCMediaConstraints(
                mandatoryConstraints: [
                    kRTCMediaConstraintsMandatoryOfferToReceiveAudio: kRTCMediaConstraintsValueTrue,
                    kRTCMediaConstraintsMandatoryOfferToReceiveVideo: kRTCMediaConstraintsValueTrue
                ],
                optionalConstraints: nil
            ))
            
            try await pc.setLocalDescription(offer)
            
            print("📤 Sending offer to \(participantId)")
            socket?.emit("signal", [
                "callId": currentCallId ?? "",
                "targetId": participantId,
                "signal": [
                    "sdp": offer.sdp,
                    "type": offer.type.rawValue
                ],
                "type": "offer"
            ])
        }
        
        return pc
    }
    
    /// Handle incoming signals
    private func handleSignal(data: [Any]?) async {
        guard let signalData = data?.first as? [String: Any],
              let fromId = signalData["fromId"] as? String,
              let signal = signalData["signal"] as? [String: Any],
              let type = signalData["type"] as? String else {
            return
        }
        
        print("📡 Received signal from \(fromId): \(type)")
        
        var pc = peerConnections[fromId]
        
        // Create peer connection if doesn't exist
        if pc == nil {
            do {
                pc = try await createPeerConnection(participantId: fromId, isInitiator: false)
            } catch {
                print("Failed to create peer connection: \(error)")
                return
            }
        }
        
        guard let pc = pc else { return }
        
        do {
            if type == "offer" {
                guard let sdp = signal["sdp"] as? String else { return }
                
                let offer = RTCSessionDescription(type: .offer, sdp: sdp)
                try await pc.setRemoteDescription(offer)
                
                let answer = try await pc.answer(for: RTCMediaConstraints(
                    mandatoryConstraints: [
                        kRTCMediaConstraintsMandatoryOfferToReceiveAudio: kRTCMediaConstraintsValueTrue,
                        kRTCMediaConstraintsMandatoryOfferToReceiveVideo: kRTCMediaConstraintsValueTrue
                    ],
                    optionalConstraints: nil
                ))
                
                try await pc.setLocalDescription(answer)
                
                print("📤 Sending answer to \(fromId)")
                socket?.emit("signal", [
                    "callId": currentCallId ?? "",
                    "targetId": fromId,
                    "signal": [
                        "sdp": answer.sdp,
                        "type": answer.type.rawValue
                    ],
                    "type": "answer"
                ])
            } else if type == "answer" {
                guard let sdp = signal["sdp"] as? String else { return }
                
                let answer = RTCSessionDescription(type: .answer, sdp: sdp)
                try await pc.setRemoteDescription(answer)
            } else if type == "ice-candidate" {
                guard let candidate = signal["candidate"] as? String,
                      let sdpMid = signal["sdpMid"] as? String,
                      let sdpMLineIndex = signal["sdpMLineIndex"] as? NSNumber else {
                    return
                }
                
                let iceCandidate = RTCIceCandidate(
                    sdp: candidate,
                    sdpMLineIndex: sdpMLineIndex.int32Value,
                    sdpMid: sdpMid
                )
                try await pc.add(iceCandidate)
            }
        } catch {
            print("Handle signal error: \(error)")
        }
    }
    
    /// Remove peer connection
    private func removePeerConnection(participantId: String) {
        if let pc = peerConnections.removeValue(forKey: participantId) {
            pc.close()
        }
        
        if let stream = remoteStreams.removeValue(forKey: participantId) {
            delegate?.onRemoteStreamRemoved(participantId: participantId)
        }
    }
    
    // MARK: - Call Control
    
    /// Send call invitation
    public func sendCallInvitation(targetUserId: String, callId: String, callType: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            guard let socket = socket, socket.status == .connected else {
                continuation.resume(throwing: XaviaCallingError.notConnected)
                return
            }
            
            socket.emitWithAck("send-call-invitation", [
                "targetUserId": targetUserId,
                "callId": callId,
                "callType": callType,
                "callerId": userId ?? "",
                "callerName": userName ?? ""
            ]).timingOut(after: 10) { [weak self] data in
                if let response = data.first as? [String: Any],
                   let success = response["success"] as? Bool, success {
                    continuation.resume()
                } else {
                    let error = (data.first as? [String: Any])?["error"] as? String ?? "Failed to send invitation"
                    continuation.resume(throwing: XaviaCallingError.apiError(error))
                }
            }
        }
    }
    
    /// Accept incoming call
    public func acceptCall(callId: String, callerId: String) {
        guard let socket = socket, socket.status == .connected else {
            delegate?.onError("Socket not connected")
            return
        }
        
        socket.emit("accept-call", [
            "callId": callId,
            "callerId": callerId
        ])
    }
    
    /// Reject incoming call
    public func rejectCall(callId: String, callerId: String) {
        guard let socket = socket, socket.status == .connected else {
            delegate?.onError("Socket not connected")
            return
        }
        
        socket.emit("reject-call", [
            "callId": callId,
            "callerId": callerId
        ])
    }
    
    /// Leave current call
    public func leaveCall() {
        guard let currentCallId = currentCallId else { return }
        
        print("👋 Leaving call: \(currentCallId)")
        
        socket?.emit("leave-call", [
            "callId": currentCallId,
            "reason": "left"
        ])
        
        // Close all peer connections
        for (_, pc) in peerConnections {
            pc.close()
        }
        peerConnections.removeAll()
        remoteStreams.removeAll()
        
        // Stop local stream
        if let localStream = localStream {
            for track in localStream.audioTracks {
                track.isEnabled = false
            }
            for track in localStream.videoTracks {
                track.isEnabled = false
            }
            self.localStream = nil
        }
        
        self.currentCallId = nil
        self.currentParticipantId = nil
    }
    
    // MARK: - Audio/Video Control
    
    /// Toggle audio enabled/disabled
    public func toggleAudio(enabled: Bool) {
        guard let localStream = localStream else { return }
        
        for track in localStream.audioTracks {
            track.isEnabled = enabled
        }
        
        print("🎤 Audio: \(enabled ? "enabled" : "disabled")")
    }
    
    /// Toggle video enabled/disabled
    public func toggleVideo(enabled: Bool) {
        guard let localStream = localStream else { return }
        
        for track in localStream.videoTracks {
            track.isEnabled = enabled
        }
        
        print("📹 Video: \(enabled ? "enabled" : "disabled")")
    }
    
    // MARK: - Connection Lifecycle
    
    /// Disconnect from server
    public func disconnect() {
        leaveCall()
        socket?.disconnect()
        socket = nil
        manager = nil
    }
    
    // MARK: - Private Helpers
    
    /// Handle call-joined event
    private func handleCallJoined(data: [Any]?) async {
        guard let callData = data?.first as? [String: Any] else { return }
        
        print("✅ Joined call: \(callData["callId"] ?? "")")
        
        if let participants = callData["participants"] as? [[String: Any]] {
            print("Other participants: \(participants.count)")
            
            for participant in participants {
                if let participantId = participant["id"] as? String {
                    do {
                        _ = try await createPeerConnection(participantId: participantId, isInitiator: true)
                    } catch {
                        print("Failed to create peer connection for \(participantId): \(error)")
                    }
                }
            }
        }
    }
    
    /// Handle participant-joined event
    private func handleParticipantJoined(data: [Any]?) async {
        guard let participantData = data?.first as? [String: Any] else { return }
        
        if let participantId = participantData["participantId"] as? String,
           let userName = participantData["userName"] as? String {
            print("👤 Participant joined: \(userName)")
            
            if participantId != currentParticipantId {
                do {
                    _ = try await createPeerConnection(participantId: participantId, isInitiator: false)
                } catch {
                    print("Failed to create peer connection: \(error)")
                }
            }
        }
        
        delegate?.onParticipantJoined(participantData)
    }
    
    /// Parse ICE servers from API response
    private func parseIceServers(_ servers: [[String: Any]]) -> [RTCIceServer] {
        return servers.compactMap { serverData in
            guard let urls = serverData["urls"] as? [String] else { return nil }
            
            let username = serverData["username"] as? String
            let credential = serverData["credential"] as? String
            
            return RTCIceServer(
                urlStrings: urls,
                username: username,
                credential: credential
            )
        }
    }
}

// MARK: - RTCPeerConnectionDelegate

extension XaviaCallingService: RTCPeerConnectionDelegate {
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        guard let userData = peerConnection.userObject as? [String: String],
              let participantId = userData["participantId"] else {
            return
        }
        
        print("📥 Received remote track from \(participantId)")
        remoteStreams[participantId] = stream
        delegate?.onRemoteStream(participantId: participantId, stream: stream)
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        guard let userData = peerConnection.userObject as? [String: String],
              let participantId = userData["participantId"] else {
            return
        }
        
        remoteStreams.removeValue(forKey: participantId)
        delegate?.onRemoteStreamRemoved(participantId: participantId)
    }
    
    public func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        guard let userData = peerConnection.userObject as? [String: String],
              let participantId = userData["participantId"] else {
            return
        }
        
        print("ICE connection state with \(participantId): \(newState.description)")
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        guard let userData = peerConnection.userObject as? [String: String],
              let participantId = userData["participantId"] else {
            return
        }
        
        print("📡 Sending ICE candidate to \(participantId)")
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
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}

// MARK: - RTCIceConnectionState Extension

extension RTCIceConnectionState {
    var description: String {
        switch self {
        case .new: return "new"
        case .checking: return "checking"
        case .connected: return "connected"
        case .completed: return "completed"
        case .failed: return "failed"
        case .disconnected: return "disconnected"
        case .closed: return "closed"
        case .count: return "count"
        @unknown default: return "unknown"
        }
    }
}

// MARK: - Error Enum

public enum XaviaCallingError: LocalizedError {
    case invalidUsername
    case notConnected
    case notInitialized
    case socketInitializationFailed
    case connectionFailed(String)
    case apiError(String)
    case peerConnectionCreationFailed
    
    public var errorDescription: String? {
        switch self {
        case .invalidUsername:
            return "Username cannot be empty"
        case .notConnected:
            return "Service is not connected"
        case .notInitialized:
            return "Service is not initialized"
        case .socketInitializationFailed:
            return "Failed to initialize socket connection"
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .apiError(let message):
            return "API error: \(message)"
        case .peerConnectionCreationFailed:
            return "Failed to create peer connection"
        }
    }
}
