import Foundation
import AVFoundation
import WebRTC
import SocketIO

// MARK: - Delegate Protocol

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

// MARK: - Main Service Class

@objc public final class WebRTCService: NSObject {
    
    // MARK: - Singleton
    @objc public static let shared = WebRTCService()
    private override init() {
        super.init()
        RTCPeerConnectionFactory.initialize()
    }
    
    // MARK: - Public Properties
    @objc public weak var delegate: WebRTCServiceDelegate?
    
    // Callback closures
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
    
    @objc public private(set) var isConnected: Bool = false
    @objc public private(set) var currentCallId: String?
    @objc public private(set) var localStream: RTCMediaStream?
    @objc public private(set) var remoteStreams: [String: RTCMediaStream] = [:]
    
    // MARK: - Private Properties
    private var socket: SocketIOClient?
    private var manager: SocketManager?
    private var peerConnections: [String: RTCPeerConnection] = [:]
    private var currentParticipantId: String?
    private var userId: String?
    private var userName: String?
    private var iceServers: [RTCIceServer] = []
    private var baseUrl: String?
    
    private lazy var factory: RTCPeerConnectionFactory = {
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        return RTCPeerConnectionFactory(
            encoderFactory: videoEncoderFactory,
            decoderFactory: videoDecoderFactory
        )
    }()
    
    // MARK: - Connection Management
    
