import Foundation
import WebRTC
import SocketIO
import AVFoundation
import CoreMedia

// MARK: - Service

public final class WebRTCService: NSObject {

    public static let shared = WebRTCService()
    override public init() {
        super.init()
        RTCInitializeSSL()
    }

    public weak var delegate: WebRTCServiceDelegate?

    private var socket: SocketIOClient?
    private var manager: SocketManager?

    private var peerConnections: [String: RTCPeerConnection] = [:]
    private var peerInitiators: [String: Bool] = [:] // Track who initiated each connection
    private var remoteStreams: [String: RTCMediaStream] = [:]
    private var localStream: RTCMediaStream?

    private var currentCallId: String?
    private var currentParticipantId: String?
    private var userId: String?
    private var userName: String?
    private var baseUrl: String?
    private var iceServers: [[String: Any]]?

    private let factory = RTCPeerConnectionFactory()
    private var videoCapturer: RTCCameraVideoCapturer?
    private var videoSource: RTCVideoSource?

    // MARK: - Connect

    // Convenience overload to preserve existing call sites
    public func connect(serverUrl: String, userId: String, userName: String) {
        connect(serverUrl: serverUrl, userId: userId, userName: userName) { _ in }
    }

    public func connect(serverUrl: String, userId: String, userName: String, 
                       completion: @escaping (Result<Void, Error>) -> Void) {
        guard !userName.trimmingCharacters(in: .whitespaces).isEmpty else {
            let error = NSError(domain: "WebRTCService", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "Username is required"])
            delegate?.onError("Username is required")
            completion(.failure(error))
            return
        }

        if socket?.status == .connected, self.userId == userId {
            completion(.success(()))
            return
        }

        disconnect()

        self.userId = userId
        self.userName = userName
        self.baseUrl = serverUrl

        manager = SocketManager(
            socketURL: URL(string: serverUrl)!,
            config: [
                .log(false),
                .compress,
                .reconnects(true),
                .reconnectAttempts(5),
                .reconnectWait(1)
            ]
        )

        socket = manager?.defaultSocket
        setupSocketListeners()

        // Wait for connection before calling completion
        socket?.once(clientEvent: .connect) { [weak self] _, _ in
            guard let self else { return }
            self.socket?.emit("register-user", ["userId": self.userId!, "userName": self.userName!])
            completion(.success(()))
        }

