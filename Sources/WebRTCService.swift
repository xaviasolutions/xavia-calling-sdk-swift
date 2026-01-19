import Foundation
import WebRTC
import SocketIO
import AVFoundation

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
    private var remoteStreams: [String: RTCMediaStream] = [:]
    private var localStream: RTCMediaStream?

    private var currentCallId: String?
    private var currentParticipantId: String?
    private var userId: String?
    private var userName: String?
    private var baseUrl: String?
    private var iceServers: [[String: Any]]?

    private let factory = RTCPeerConnectionFactory()

    // MARK: - Connect

    public func connect(serverUrl: String, userId: String, userName: String) {
        guard !userName.trimmingCharacters(in: .whitespaces).isEmpty else {
            delegate?.onError("Username is required")
            return
        }

        if socket?.status == .connected, self.userId == userId { return }

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

        URLSession.shared.dataTask(with: req) { data, _, err in
            if let err = err { completion(.failure(err)); return }
            let json = try? JSONSerialization.jsonObject(with: data!) as? [String: Any]
            guard json?["success"] as? Bool == true else {
                completion(.failure(NSError(domain: "", code: 0)))
                return
            }

            self.currentCallId = json?["callId"] as? String
            self.currentParticipantId = json?["participantId"] as? String
            self.iceServers = (json?["config"] as? [String: Any])?["iceServers"] as? [[String: Any]]

            self.getLocalMedia()

            self.socket?.emit("join-call", [
                "callId": self.currentCallId!,
                "participantId": self.currentParticipantId!,
                "userName": userName
            ])

            completion(.success(json!))
        }.resume()
    }

    // MARK: - Media

    public func getLocalMedia() {
        let stream = factory.mediaStream(withStreamId: "local")

        let audioTrack = factory.audioTrack(withTrackId: "audio0")
        stream.addAudioTrack(audioTrack)

        let videoSource = factory.videoSource()
        let capturer = RTCCameraVideoCapturer(delegate: videoSource)
        let videoTrack = factory.videoTrack(with: videoSource, trackId: "video0")
        stream.addVideoTrack(videoTrack)

        localStream = stream
        delegate?.onLocalStream(stream)
    }

    // MARK: - Peer Connection

    private func createPeerConnection(participantId: String, isInitiator: Bool) {
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

        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)

        guard let pc = factory.peerConnection(with: config, constraints: constraints, delegate: self) else {
            delegate?.onError("Failed to create peer connection")
            return
        }

        peerConnections[participantId] = pc

        if let localStream = localStream {
            localStream.videoTracks.forEach { track in
                pc.add(track, streamIds: ["local"])
            }
            localStream.audioTracks.forEach { track in
                pc.add(track, streamIds: ["local"])
            }
        }

        if isInitiator {
            let offerConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
            pc.offer(for: offerConstraints) { [weak self, weak pc] sdp, error in
                guard let self, let pc, let sdp, error == nil else {
                    self?.delegate?.onError("Failed to create offer: \(error?.localizedDescription ?? "unknown")")
                    return
                }

                pc.setLocalDescription(sdp) { error in
                    if let error {
                        self.delegate?.onError("Failed to set local description: \(error.localizedDescription)")
                        return
                    }

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
        else { return }

        var pc = peerConnections[fromId]
        if pc == nil {
            createPeerConnection(participantId: fromId, isInitiator: false)
            pc = peerConnections[fromId]
        }

        guard let pc else { return }

        if type == "offer" {
            guard let signalData = data["signal"] as? [String: Any],
                  let sdpString = signalData["sdp"] as? String else { return }
            let sdp = RTCSessionDescription(type: .offer, sdp: sdpString)

            pc.setRemoteDescription(sdp) { [weak self] error in
                guard let self else { return }
                if let error {
                    self.delegate?.onError("Failed to set remote description: \(error.localizedDescription)")
                    return
                }

                let answerConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
                pc.answer(for: answerConstraints) { [weak self, weak pc] answer, error in
                    guard let self, let pc, let answer, error == nil else {
                        self?.delegate?.onError("Failed to create answer: \(error?.localizedDescription ?? "unknown")")
                        return
                    }

                    pc.setLocalDescription(answer) { error in
                        if let error {
                            self.delegate?.onError("Failed to set local description: \(error.localizedDescription)")
                            return
                        }

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
                  let sdpString = signalData["sdp"] as? String else { return }
            let sdp = RTCSessionDescription(type: .answer, sdp: sdpString)

            pc.setRemoteDescription(sdp) { [weak self] error in
                if let error {
                    self?.delegate?.onError("Failed to set remote description: \(error.localizedDescription)")
                }
            }
        } else if type == "ice-candidate" {
            guard let signalData = data["signal"] as? [String: Any],
                  let candidate = signalData["candidate"] as? String,
                  let sdpMLineIndex = signalData["sdpMLineIndex"] as? Int32 else { return }
            let c = RTCIceCandidate(sdp: candidate,
                                    sdpMLineIndex: sdpMLineIndex,
                                    sdpMid: signalData["sdpMid"] as? String)

            pc.add(c) { [weak self] error in
                if let error {
                    self?.delegate?.onError("Failed to add ICE candidate: \(error.localizedDescription)")
                }
            }
        }
    }

    private func removePeerConnection(participantId: String) {
        peerConnections[participantId]?.close()
        peerConnections.removeValue(forKey: participantId)
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

    public func leaveCall() {
        guard let callId = currentCallId else { return }
        socket?.emit("leave-call", ["callId": callId, "reason": "left"])
        peerConnections.values.forEach { $0.close() }
        peerConnections.removeAll()
        remoteStreams.removeAll()
        localStream = nil
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
    
    // MARK: - Media Stream Events
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        guard let participantId = peerConnections.first(where: { $0.value === peerConnection })?.key else {
            return
        }
        
        remoteStreams[participantId] = stream
        delegate?.onRemoteStream(participantId: participantId, stream: stream)
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        // Empty implementation is fine
    }
    
    // MARK: - ICE Candidate Events
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        guard let participantId = peerConnections.first(where: { $0.value === peerConnection })?.key else {
            return
        }
        
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
        
        print("PeerConnection [\(participantId)] → state: \(stateStr)")
        
        switch newState {
        case .failed, .disconnected:
            // Optional: Add reconnection logic or notify delegate
            break
        case .connected:
            // Optional: Notify success
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
        
        print("ICE Connection [\(participantId)] → \(stateStr)")
        
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
        print("Negotiation needed")
        // Optional: Trigger offer if needed
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        print("DataChannel opened: \(dataChannel.label ?? "unnamed")")
        // Optional: Handle data channel
    }
}