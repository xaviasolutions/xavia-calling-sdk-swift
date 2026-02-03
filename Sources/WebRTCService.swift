import Foundation
import AVFoundation
import WebRTC
import SocketIO

// MARK: - Public API

@objc public protocol WebRTCServiceDelegate: AnyObject {
    @objc optional func onConnectionChange(_ isConnected: Bool)
    @objc optional func onLocalStream(_ stream: RTCMediaStream)
    @objc optional func onRemoteStream(_ participantId: String, stream: RTCMediaStream)
    @objc optional func onRemoteStreamRemoved(_ participantId: String)
    @objc optional func onOnlineUsers(_ users: [CallParticipant])
    @objc optional func onIncomingCall(_ data: IncomingCallData)
    @objc optional func onCallAccepted(_ data: CallResponse)
    @objc optional func onCallRejected(_ data: CallResponse)
    @objc optional func onParticipantJoined(_ participant: CallParticipant)
    @objc optional func onParticipantLeft(_ participant: CallParticipant)
    @objc optional func onError(_ message: String)
}

@objc public final class WebRTCService: NSObject {
    
    // MARK: - Singleton
    @objc public static let shared = WebRTCService()
    private override init() {
        super.init()
        RTCPeerConnectionFactory.initialize()
    }
    
    // MARK: - Public Properties
    @objc public weak var delegate: WebRTCServiceDelegate?
    
    // Callback closures for Swift users
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
    
    // MARK: - Objective-C Accessible Properties
    @objc public private(set) var isConnected: Bool = false
    @objc public private(set) var currentCallId: String?
    @objc public private(set) var localStream: RTCMediaStream?
    @objc public private(set) var remoteStreams: [String: RTCMediaStream] {
        get { _remoteStreams }
        set { _remoteStreams = newValue }
    }
    
    // MARK: - Private Properties
    private var socket: SocketIOClient?
    private var manager: SocketManager?
    private var peerConnections: [String: RTCPeerConnection] = [:]
    private var _remoteStreams: [String: RTCMediaStream] = [:]
    private var currentParticipantId: String?
    private var userId: String?
    private var userName: String?
    private var iceServers: [RTCIceServer] = []
    private var baseUrl: String?
    private var connectionTimeoutWorkItem: DispatchWorkItem?
    
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
    @objc public func connect(serverUrl: String, userId: String, userName: String, completion: @escaping (Error?) -> Void) {
        // Validate username
        guard !userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(WebRTCError.invalidUsername)
            return
        }
        
        // If already connected with same user, skip
        if let socket = socket, socket.status == .connected, self.userId == userId {
            print("⚠️ Already connected, skipping reconnection")
            completion(nil)
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
            completion(WebRTCError.invalidURL)
            return
        }
        
        // Cancel previous timeout
        connectionTimeoutWorkItem?.cancel()
        