        socket?.once(clientEvent: .error) { _, _ in
            let error = NSError(domain: "WebRTCService", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "Connection failed"])
            completion(.failure(error))
        }

        socket?.connect()
    }

    // MARK: - Socket Listeners

    private func setupSocketListeners() {
        guard let socket = socket else { return }

        socket.on(clientEvent: .connect) { [weak self] _, _ in
            guard let self else { return }
            socket.emit("register-user", ["userId": self.userId!, "userName": self.userName!])
            self.delegate?.onConnectionChange(true)
        }

        socket.on(clientEvent: .disconnect) { [weak self] _, _ in
            self?.delegate?.onConnectionChange(false)
        }

        socket.on("users-online") { [weak self] data, _ in
            if let users = data.first as? [[String: Any]] {
                self?.delegate?.onOnlineUsers(users)
            }
        }

        socket.on("incoming-call") { [weak self] data, _ in
            self?.delegate?.onIncomingCall(data.first as? [String: Any] ?? [:])
        }

        socket.on("call-accepted") { [weak self] data, _ in
            self?.delegate?.onCallAccepted(data.first as? [String: Any] ?? [:])
        }

        socket.on("call-rejected") { [weak self] data, _ in
            self?.delegate?.onCallRejected(data.first as? [String: Any] ?? [:])
        }

        socket.on("participant-joined") { [weak self] data, _ in
            guard let self,
                  let payload = data.first as? [String: Any],
                  let pid = payload["participantId"] as? String
            else { return }

            if pid != self.currentParticipantId {
                self.createPeerConnection(participantId: pid, isInitiator: false)
            }
            self.delegate?.onParticipantJoined(payload)
        }

        socket.on("participant-left") { [weak self] data, _ in
            guard let payload = data.first as? [String: Any],
                  let pid = payload["participantId"] as? String
            else { return }

            self?.removePeerConnection(participantId: pid)
            self?.delegate?.onParticipantLeft(payload)
        }

        socket.on("call-joined") { [weak self] data, _ in
            guard let self,
                  let payload = data.first as? [String: Any],
                  let participants = payload["participants"] as? [[String: Any]]
            else { return }

            self.iceServers = payload["iceServers"] as? [[String: Any]]

            // Create peer connections for all existing participants
            for p in participants {
                if let id = p["id"] as? String {
                    self.createPeerConnection(participantId: id, isInitiator: true)
                }
            }
        }

        socket.on("signal") { [weak self] data, _ in
            self?.handleSignal(data.first as? [String: Any] ?? [:])
        }

        socket.on("error") { [weak self] data, _ in
            let msg = (data.first as? [String: Any])?["message"] as? String ?? "Unknown error"
            self?.delegate?.onError(msg)
        }
    }

    // MARK: - REST

    public func createCall(callType: String = "video", isGroup: Bool = false, maxParticipants: Int = 1000,
                           completion: @escaping (Result<[String: Any], Error>) -> Void) {

        guard let baseUrl else { return }
        var req = URLRequest(url: URL(string: "\(baseUrl)/api/calls")!)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "callType": callType,
            "isGroup": isGroup,
            "maxParticipants": maxParticipants
        ])

        URLSession.shared.dataTask(with: req) { data, _, err in
            if let err = err { completion(.failure(err)); return }
            let json = try? JSONSerialization.jsonObject(with: data!) as? [String: Any]
            if json?["success"] as? Bool == true {
                self.iceServers = (json?["config"] as? [String: Any])?["iceServers"] as? [[String: Any]]
                completion(.success(json!))
            } else {
                completion(.failure(NSError(domain: "", code: 0)))
            }
        }.resume()
    }

    public func joinCall(callId: String, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        guard let baseUrl, let userId, let userName else { return }

        var req = URLRequest(url: URL(string: "\(baseUrl)/api/calls/\(callId)/join")!)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "userId": userId,
            "userName": userName
        ])

        URLSession.shared.dataTask(with: req) { [weak self] data, _, err in
            guard let self else { return }
            
            if let err = err { completion(.failure(err)); return }
            let json = try? JSONSerialization.jsonObject(with: data!) as? [String: Any]
            guard json?["success"] as? Bool == true else {
                completion(.failure(NSError(domain: "", code: 0)))
                return
            }

            self.currentCallId = json?["callId"] as? String
            self.currentParticipantId = json?["participantId"] as? String
            self.iceServers = (json?["config"] as? [String: Any])?["iceServers"] as? [[String: Any]]

            print("📞 Join call - callId: \(self.currentCallId ?? "nil"), participantId: \(self.currentParticipantId ?? "nil")")

            // Get local media before joining
            self.getLocalMedia { result in
                switch result {
                case .success(let stream):
                    print("✅ Local media obtained successfully")
                    
                    // Now emit join-call after media is ready
                    self.socket?.emit("join-call", [
                        "callId": self.currentCallId!,
                        "participantId": self.currentParticipantId!,
                        "userName": userName
                    ])
                    
                    completion(.success(json!))
                    
                case .failure(let error):
                    print("❌ Failed to get local media: \(error)")
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    // MARK: - Media

    // Backwards-compatible convenience
    public func getLocalMedia() {
        getLocalMedia(constraints: [:]) { _ in }
    }

    public func getLocalMedia(constraints: [String: Any] = [:],
                              completion: @escaping (Result<RTCMediaStream, Error>) -> Void) {
        print("🎥 getLocalMedia called")
        
        // Request permissions first
        func requestPermissions(_ done: @escaping (Bool, Bool) -> Void) {
            var videoGranted = false
            var audioGranted = false

            let group = DispatchGroup()

            group.enter()
            AVCaptureDevice.requestAccess(for: .video) { granted in
                videoGranted = granted
                print("📹 Video permission: \(granted)")
                group.leave()
            }

            group.enter()
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                audioGranted = granted
                print("🎤 Audio permission: \(granted)")
                group.leave()
            }

            group.notify(queue: .main) {
                done(videoGranted, audioGranted)
            }
        }

        requestPermissions { [weak self] videoOK, audioOK in
            guard let self else { return }

            if !videoOK || !audioOK {
                let reason = !videoOK && !audioOK ? "camera and microphone" : (!videoOK ? "camera" : "microphone")
                let err = NSError(domain: "WebRTCService", code: -1,
                                   userInfo: [NSLocalizedDescriptionKey: "Permission denied for \(reason)"])
                self.delegate?.onError(err.localizedDescription)
                completion(.failure(err))
                return
            }

            // Configure audio session (iOS only)
            #if os(iOS)
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playAndRecord, mode: .videoChat, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
                try session.setActive(true)
                print("✅ Audio session configured")
            } catch {
                print("❌ Failed to configure audio session: \(error)")
                self.delegate?.onError("Failed to configure audio session: \(error.localizedDescription)")
            }
            #endif

            // Prepare local stream and start camera capture
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }

                let stream = self.factory.mediaStream(withStreamId: "local")

                // Audio
                let audioTrack = self.factory.audioTrack(withTrackId: "audio0")
                stream.addAudioTrack(audioTrack)
                print("✅ Audio track added")

                // Video
                let vSource = self.factory.videoSource()
                self.videoSource = vSource
                let capturer = RTCCameraVideoCapturer(delegate: vSource)
                self.videoCapturer = capturer
                let videoTrack = self.factory.videoTrack(with: vSource, trackId: "video0")
                stream.addVideoTrack(videoTrack)
                print("✅ Video track added")

                // Choose device and format
                let devices = RTCCameraVideoCapturer.captureDevices()
                #if os(iOS)
                let preferredPos: AVCaptureDevice.Position = .front
                let device = devices.first(where: { $0.position == preferredPos }) ?? devices.first
                #else
                let device = devices.first
                #endif

                if let device {
                    let formats = RTCCameraVideoCapturer.supportedFormats(for: device)
                    // Prefer 1280x720, else highest resolution
                    let targetWidth: Int32 = 1280
                    let targetHeight: Int32 = 720

                    var selectedFormat: AVCaptureDevice.Format? = formats.first
                    var selectedDimension: CMVideoDimensions = CMVideoDimensions(width: 0, height: 0)

                    for f in formats {
                        let desc = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
                        if desc.width == targetWidth && desc.height == targetHeight {
                            selectedFormat = f
                            selectedDimension = desc
                            break
                        }
                        if desc.width > selectedDimension.width || desc.height > selectedDimension.height {
                            selectedFormat = f
                            selectedDimension = desc
                        }
                    }

                    let fpsRanges = selectedFormat?.videoSupportedFrameRateRanges ?? []
                    let maxFps = fpsRanges.map { $0.maxFrameRate }.max() ?? 30
                    let fps = min(30, Int(maxFps))

                    print("📹 Starting capture with device: \(device.localizedName), format: \(selectedDimension.width)x\(selectedDimension.height)@\(fps)fps")

                    capturer.startCapture(with: device, format: selectedFormat!, fps: fps) { error in
                        if let error {
                            print("❌ Failed to start video capture: \(error)")
                            DispatchQueue.main.async { [weak self] in
                                self?.delegate?.onError("Failed to start video capture: \(error.localizedDescription)")
                            }
                        } else {
                            print("✅ Video capture started successfully")
                        }
                    }
                }

                self.localStream = stream

                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    print("📢 Calling onLocalStream delegate")
                    self.delegate?.onLocalStream(stream)
                    completion(.success(stream))
                }
            }
        }
    }

    // MARK: - Peer Connection

    private func createPeerConnection(participantId: String, isInitiator: Bool) {
        print("🔗 Creating peer connection with \(participantId), isInitiator: \(isInitiator)")
        
        let config = RTCConfiguration()
        config.iceServers = iceServers?.compactMap { serverDict -> RTCIceServer? in
            guard let urls = serverDict["urls"] as? [String] else { return nil }

            if let username = serverDict["username"] as? String,
               let credential = serverDict["credential"] as? String {
                return RTCIceServer(
                    urlStrings: urls,
                    username: username,
                    credential: credential
                )
            }

            return RTCIceServer(urlStrings: urls)
        } ?? [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]

        print("📡 ICE Servers: \(config.iceServers.map { $0.urlStrings })")

        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)

        guard let pc = factory.peerConnection(with: config, constraints: constraints, delegate: self) else {
            delegate?.onError("Failed to create peer connection")
            return
        }

        peerConnections[participantId] = pc
        peerInitiators[participantId] = isInitiator

        // Add local tracks to peer connection
        if let localStream = localStream {
            localStream.videoTracks.forEach { track in
                let sender = pc.add(track, streamIds: ["local"])
                print("➕ Added video track to peer connection, sender: \(sender)")
            }
            localStream.audioTracks.forEach { track in
                let sender = pc.add(track, streamIds: ["local"])
                print("➕ Added audio track to peer connection, sender: \(sender)")
            }
        } else {
            print("⚠️ No local stream available when creating peer connection")
        }

        if isInitiator {
            let offerConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
            pc.offer(for: offerConstraints) { [weak self, weak pc] sdp, error in
                guard let self, let pc, let sdp, error == nil else {
                    print("❌ Failed to create offer: \(error?.localizedDescription ?? "unknown")")
                    self?.delegate?.onError("Failed to create offer: \(error?.localizedDescription ?? "unknown")")
                    return
                }

                pc.setLocalDescription(sdp) { error in
                    if let error {
                        print("❌ Failed to set local description: \(error)")
                        self.delegate?.onError("Failed to set local description: \(error.localizedDescription)")
                        return
                    }

                    print("📤 Sending offer to \(participantId)")
                    self.socket?.emit("signal", [
                        "callId": self.currentCallId ?? "",
                        "targetId": participantId,
                        "signal": ["sdp": sdp.sdp, "type": sdp.type.rawValue],
                        "type": "offer"
                    ])
                }
            }
        }
    }

    private func handleSignal(_ data: [String: Any]) {
        guard let fromId = data["fromId"] as? String,
              let type = data["type"] as? String
        else { 
            print("⚠️ Invalid signal data")
            return 
        }

        print("📡 Received signal from \(fromId): \(type)")

        var pc = peerConnections[fromId]
        if pc == nil {
            createPeerConnection(participantId: fromId, isInitiator: false)
            pc = peerConnections[fromId]
        }

        guard let pc else { return }

        if type == "offer" {
            guard let signalData = data["signal"] as? [String: Any],
                  let sdpString = signalData["sdp"] as? String else { 
                print("⚠️ Invalid offer signal data")
                return 
            }
            let sdp = RTCSessionDescription(type: .offer, sdp: sdpString)

            pc.setRemoteDescription(sdp) { [weak self] error in
                guard let self else { return }
                if let error {
                    print("❌ Failed to set remote description: \(error)")
                    self.delegate?.onError("Failed to set remote description: \(error.localizedDescription)")
                    return
                }

                print("✅ Remote description set for offer")

                let answerConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
                pc.answer(for: answerConstraints) { [weak self, weak pc] answer, error in
                    guard let self, let pc, let answer, error == nil else {
                        print("❌ Failed to create answer: \(error?.localizedDescription ?? "unknown")")
                        self?.delegate?.onError("Failed to create answer: \(error?.localizedDescription ?? "unknown")")
                        return
                    }

                    pc.setLocalDescription(answer) { error in
                        if let error {
                            print("❌ Failed to set local description: \(error)")
                            self.delegate?.onError("Failed to set local description: \(error.localizedDescription)")
                            return
                        }

                        print("📤 Sending answer to \(fromId)")
                        self.socket?.emit("signal", [
                            "callId": self.currentCallId ?? "",
                            "targetId": fromId,
                            "signal": ["sdp": answer.sdp, "type": answer.type.rawValue],
                            "type": "answer"
                        ])
                    }
                }
            }
        } else if type == "answer" {
            guard let signalData = data["signal"] as? [String: Any],
                  let sdpString = signalData["sdp"] as? String else { 
                print("⚠️ Invalid answer signal data")
                return 
            }
            let sdp = RTCSessionDescription(type: .answer, sdp: sdpString)

            pc.setRemoteDescription(sdp) { [weak self] error in
                if let error {
                    print("❌ Failed to set remote description: \(error)")
                    self?.delegate?.onError("Failed to set remote description: \(error.localizedDescription)")
                } else {
                    print("✅ Remote description set for answer")
                }
            }
        } else if type == "ice-candidate" {
            guard let signalData = data["signal"] as? [String: Any],
                  let candidate = signalData["candidate"] as? String else { 
                print("⚠️ Invalid ICE candidate signal data")
                return 
            }

            var mLineIndex: Int32?
            if let idx = signalData["sdpMLineIndex"] as? Int {
                mLineIndex = Int32(idx)
            } else if let idx = signalData["sdpMLineIndex"] as? NSNumber {
                mLineIndex = idx.int32Value
            } else if let idx = signalData["sdpMLineIndex"] as? Int32 {
                mLineIndex = idx
            }
            guard let sdpMLineIndex = mLineIndex else { 
                print("⚠️ Invalid sdpMLineIndex")
                return 
            }

            let c = RTCIceCandidate(sdp: candidate,
                                    sdpMLineIndex: sdpMLineIndex,
                                    sdpMid: signalData["sdpMid"] as? String)

            pc.add(c) { [weak self] error in
                if let error {
                    print("❌ Failed to add ICE candidate: \(error)")
                    self?.delegate?.onError("Failed to add ICE candidate: \(error.localizedDescription)")
                } else {
                    print("✅ ICE candidate added successfully")
                }
            }
        }
    }

    private func removePeerConnection(participantId: String) {
        print("🗑️ Removing peer connection for \(participantId)")
        peerConnections[participantId]?.close()
        peerConnections.removeValue(forKey: participantId)
        peerInitiators.removeValue(forKey: participantId)
        remoteStreams.removeValue(forKey: participantId)
        delegate?.onRemoteStreamRemoved(participantId: participantId)
    }

    // MARK: - Call Controls

    public func acceptCall(callId: String, callerId: String) {
        socket?.emit("accept-call", ["callId": callId, "callerId": callerId])
    }

    public func rejectCall(callId: String, callerId: String) {
        socket?.emit("reject-call", ["callId": callId, "callerId": callerId])
    }

    public func sendCallInvitation(targetUserId: String, callId: String, callType: String,
                                   completion: @escaping (Result<[String: Any], Error>) -> Void) {
        socket?.emitWithAck("send-call-invitation", [
            "targetUserId": targetUserId,
            "callId": callId,
            "callType": callType,
            "callerId": userId ?? "",
            "callerName": userName ?? ""
        ]).timingOut(after: 10) { response in
            if let responseArray = response as? [[String: Any]], let data = responseArray.first {
                if data["success"] as? Bool == true {
                    completion(.success(data))
                } else {
                    let errorMsg = data["error"] as? String ?? "Failed to send call invitation"
                    let error = NSError(domain: "WebRTCService", code: -1,
                                        userInfo: [NSLocalizedDescriptionKey: errorMsg])
                    completion(.failure(error))
                }
            } else {
                let error = NSError(domain: "WebRTCService", code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
                completion(.failure(error))
            }
        }
    }

    public func toggleAudio(enabled: Bool) {
        localStream?.audioTracks.forEach { track in
            track.isEnabled = enabled
        }
        print("🎤 Audio:", enabled ? "enabled" : "disabled")
    }

    public func toggleVideo(enabled: Bool) {
        localStream?.videoTracks.forEach { track in
            track.isEnabled = enabled
        }
        print("📹 Video:", enabled ? "enabled" : "disabled")
    }

    public func leaveCall() {
        guard let callId = currentCallId else { return }
        print("👋 Leaving call: \(callId)")
        
        socket?.emit("leave-call", ["callId": callId, "reason": "left"])
        peerConnections.values.forEach { $0.close() }
        peerConnections.removeAll()
        peerInitiators.removeAll()
        remoteStreams.removeAll()
        
        // Stop local stream tracks
        localStream?.audioTracks.forEach { $0.isEnabled = false }
        localStream?.videoTracks.forEach { $0.isEnabled = false }
        localStream = nil
        
        // Stop camera capture
        videoCapturer?.stopCapture()
        videoCapturer = nil
        videoSource = nil
        
        #if os(iOS)
        // Optionally deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
        
        currentCallId = nil
        currentParticipantId = nil
    }

    public func disconnect() {
        leaveCall()
        socket?.disconnect()
        socket = nil
    }
}