    @objc public func connect(serverUrl: String, userId: String, userName: String, completion: @escaping (Error?) -> Void) {
        guard !userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(NSError(domain: "WebRTCService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Username is required"]))
            return
        }
        
        if let socket = socket, socket.status == .connected, self.userId == userId {
            print("Already connected")
            completion(nil)
            return
        }
        
        if socket != nil && self.userId != userId {
            disconnect()
        }
        
        self.baseUrl = serverUrl
        self.userId = userId
        self.userName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let url = URL(string: serverUrl) else {
            completion(NSError(domain: "WebRTCService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid server URL"]))
            return
        }
        
        DispatchQueue.main.async {
            self.manager = SocketManager(
                socketURL: url,
                config: [
                    .log(false),
                    .compress,
                    .reconnects(true),
                    .reconnectAttempts(5),
                    .reconnectWait(1000)
                ]
            )
            
            self.socket = self.manager?.defaultSocket
            self.setupSocketListeners()
            self.socket?.connect()
            
            // Timeout after 10 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                if !self.isConnected {
                    completion(NSError(domain: "WebRTCService", code: -3, userInfo: [NSLocalizedDescriptionKey: "Connection timeout"]))
                }
            }
        }
        
        // Listen for connection success
        let originalOnConnectionChange = onConnectionChange
        onConnectionChange = { [weak self] connected in
            if connected {
                completion(nil)
            }
            originalOnConnectionChange?(connected)
        }
    }
    
    @objc public func disconnect() {
        leaveCall()
        socket?.disconnect()
        socket = nil
        manager = nil
        isConnected = false
        notifyConnectionChange(false)
    }
    
    // MARK: - Call Management
    
    @objc public func createCall(callType: String = "video", 
                                 isGroup: Bool = false, 
                                 maxParticipants: Int = 1000,
                                 completion: @escaping (CallResponse?, Error?) -> Void) {
        guard let baseUrl = baseUrl else {
            completion(nil, NSError(domain: "WebRTCService", code: -4, userInfo: [NSLocalizedDescriptionKey: "Not connected"]))
            return
        }
        
        guard let url = URL(string: "\(baseUrl)/api/calls") else {
            completion(nil, NSError(domain: "WebRTCService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
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
        
        URLSession.shared.dataTask(with: request) { data, response, error in
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
                    completion(nil, NSError(domain: "WebRTCService", code: -5, userInfo: [NSLocalizedDescriptionKey: "Network error"]))
                }
                return
            }
            
            do {
                let decoder = JSONDecoder()
                let result = try decoder.decode(CallResponse.self, from: data)
                
                DispatchQueue.main.async {
                    if result.success {
                        if let iceServers = result.config?.iceServers {
                            self.iceServers = iceServers
                        }
                        completion(result, nil)
                    } else {
                        completion(nil, NSError(domain: "WebRTCService", code: -6, userInfo: [NSLocalizedDescriptionKey: result.error ?? "Failed to create call"]))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(nil, error)
                }
            }
        }.resume()
    }
    
    @objc public func joinCall(callId: String, completion: @escaping (CallResponse?, Error?) -> Void) {
        guard let baseUrl = baseUrl,
              let userId = userId,
              let userName = userName else {
            completion(nil, NSError(domain: "WebRTCService", code: -4, userInfo: [NSLocalizedDescriptionKey: "Not connected"]))
            return
        }
        
        guard let url = URL(string: "\(baseUrl)/api/calls/\(callId)/join") else {
            completion(nil, NSError(domain: "WebRTCService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
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
        
        URLSession.shared.dataTask(with: request) { data, response, error in
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
                    completion(nil, NSError(domain: "WebRTCService", code: -5, userInfo: [NSLocalizedDescriptionKey: "Network error"]))
                }
                return
            }
            
            do {
                let decoder = JSONDecoder()
                let result = try decoder.decode(CallResponse.self, from: data)
                
                DispatchQueue.main.async {
                    if result.success {
                        self.currentCallId = result.callId
                        self.currentParticipantId = result.participantId
                        
                        if let iceServers = result.config?.iceServers {
                            self.iceServers = iceServers
                        }
                        
                        // Get local media
                        self.getLocalMedia { stream, error in
                            if let error = error {
                                completion(nil, error)
                                return
                            }
                            
                            // Join via socket
                            self.socket?.emit("join-call", [
                                "callId": result.callId ?? "",
                                "participantId": result.participantId ?? "",
                                "userName": userName
                            ])
                            
                            completion(result, nil)
                        }
                    } else {
                        completion(nil, NSError(domain: "WebRTCService", code: -7, userInfo: [NSLocalizedDescriptionKey: result.error ?? "Failed to join call"]))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(nil, error)
                }
            }
        }.resume()
    }
    
    @objc public func getLocalMedia(completion: @escaping (RTCMediaStream?, Error?) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { videoGranted in
                AVCaptureDevice.requestAccess(for: .audio) { audioGranted in
                    DispatchQueue.main.async {
                        if videoGranted && audioGranted {
                            self.createLocalStream(completion: completion)
                        } else {
                            completion(nil, NSError(domain: "WebRTCService", code: -8, userInfo: [NSLocalizedDescriptionKey: "Camera or microphone permission denied"]))
                        }
                    }
                }
            }
        } else if status == .authorized {
            createLocalStream(completion: completion)
        } else {
            completion(nil, NSError(domain: "WebRTCService", code: -8, userInfo: [NSLocalizedDescriptionKey: "Camera or microphone permission denied"]))
        }
    }
    
    private func createLocalStream(completion: @escaping (RTCMediaStream?, Error?) -> Void) {
        let streamId = "local_stream_\(UUID().uuidString)"
        let stream = factory.mediaStream(withStreamId: streamId)
        
        // Create video track
        let videoSource = factory.videoSource()
        let videoTrack = factory.videoTrack(with: videoSource, trackId: "video_\(UUID().uuidString)")
        stream.addVideoTrack(videoTrack)
        
        // Create audio track
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
        
        self.localStream = stream
        notifyLocalStream(stream)
        completion(stream, nil)
    }
    
    @objc public func sendCallInvitation(targetUserId: String, 
                                         callId: String, 
                                         callType: String,
                                         completion: @escaping (CallResponse?, Error?) -> Void) {
        guard let userId = userId, let userName = userName else {
            completion(nil, NSError(domain: "WebRTCService", code: -4, userInfo: [NSLocalizedDescriptionKey: "Not connected"]))
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
                
                DispatchQueue.main.async {
                    if response.success {
                        completion(response, nil)
                    } else {
                        completion(nil, NSError(domain: "WebRTCService", code: -9, userInfo: [NSLocalizedDescriptionKey: response.error ?? "Invitation failed"]))
                    }
                }
            } else {
                DispatchQueue.main.async {
                    completion(nil, NSError(domain: "WebRTCService", code: -10, userInfo: [NSLocalizedDescriptionKey: "Invalid response"]))
                }
            }
        }
    }
    
    @objc public func acceptCall(callId: String, callerId: String) {
        socket?.emit("accept-call", [
            "callId": callId,
            "callerId": callerId
        ])
    }
    
    @objc public func rejectCall(callId: String, callerId: String) {
        socket?.emit("reject-call", [
            "callId": callId,
            "callerId": callerId
        ])
    }
    
    @objc public func leaveCall() {
        guard let callId = currentCallId else { return }
        
        socket?.emit("leave-call", [
            "callId": callId,
            "reason": "left"
        ])
        
        cleanupPeerConnections()
        currentCallId = nil
        currentParticipantId = nil
    }
    
    @objc public func toggleAudio(enabled: Bool) {
        localStream?.audioTracks.forEach { $0.isEnabled = enabled }
    }
    
    @objc public func toggleVideo(enabled: Bool) {
        localStream?.videoTracks.forEach { $0.isEnabled = enabled }
    }
    
    // MARK: - Private Methods
    
    private func setupSocketListeners() {
        guard let socket = socket else { return }
        
        socket.on(clientEvent: .connect) { [weak self] _, _ in
            print("✅ Socket connected")
            self?.isConnected = true
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
        
        socket.on("users-online") { [weak self] data, _ in
            guard let usersData = data.first as? [[String: Any]] else { return }
            let users = usersData.compactMap(CallParticipant.from(dictionary:))
            self?.notifyOnlineUsers(users)
        }
        
        socket.on("incoming-call") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any],
                  let callData = IncomingCallData.from(dictionary: dict) else { return }
            self?.notifyIncomingCall(callData)
        }
        
        socket.on("call-accepted") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any] else { return }
            let response = CallResponse.from(dictionary: dict)
            self?.notifyCallAccepted(response)
        }
        
        socket.on("call-rejected") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any] else { return }
            let response = CallResponse.from(dictionary: dict)
            self?.notifyCallRejected(response)
        }
        
        socket.on("call-joined") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any],
                  let participantsData = dict["participants"] as? [[String: Any]],
                  let iceServersData = dict["iceServers"] as? [[String: Any]] else {
                return
            }
            
            let participants = participantsData.compactMap(CallParticipant.from(dictionary:))
            
            self?.iceServers = iceServersData.compactMap { serverDict in
                guard let urlsValue = serverDict["urls"] else { return nil }
                if let urlString = urlsValue as? String {
                    return RTCIceServer(urlStrings: [urlString])
                } else if let urlArray = urlsValue as? [String] {
                    return RTCIceServer(urlStrings: urlArray)
                }
                return nil
            }
            
            for participant in participants {
                if participant.id != self?.currentParticipantId {
                    self?.createPeerConnection(participantId: participant.id, isInitiator: true)
                }
            }
        }
        
        socket.on("participant-joined") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any],
                  let participant = CallParticipant.from(dictionary: dict) else {
                return
            }
            
            self?.notifyParticipantJoined(participant)
            
            if participant.id != self?.currentParticipantId {
                self?.createPeerConnection(participantId: participant.id, isInitiator: false)
            }
        }
        
        socket.on("participant-left") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any],
                  let participantId = dict["participantId"] as? String else {
                return
            }
            
            self?.removePeerConnection(participantId: participantId)
            
            let participant = CallParticipant(
                id: participantId,
                userName: dict["userName"] as? String ?? "",
                userId: dict["userId"] as? String ?? ""
            )
            self?.notifyParticipantLeft(participant)
        }
        
        socket.on("signal") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any],
                  let fromId = dict["fromId"] as? String,
                  let signalDict = dict["signal"] as? [String: Any],
                  let typeString = dict["type"] as? String else {
                return
            }
            
            let signal = SignalContent(
                sdp: signalDict["sdp"] as? String,
                type: signalDict["type"] as? String,
                candidate: signalDict["candidate"] as? String,
                sdpMid: signalDict["sdpMid"] as? String,
                sdpMLineIndex: signalDict["sdpMLineIndex"] as? Int32
            )
            
            self?.handleSignal(fromId: fromId, signal: signal, type: typeString)
        }
    }
    
    private func createPeerConnection(participantId: String, isInitiator: Bool) {
        let config = RTCConfiguration()
        config.iceServers = iceServers.isEmpty ? 
            [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])] : 
            iceServers
        config.sdpSemantics = .unifiedPlan
        
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue,
                kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueTrue
            ],
            optionalConstraints: nil
        )
        
        guard let pc = factory.peerConnection(with: config, constraints: constraints, delegate: self) else {
            return
        }
        
        peerConnections[participantId] = pc
        
        if let localStream = localStream {
            for track in localStream.videoTracks {
                pc.add(track, streamIds: [localStream.streamId])
            }
            for track in localStream.audioTracks {
                pc.add(track, streamIds: [localStream.streamId])
            }
        }
        
        if isInitiator {
            pc.offer(for: constraints) { [weak self] offer, error in
                guard let offer = offer, error == nil else { return }
                
                pc.setLocalDescription(offer) { error in
                    if error == nil {
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
    }
    
    private func handleSignal(fromId: String, signal: SignalContent, type: String) {
        guard let pc = peerConnections[fromId] else {
            createPeerConnection(participantId: fromId, isInitiator: false)
            return
        }
        
        if type == "offer", let sdp = signal.sdp, let sdpType = signal.type {
            let remoteSdp = RTCSessionDescription(type: RTCSdpType(rawValue: sdpType) ?? .offer, sdp: sdp)
            pc.setRemoteDescription(remoteSdp) { error in
                if error == nil {
                    pc.answer(for: nil) { answer, error in
                        guard let answer = answer, error == nil else { return }
                        
                        pc.setLocalDescription(answer) { error in
                            if error == nil {
                                self.socket?.emit("signal", [
                                    "callId": self.currentCallId ?? "",
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
                }
            }
        } else if type == "answer", let sdp = signal.sdp, let sdpType = signal.type {
            let remoteSdp = RTCSessionDescription(type: RTCSdpType(rawValue: sdpType) ?? .answer, sdp: sdp)
            pc.setRemoteDescription(remoteSdp) { _ in }
        } else if type == "ice-candidate", let candidate = signal.candidate,
                  let sdpMid = signal.sdpMid, let sdpMLineIndex = signal.sdpMLineIndex {
            let iceCandidate = RTCIceCandidate(
                sdp: candidate,
                sdpMLineIndex: Int32(sdpMLineIndex),
                sdpMid: sdpMid
            )
            pc.add(iceCandidate)
        }
    }
    
    private func removePeerConnection(participantId: String) {
        peerConnections[participantId]?.close()
        peerConnections.removeValue(forKey: participantId)
        remoteStreams.removeValue(forKey: participantId)
        notifyRemoteStreamRemoved(participantId)
    }
    
    private func cleanupPeerConnections() {
        peerConnections.values.forEach { $0.close() }
        peerConnections.removeAll()
        remoteStreams.removeAll()
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
            self.remoteStreams[participantId] = stream
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
        notifyRemoteStream(participantId, stream)
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        guard let participantId = findParticipantId(for: peerConnection) else { return }
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
        print("ICE connection state: \(newState.rawValue)")
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCSignalingState) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    public func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
    
    private func findParticipantId(for peerConnection: RTCPeerConnection) -> String? {
        return peerConnections.first { $0.value === peerConnection }?.key
    }
}