        DispatchQueue.main.async {
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
            
            self.socket = self.manager?.defaultSocket
            self.setupSocketListeners()
            self.socket?.connect()
            
            // Setup connection timeout
            let timeoutWorkItem = DispatchWorkItem { [weak self] in
                if let self = self, !self.isConnected {
                    completion(WebRTCError.connectionTimeout)
                    self.disconnect()
                }
            }
            self.connectionTimeoutWorkItem = timeoutWorkItem
            DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: timeoutWorkItem)
        }
    }
    
    /// Disconnect from server
    @objc public func disconnect() {
        leaveCall()
        
        socket?.disconnect()
        socket = nil
        manager = nil
        
        userId = nil
        userName = nil
        baseUrl = nil
        isConnected = false
        
        notifyConnectionChange(false)
    }
    
    // MARK: - Call Management
    
    /// Create a new call
    @objc public func createCall(callType: String = "video", 
                                 isGroup: Bool = false, 
                                 maxParticipants: Int = 1000,
                                 completion: @escaping (CallResponse?, Error?) -> Void) {
        guard let baseUrl = baseUrl else {
            completion(nil, WebRTCError.notConnected)
            return
        }
        
        guard let url = URL(string: "\(baseUrl)/api/calls") else {
            completion(nil, WebRTCError.invalidURL)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        
        let body: [String: Any] = [
            "callType": callType,
            "isGroup": isGroup,
            "maxParticipants": maxParticipants
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(nil, error)
            return
        }
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(nil, error)
                }
                return
            }
            
            guard let data = data,
                  let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                DispatchQueue.main.async {
                    completion(nil, WebRTCError.networkError)
                }
                return
            }
            
            do {
                let decoder = JSONDecoder()
                let result = try decoder.decode(CallResponse.self, from: data)
                
                if !result.success {
                    DispatchQueue.main.async {
                        completion(nil, WebRTCError.serverError(result.error ?? "Failed to create call"))
                    }
                    return
                }
                
                print("✅ Call created: \(result.callId ?? "unknown")")
                
                if let iceServers = result.config?.iceServers {
                    self.iceServers = iceServers
                }
                
                DispatchQueue.main.async {
                    completion(result, nil)
                }
            } catch {
                print("Decode error: \(error)")
                DispatchQueue.main.async {
                    completion(nil, error)
                }
            }
        }
        task.resume()
    }
    
    /// Join an existing call
    @objc public func joinCall(callId: String, completion: @escaping (CallResponse?, Error?) -> Void) {
        guard let baseUrl = baseUrl,
              let userId = userId,
              let userName = userName else {
            completion(nil, WebRTCError.notConnected)
            return
        }
        
        guard let url = URL(string: "\(baseUrl)/api/calls/\(callId)/join") else {
            completion(nil, WebRTCError.invalidURL)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        
        let body: [String: Any] = [
            "userName": userName,
            "userId": userId
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(nil, error)
            return
        }
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(nil, error)
                }
                return
            }
            
            guard let data = data,
                  let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                DispatchQueue.main.async {
                    completion(nil, WebRTCError.networkError)
                }
                return
            }
            
            do {
                let decoder = JSONDecoder()
                let result = try decoder.decode(CallResponse.self, from: data)
                
                if !result.success {
                    DispatchQueue.main.async {
                        completion(nil, WebRTCError.serverError(result.error ?? "Failed to join call"))
                    }
                    return
                }
                
                print("✅ Joined call via API: \(result.callId ?? "unknown")")
                
                self.currentCallId = result.callId
                self.currentParticipantId = result.participantId
                
                if let iceServers = result.config?.iceServers {
                    self.iceServers = iceServers
                }
                
                // Get local media
                self.getLocalMedia { stream, error in
                    if let error = error {
                        DispatchQueue.main.async {
                            completion(nil, error)
                        }
                        return
                    }
                    
                    // Join via socket
                    self.socket?.emit("join-call", [
                        "callId": result.callId ?? "",
                        "participantId": result.participantId ?? "",
                        "userName": userName
                    ])
                    
                    DispatchQueue.main.async {
                        completion(result, nil)
                    }
                }
            } catch {
                print("Decode error: \(error)")
                DispatchQueue.main.async {
                    completion(nil, error)
                }
            }
        }
        task.resume()
    }
    
    /// Get local media stream
    @objc public func getLocalMedia(completion: @escaping (RTCMediaStream?, Error?) -> Void) {
        let streamId = "local_stream_\(UUID().uuidString)"
        let stream = factory.mediaStream(withStreamId: streamId)
        
        // Request camera permission
        AVCaptureDevice.requestAccess(for: .video) { videoGranted in
            AVCaptureDevice.requestAccess(for: .audio) { audioGranted in
                DispatchQueue.main.async {
                    if !videoGranted || !audioGranted {
                        completion(nil, WebRTCError.permissionDenied)
                        return
                    }
                    
                    // Add video track
                    let videoSource = self.factory.videoSource()
                    let videoTrack = self.factory.videoTrack(with: videoSource, trackId: "video_\(UUID().uuidString)")
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
                    
                    let audioSource = self.factory.audioSource(with: audioConstraints)
                    let audioTrack = self.factory.audioTrack(with: audioSource, trackId: "audio_\(UUID().uuidString)")
                    stream.addAudioTrack(audioTrack)
                    
                    self.localStream = stream
                    print("✅ Local media obtained")
                    
                    self.notifyLocalStream(stream)
                    completion(stream, nil)
                }
            }
        }
    }
    
    /// Send call invitation
    @objc public func sendCallInvitation(targetUserId: String, 
                                         callId: String, 
                                         callType: String,
                                         completion: @escaping (CallResponse?, Error?) -> Void) {
        guard let userId = userId, let userName = userName else {
            completion(nil, WebRTCError.notConnected)
            return
        }
        
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
                    completion(response, nil)
                } else {
                    completion(nil, WebRTCError.serverError(response.error ?? "Invitation failed"))
                }
            } else {
                completion(nil, WebRTCError.invalidResponse)
            }
        }
    }
    
    /// Accept incoming call
    @objc public func acceptCall(callId: String, callerId: String) {
        socket?.emit("accept-call", [
            "callId": callId,
            "callerId": callerId
        ])
    }
    
    /// Reject incoming call
    @objc public func rejectCall(callId: String, callerId: String) {
        socket?.emit("reject-call", [
            "callId": callId,
            "callerId": callerId
        ])
    }
    
    /// Leave current call
    @objc public func leaveCall() {
        guard let callId = currentCallId else { return }
        
        print("👋 Leaving call: \(callId)")
        
        socket?.emit("leave-call", [
            "callId": callId,
            "reason": "left"
        ])
        
        cleanupPeerConnections()
        
        currentCallId = nil
        currentParticipantId = nil
        localStream = nil
        _remoteStreams.removeAll()
    }
    
    /// Toggle audio
    @objc public func toggleAudio(enabled: Bool) {
        localStream?.audioTracks.forEach { $0.isEnabled = enabled }
        print("🎤 Audio: \(enabled ? "enabled" : "disabled")")
    }
    
    /// Toggle video
    @objc public func toggleVideo(enabled: Bool) {
        localStream?.videoTracks.forEach { $0.isEnabled = enabled }
        print("📹 Video: \(enabled ? "enabled" : "disabled")")
    }
    
    // MARK: - Private Methods
    
    private func setupSocketListeners() {
        guard let socket = socket else { return }
        
        socket.on(clientEvent: .connect) { [weak self] _, _ in
            print("✅ Socket connected")
            self?.isConnected = true
            self?.connectionTimeoutWorkItem?.cancel()
            self?.connectionTimeoutWorkItem = nil
            
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
            self?.isConnected = false
            self?.notifyConnectionChange(false)
        }
        
        socket.on(clientEvent: .error) { [weak self] data, _ in
            print("Socket error: \(data)")
            self?.notifyError("Socket connection error")
        }
        
        // Online users list
        socket.on("users-online") { [weak self] data, _ in
            guard let usersData = data.first as? [[String: Any]] else { return }
            let users = usersData.compactMap(CallParticipant.from(dictionary:))
            print("📢 Online users: \(users.count)")
            self?.notifyOnlineUsers(users)
        }
        
        // Incoming call invitation
        socket.on("incoming-call") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any],
                  let callData = IncomingCallData.from(dictionary: dict) else { return }
            print("📞 Incoming call from: \(callData.callerName)")
            self?.notifyIncomingCall(callData)
        }
        
        // Call accepted
        socket.on("call-accepted") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any] else { return }
            let response = CallResponse.from(dictionary: dict)
            print("✅ Call accepted")
            self?.notifyCallAccepted(response)
        }
        
        // Call rejected
        socket.on("call-rejected") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any] else { return }
            let response = CallResponse.from(dictionary: dict)
            print("❌ Call rejected")
            self?.notifyCallRejected(response)
        }
        
        // Call joined successfully
        socket.on("call-joined") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any],
                  let callId = dict["callId"] as? String,
                  let participantsData = dict["participants"] as? [[String: Any]],
                  let iceServersData = dict["iceServers"] as? [[String: Any]] else {
                return
            }
            
            print("✅ Joined call: \(callId)")
            
            // Parse participants
            let participants = participantsData.compactMap(CallParticipant.from(dictionary:))
            
            // Parse ICE servers
            self?.iceServers = iceServersData.compactMap { serverDict in
                guard let urlsValue = serverDict["urls"] else { return nil }
                if let urlString = urlsValue as? String {
                    return RTCIceServer(urlStrings: [urlString])
                } else if let urlArray = urlsValue as? [String] {
                    return RTCIceServer(urlStrings: urlArray)
                } else if let urlArray = serverDict["urls"] as? [String] {
                    let username = serverDict["username"] as? String
                    let credential = serverDict["credential"] as? String
                    return RTCIceServer(urlStrings: urlArray, username: username, credential: credential)
                }
                return nil
            }
            
            // Create peer connections for existing participants
            for participant in participants {
                if participant.id != self?.currentParticipantId {
                    self?.createPeerConnection(participantId: participant.id, isInitiator: true)
                }
            }
        }
        
        // New participant joined
        socket.on("participant-joined") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any],
                  let participantId = dict["participantId"] as? String,
                  let userName = dict["userName"] as? String,
                  let userId = dict["userId"] as? String else {
                return
            }
            
            let participant = CallParticipant(id: participantId, userName: userName, userId: userId)
            print("👤 Participant joined: \(userName)")
            
            if participantId != self?.currentParticipantId {
                self?.createPeerConnection(participantId: participantId, isInitiator: false)
            }
            
            self?.notifyParticipantJoined(participant)
        }
        
        // Participant left
        socket.on("participant-left") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any],
                  let participantId = dict["participantId"] as? String else {
                return
            }
            
            print("👋 Participant left: \(participantId)")
            self?.removePeerConnection(participantId: participantId)
            
            let participant = CallParticipant(
                id: participantId,
                userName: dict["userName"] as? String ?? "",
                userId: dict["userId"] as? String ?? ""
            )
            self?.notifyParticipantLeft(participant)
        }
        
        // WebRTC signaling
        socket.on("signal") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any],
                  let fromId = dict["fromId"] as? String,
                  let signalData = dict["signal"] as? [String: Any],
                  let typeString = dict["type"] as? String,
                  let type = SignalType(rawValue: typeString) else {
                return
            }
            
            let signal = SignalContent(
                sdp: signalData["sdp"] as? String,
                type: signalData["type"] as? String,
                candidate: signalData["candidate"] as? String,
                sdpMid: signalData["sdpMid"] as? String,
                sdpMLineIndex: signalData["sdpMLineIndex"] as? Int32
            )
            
            let signalMessage = SignalData(fromId: fromId, signal: signal, type: type)
            
            self?.handleSignal(signalMessage)
        }
        
        // Error handling
        socket.on("error") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any],
                  let message = dict["message"] as? String else {
                return
            }
            print("❌ Server error: \(message)")
            self?.notifyError(message)
        }
    }
    
    private func createPeerConnection(participantId: String, isInitiator: Bool) {
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
        
        // Add local stream tracks
        if let localStream = localStream {
            for track in localStream.videoTracks {
                pc.add(track, streamIds: [localStream.streamId])
                print("➕ Added local video track")
            }
            for track in localStream.audioTracks {
                pc.add(track, streamIds: [localStream.streamId])
                print("➕ Added local audio track")
            }
        }
        
        // If initiator, create and send offer
        if isInitiator {
            pc.offer(for: constraints) { [weak self] offer, error in
                guard let offer = offer, error == nil else {
                    print("Create offer error: \(error?.localizedDescription ?? "unknown")")
                    self?.notifyError("Failed to create offer: \(error?.localizedDescription ?? "unknown")")
                    return
                }
                
                pc.setLocalDescription(offer) { error in
                    if let error = error {
                        print("Set local description error: \(error)")
                        return
                    }
                    
                    print("📤 Sending offer to \(participantId)")
                    
                    self?.socket?.emit("signal", [
                        "callId": self?.currentCallId ?? "",
                        "targetId": participantId,
                        "signal": [
                            "sdp": offer.sdp,
                            "type": offer.type.rawValue
                        ],
                        "type": "offer"
                    ])
                }
            }
        }
    }
    
    private func handleSignal(_ data: SignalData) {
        let fromId = data.fromId
        let signal = data.signal
        let type = data.type
        
        print("📡 Received signal from \(fromId): \(type)")
        
        var pc = peerConnections[fromId]
        
        // Create peer connection if doesn't exist
        if pc == nil {
            createPeerConnection(participantId: fromId, isInitiator: false)
            pc = peerConnections[fromId]
        }
        
        guard let peerConnection = pc else {
            print("❌ Failed to get peer connection for \(fromId)")
            return
        }
        
        switch type {
        case .offer:
            guard let sdp = signal.sdp, let typeStr = signal.type,
                  let sdpType = RTCSdpType(rawValue: typeStr) else {
                notifyError("Invalid offer signal")
                return
            }
            
            let remoteSdp = RTCSessionDescription(type: sdpType, sdp: sdp)
            peerConnection.setRemoteDescription(remoteSdp) { [weak self] error in
                if let error = error {
                    print("Set remote description error: \(error)")
                    self?.notifyError("Failed to set remote description: \(error.localizedDescription)")
                    return
                }
                
                peerConnection.answer(for: nil) { answer, error in
                    guard let answer = answer, error == nil else {
                        print("Create answer error: \(error?.localizedDescription ?? "unknown")")
                        self?.notifyError("Failed to create answer: \(error?.localizedDescription ?? "unknown")")
                        return
                    }
                    
                    peerConnection.setLocalDescription(answer) { error in
                        if let error = error {
                            print("Set local description error: \(error)")
                            return
                        }
                        
                        print("📤 Sending answer to \(fromId)")
                        
                        self?.socket?.emit("signal", [
                            "callId": self?.currentCallId ?? "",
                            "targetId": fromId,
                            "signal": [
                                "sdp": answer.sdp,
                                "type": answer.type.rawValue
                            ],
                            "type": "answer"
                        ])
                    }
                }
            }
            
        case .answer:
            guard let sdp = signal.sdp, let typeStr = signal.type,
                  let sdpType = RTCSdpType(rawValue: typeStr) else {
                notifyError("Invalid answer signal")
                return
            }
            
            let remoteSdp = RTCSessionDescription(type: sdpType, sdp: sdp)
            peerConnection.setRemoteDescription(remoteSdp) { error in
                if let error = error {
                    print("Set remote description error: \(error)")
                }
            }
            
        case .iceCandidate:
            guard let candidate = signal.candidate,
                  let sdpMid = signal.sdpMid,
                  let sdpMLineIndex = signal.sdpMLineIndex else {
                notifyError("Invalid ICE candidate")
                return
            }
            
            let iceCandidate = RTCIceCandidate(
                sdp: candidate,
                sdpMLineIndex: Int32(sdpMLineIndex),
                sdpMid: sdpMid
            )
            
            peerConnection.add(iceCandidate)
        }
    }
    
    private func removePeerConnection(participantId: String) {
        if let pc = peerConnections[participantId] {
            pc.close()
            peerConnections.removeValue(forKey: participantId)
        }
        
        if _remoteStreams[participantId] != nil {
            _remoteStreams.removeValue(forKey: participantId)
            notifyRemoteStreamRemoved(participantId)
        }
    }
    
    private func cleanupPeerConnections() {
        peerConnections.values.forEach { $0.close() }
        peerConnections.removeAll()
        _remoteStreams.removeAll()
        
        // Stop local stream
        localStream?.audioTracks.forEach { $0.isEnabled = false }
        localStream?.videoTracks.forEach { $0.isEnabled = false }
        localStream = nil
    }
    
    // MARK: - Notification Helpers
    
    private func notifyConnectionChange(_ isConnected: Bool) {
        DispatchQueue.main.async {
            self.delegate?.onConnectionChange?(isConnected)
            self.onConnectionChange?(isConnected)
        }
    }
    
    private func notifyLocalStream(_ stream: RTCMediaStream) {
        DispatchQueue.main.async {
            self.delegate?.onLocalStream?(stream)
            self.onLocalStream?(stream)
        }
    }
    
    private func notifyRemoteStream(_ participantId: String, _ stream: RTCMediaStream) {
        DispatchQueue.main.async {
            self._remoteStreams[participantId] = stream
            self.delegate?.onRemoteStream?(participantId, stream)
            self.onRemoteStream?(participantId, stream)
        }
    }
    
    private func notifyRemoteStreamRemoved(_ participantId: String) {
        DispatchQueue.main.async {
            self.delegate?.onRemoteStreamRemoved?(participantId)
            self.onRemoteStreamRemoved?(participantId)
        }
    }
    
    private func notifyOnlineUsers(_ users: [CallParticipant]) {
        DispatchQueue.main.async {
            self.delegate?.onOnlineUsers?(users)
            self.onOnlineUsers?(users)
        }
    }
    
    private func notifyIncomingCall(_ data: IncomingCallData) {
        DispatchQueue.main.async {
            self.delegate?.onIncomingCall?(data)
            self.onIncomingCall?(data)
        }
    }
    
    private func notifyCallAccepted(_ data: CallResponse) {
        DispatchQueue.main.async {
            self.delegate?.onCallAccepted?(data)
            self.onCallAccepted?(data)
        }
    }
    
    private func notifyCallRejected(_ data: CallResponse) {
        DispatchQueue.main.async {
            self.delegate?.onCallRejected?(data)
            self.onCallRejected?(data)
        }
    }
    
    private func notifyParticipantJoined(_ participant: CallParticipant) {
        DispatchQueue.main.async {
            self.delegate?.onParticipantJoined?(participant)
            self.onParticipantJoined?(participant)
        }
    }
    
    private func notifyParticipantLeft(_ participant: CallParticipant) {
        DispatchQueue.main.async {
            self.delegate?.onParticipantLeft?(participant)
            self.onParticipantLeft?(participant)
        }
    }
    
    private func notifyError(_ message: String) {
        DispatchQueue.main.async {
            self.delegate?.onError?(message)
            self.onError?(message)
        }
    }
}