// MARK: - RTCPeerConnectionDelegate

extension WebRTCService: RTCPeerConnectionDelegate {
    
    // MARK: - Media Stream Events (CRITICAL FIX)
    
    // Use the correct modern delegate method
    public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams: [RTCMediaStream]) {
        guard let participantId = peerConnections.first(where: { $0.value === peerConnection })?.key else {
            print("⚠️ Could not find participantId for peer connection")
            return
        }
        
        print("📥 Received \(streams.count) stream(s) from \(participantId)")
        
        if let stream = streams.first {
            print("📥 Stream details - audio tracks: \(stream.audioTracks.count), video tracks: \(stream.videoTracks.count)")
            remoteStreams[participantId] = stream
            
            DispatchQueue.main.async { [weak self] in
                print("📢 Calling onRemoteStream delegate for \(participantId)")
                self?.delegate?.onRemoteStream(participantId: participantId, stream: stream)
            }
        } else {
            print("⚠️ No streams received")
        }
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        guard let participantId = peerConnections.first(where: { $0.value === peerConnection })?.key else {
            return
        }
        print("📤 Stream removed from \(participantId)")
    }
    
    // MARK: - ICE Candidate Events
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        guard let participantId = peerConnections.first(where: { $0.value === peerConnection })?.key else {
            return
        }
        
        print("📡 Generated ICE candidate for \(participantId)")
        
        socket?.emit("signal", [
            "callId": currentCallId ?? "",
            "targetId": participantId,
            "type": "ice-candidate",
            "signal": [
                "candidate": candidate.sdp,
                "sdpMid": candidate.sdpMid ?? "",
                "sdpMLineIndex": candidate.sdpMLineIndex
            ]
        ])
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        // Empty implementation is fine
    }
    
    // MARK: - State Change Events
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        guard let participantId = peerConnections.first(where: { $0.value === peerConnection })?.key else { return }
        
        let stateStr: String
        switch newState {
        case .new: stateStr = "new"
        case .connecting: stateStr = "connecting"
        case .connected: stateStr = "connected"
        case .disconnected: stateStr = "disconnected"
        case .failed: stateStr = "failed"
        case .closed: stateStr = "closed"
        @unknown default: stateStr = "unknown"
        }
        
        print("🔌 PeerConnection [\(participantId)] → state: \(stateStr)")
        
        switch newState {
        case .failed, .disconnected:
            // Optional: Add reconnection logic or notify delegate
            break
        case .connected:
            print("✅ Peer connection established with \(participantId)")
            break
        default:
            break
        }
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        guard let participantId = peerConnections.first(where: { $0.value === peerConnection })?.key else { return }
        
        let stateStr: String
        switch newState {
        case .new: stateStr = "new"
        case .checking: stateStr = "checking"
        case .connected: stateStr = "connected"
        case .completed: stateStr = "completed"
        case .failed: stateStr = "failed"
        case .disconnected: stateStr = "disconnected"
        case .closed: stateStr = "closed"
        @unknown default: stateStr = "unknown"
        }
        
        print("❄️ ICE Connection [\(participantId)] → \(stateStr)")
        
        if newState == .failed || newState == .disconnected {
            // Optional: Restart ICE or notify delegate
        }
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        // Optional: print("ICE Gathering → \(newState)")
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCSignalingState) {
        // Optional: print("Signaling → \(newState)")
    }
    
    // MARK: - Negotiation & DataChannel
    
    public func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        // NOTE: Negotiation is handled by signal/offer-answer mechanism
        // Do NOT create offers here - only initiators create initial offers
        // This callback just indicates renegotiation may be needed
        // The signaling layer handles actual SDP exchange to avoid state conflicts
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        print("📨 DataChannel opened: \(dataChannel.label ?? "unnamed")")
        // Optional: Handle data channel
    }
}