// MARK: - RTCPeerConnectionDelegate
extension WebRTCService: RTCPeerConnectionDelegate {
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        guard let participantId = findParticipantId(for: peerConnection) else { return }
        
        print("📥 Received remote stream from \(participantId)")
        notifyRemoteStream(participantId, stream)
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        guard let participantId = findParticipantId(for: peerConnection) else { return }
        
        print("Removed remote stream from \(participantId)")
        notifyRemoteStreamRemoved(participantId)
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        guard let participantId = findParticipantId(for: peerConnection) else { return }
        
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
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        guard let participantId = findParticipantId(for: peerConnection) else { return }
        print("ICE connection state with \(participantId): \(newState.rawValue)")
        
        if newState == .disconnected || newState == .failed || newState == .closed {
            // Clean up failed connection
            removePeerConnection(participantId: participantId)
        }
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCSignalingState) {
        print("Signaling state changed: \(newState.rawValue)")
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        guard let participantId = findParticipantId(for: peerConnection) else { return }
        print("Peer connection state with \(participantId): \(newState.rawValue)")
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        print("ICE gathering state: \(newState.rawValue)")
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        // Not used in this implementation
    }
    
    public func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        // Trigger renegotiation if needed
        print("Peer connection should negotiate")
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        print("Data channel opened")
    }
    
    private func findParticipantId(for peerConnection: RTCPeerConnection) -> String? {
        return peerConnections.first { $0.value === peerConnection }?.key
    }
}