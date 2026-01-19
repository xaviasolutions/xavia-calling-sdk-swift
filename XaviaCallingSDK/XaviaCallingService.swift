// XaviaCallingService.swift

import Foundation
import WebRTC
import SocketIO
import AVFoundation

/// Singleton service handling WebRTC calls + Socket.IO signaling
public final class XaviaCallingService: NSObject {
    
    // MARK: - Singleton
    public static let shared = XaviaCallingService()
    private override init() {
        self.factory = RTCPeerConnectionFactory()
        super.init()
    }
    
    // MARK: - Properties
    private var socket: SocketIOClient?
    private var peerConnections: [String: RTCPeerConnection] = [:]           // participantId → PC
    private var localStream: RTCMediaStream?
    private var remoteStreams: [String: RTCMediaStream] = [:]
    private var currentCallId: String?
    private var currentParticipantId: String?
    private var userId: String?
    private var userName: String?
    private var iceServers: [RTCIceServer]?
    private var baseUrl: String?
    
    public weak var delegate: XaviaCallingDelegate?
    
    private let factory: RTCPeerConnectionFactory
    private var videoCapturer: RTCCameraVideoCapturer?
    private var videoSource: RTCVideoSource?
    
    // MARK: - Connection
    
    /// Connect to the signaling server and register user
    public func connect(serverUrl: String, userId: String, userName: String) async throws {
        self.baseUrl = serverUrl
        
        let trimmedName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw NSError(domain: "XaviaCalling", code: -1001, userInfo: [NSLocalizedDescriptionKey: "Username is required"])
        }
        
        if socket?.status == .connected, self.userId == userId {
            print("⚠️ Already connected with same user")
            return
        }
        
        if self.userId != userId {
            disconnect()
        }
        
        self.userId = userId
        self.userName = trimmedName
        
        print("🔌 Connecting to: \(serverUrl)")
        
        let manager = SocketManager(socketURL: URL(string: serverUrl)!,
                                    config: [.log(false),
                                             .transports([.websocket, .polling]),
                                             .reconnects(true),
                                             .reconnectAttempts(5),
                                             .reconnectWait(1)])
        
        socket = manager.defaultSocket
        
        try await withCheckedThrowingContinuation { continuation in
            socket?.on(clientEvent: .connect) { _, _ in
                print("✅ Connected: \(self.socket?.sid ?? "—")")
                self.socket?.emit("register-user", ["userId": userId, "userName": trimmedName])
                self.delegate?.connectionChanged(connected: true)
                continuation.resume()
            }
            
            socket?.on(clientEvent: .disconnect) { _, _ in
                print("❌ Disconnected")
                self.delegate?.connectionChanged(connected: false)
            }
            
            socket?.on(clientEvent: .error) { data, _ in
                let msg = (data.first as? String) ?? "Unknown error"
                print("Connection error: \(msg)")
                self.delegate?.didReceiveError("Connection failed: \(msg)")
                continuation.resume(throwing: NSError(domain: "XaviaCalling", code: -1002, userInfo: [NSLocalizedDescriptionKey: msg]))
            }
            
            setupSocketListeners()
            socket?.connect()
        }
    }
    
    private func setupSocketListeners() {
        socket?.on("users-online") { [weak self] data, _ in
            guard let self else { return }
            if let users = data.first as? [[String: Any]] {
                self.delegate?.didReceiveOnlineUsers(users)
            }
        }
        
        socket?.on("incoming-call") { [weak self] data, _ in
            if let payload = data.first as? [String: Any] {
                self?.delegate?.didReceiveIncomingCall(payload)
            }
        }
        
        socket?.on("call-accepted") { [weak self] data, _ in
            if let payload = data.first as? [String: Any] {
                self?.delegate?.didReceiveCallAccepted(payload)
            }
        }
        
        socket?.on("call-rejected") { [weak self] data, _ in
            if let payload = data.first as? [String: Any] {
                self?.delegate?.didReceiveCallRejected(payload)
            }
        }
        
        socket?.on("call-joined") { [weak self] data, _ in
            guard let self else { return }
            Task {
                guard let payload = data.first as? [String: Any],
                      let callId = payload["callId"] as? String,
                      let participants = payload["participants"] as? [[String: Any]] else { return }
                
                if let iceArray = payload["iceServers"] as? [[String: Any]] {
                    self.iceServers = iceArray.compactMap { RTCIceServer(dictionary: $0) }
                }
                
                for participant in participants {
                    if let id = participant["id"] as? String {
                        try? await self.createPeerConnection(participantId: id, isInitiator: true)
                    }
                }
            }
        }
        
        socket?.on("participant-joined") { [weak self] data, _ in
            Task {
                guard let self,
                      let payload = data.first as? [String: Any],
                      let participantId = payload["participantId"] as? String,
                      participantId != self.currentParticipantId else { return }
                
                try? await self.createPeerConnection(participantId: participantId, isInitiator: false)
                self.delegate?.didReceiveParticipantJoined(payload)
            }
        }
        
        socket?.on("participant-left") { [weak self] data, _ in
            if let payload = data.first as? [String: Any],
               let participantId = payload["participantId"] as? String {
                self?.removePeerConnection(participantId: participantId)
                self?.delegate?.didReceiveParticipantLeft(payload)
            }
        }
        
        socket?.on("signal") { [weak self] data, _ in
            Task {
                if let payload = data.first as? [String: Any] {
                    try? await self?.handleSignal(data: payload)
                }
            }
        }
        
        socket?.on("error") { [weak self] data, _ in
            if let payload = data.first as? [String: Any],
               let message = payload["message"] as? String {
                self?.delegate?.didReceiveError(message)
            }
        }
    }
    
    // MARK: - Call Management
    
    public func createCall(callType: String = "video", isGroup: Bool = false, maxParticipants: Int = 1000) async throws -> [String: Any] {
        guard let baseUrl else { throw NSError(domain: "XaviaCalling", code: -2001, userInfo: [NSLocalizedDescriptionKey: "Base URL not set"]) }
        
        let url = URL(string: "\(baseUrl)/api/calls")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["callType": callType, "isGroup": isGroup, "maxParticipants": maxParticipants]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        
        guard let success = json["success"] as? Bool, success else {
            let errorMsg = json["error"] as? String ?? "Failed to create call"
            throw NSError(domain: "XaviaCalling", code: -2002, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
        
        if let config = json["config"] as? [String: Any],
           let iceArray = config["iceServers"] as? [[String: Any]] {
            iceServers = iceArray.compactMap { RTCIceServer(dictionary: $0) }
        }
        
        return json
    }
    
    public func joinCall(callId: String) async throws -> [String: Any] {
        guard let baseUrl else { throw NSError(domain: "XaviaCalling", code: -2001, userInfo: [NSLocalizedDescriptionKey: "Base URL not set"]) }
        
        let url = URL(string: "\(baseUrl)/api/calls/\(callId)/join")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["userName": userName ?? "", "userId": userId ?? ""]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        
        guard let success = json["success"] as? Bool, success,
              let joinedCallId = json["callId"] as? String else {
            let errorMsg = json["error"] as? String ?? "Failed to join call"
            throw NSError(domain: "XaviaCalling", code: -2003, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
        
        currentCallId = joinedCallId
        currentParticipantId = json["participantId"] as? String
        
        if let config = json["config"] as? [String: Any],
           let iceArray = config["iceServers"] as? [[String: Any]] {
            iceServers = iceArray.compactMap { RTCIceServer(dictionary: $0) }
        }
        
        try await getLocalMedia()
        
        socket?.emit("join-call", [
            "callId": joinedCallId,
            "participantId": currentParticipantId ?? "",
            "userName": userName ?? ""
        ])
        
        return json
    }
    
    // MARK: - Media
    
    public func getLocalMedia() async throws {
        print("🎥 Getting local media...")
        
        // Audio
        let audioConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let audioSource = factory.audioSource(with: audioConstraints)
        let audioTrack = factory.audioTrack(with: audioSource, trackId: "audio0")
        
        // Video (front camera)
        videoSource = factory.videoSource()
        videoCapturer = RTCCameraVideoCapturer(delegate: videoSource!)
        
        guard let camera = RTCCameraVideoCapturer.captureDevices().first(where: { $0.position == .front }) else {
            throw NSError(domain: "XaviaCalling", code: -3001, userInfo: [NSLocalizedDescriptionKey: "No front camera available"])
        }
        
        let format = RTCCameraVideoCapturer.supportedFormats(for: camera).max(by: {
            let d1 = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
            let d2 = CMVideoFormatDescriptionGetDimensions($1.formatDescription)
            return d1.width * d1.height < d2.width * d2.height
        })
        
        guard let format else {
            throw NSError(domain: "XaviaCalling", code: -3002, userInfo: [NSLocalizedDescriptionKey: "No supported video format"])
        }
        
        try await videoCapturer?.startCapture(with: camera, format: format, fps: 30)
        
        let videoTrack = factory.videoTrack(with: videoSource!, trackId: "video0")
        
        let stream = factory.mediaStream(withStreamId: "local")
        stream.addAudioTrack(audioTrack)
        stream.addVideoTrack(videoTrack)
        
        localStream = stream
        delegate?.didReceiveLocalStream(stream)
        
        print("✅ Local media ready")
    }
    
    // MARK: - Peer Connection
    
    private func createPeerConnection(participantId: String, isInitiator: Bool) async throws {
        print("🔗 Creating PC → \(participantId) (initiator: \(isInitiator))")
        
        let config = RTCConfiguration()
        config.iceServers = iceServers ?? [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
        
        guard let pc = factory.peerConnection(with: config, constraints: nil, delegate: self) else {
            throw NSError(domain: "XaviaCalling", code: -4001, userInfo: [NSLocalizedDescriptionKey: "Failed to create peer connection"])
        }
        
        peerConnections[participantId] = pc
        
        if let local = localStream {
            for track in local.audioTracks + local.videoTracks {
                pc.add(track, streamIds: ["local"])
            }
        }
        
        if isInitiator {
            let offer = try await pc.offer(for: RTCMediaConstraints(mandatoryConstraints: ["OfferToReceiveAudio": "true", "OfferToReceiveVideo": "true"], optionalConstraints: nil))
            try await pc.setLocalDescription(offer)
            
            socket?.emit("signal", [
                "callId": currentCallId ?? "",
                "targetId": participantId,
                "signal": ["type": offer.type, "sdp": offer.sdp],
                "type": "offer"
            ])
        }
    }
    
    private func handleSignal(data: [String: Any]) async throws {
        guard let fromId = data["fromId"] as? String,
              let type = data["type"] as? String,
              let signal = data["signal"] as? [String: Any] else { return }
        
        var pc = peerConnections[fromId]
        if pc == nil {
            try await createPeerConnection(participantId: fromId, isInitiator: false)
            pc = peerConnections[fromId]
        }
        
        guard let pc else { return }
        
        switch type {
        case "offer":
            let desc = RTCSessionDescription(type: .offer, sdp: signal["sdp"] as? String ?? "")
            try await pc.setRemoteDescription(desc)
            
            let answer = try await pc.answer(for: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
            try await pc.setLocalDescription(answer)
            
            socket?.emit("signal", [
                "callId": currentCallId ?? "",
                "targetId": fromId,
                "signal": ["type": answer.type, "sdp": answer.sdp],
                "type": "answer"
            ])
            
        case "answer":
            let desc = RTCSessionDescription(type: .answer, sdp: signal["sdp"] as? String ?? "")
            try await pc.setRemoteDescription(desc)
            
        case "ice-candidate":
            guard let candidateStr = signal["candidate"] as? String,
                  let mid = signal["sdpMid"] as? String?,
                  let index = signal["sdpMLineIndex"] as? Int32 else { return }
            
            let candidate = RTCIceCandidate(sdp: candidateStr, sdpMLineIndex: index, sdpMid: mid)
            try await pc.add(candidate)
            
        default:
            break
        }
    }
    
    private func removePeerConnection(participantId: String) {
        peerConnections[participantId]?.close()
        peerConnections.removeValue(forKey: participantId)
        remoteStreams.removeValue(forKey: participantId)
        delegate?.didRemoveRemoteStream(for: participantId)
    }
    
    // MARK: - Call Control
    
    public func sendCallInvitation(targetUserId: String, callId: String, callType: String) async throws {
        try await withCheckedThrowingContinuation { cont in
            socket?.emitWithAck("send-call-invitation", [
                "targetUserId": targetUserId,
                "callId": callId,
                "callType": callType,
                "callerId": userId ?? "",
                "callerName": userName ?? ""
            ]) { ack in
                if let dict = ack.first as? [String: Any], let success = dict["success"] as? Bool, success {
                    cont.resume()
                } else {
                    let err = (ack.first as? [String: Any])?["error"] as? String ?? "Invitation failed"
                    cont.resume(throwing: NSError(domain: "XaviaCalling", code: -5001, userInfo: [NSLocalizedDescriptionKey: err]))
                }
            }
        }
    }
    
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
        
        videoCapturer?.stopCapture()
        videoCapturer = nil
        videoSource = nil
        localStream = nil
        
        currentCallId = nil
        currentParticipantId = nil
    }
    
    public func toggleAudio(enabled: Bool) {
        localStream?.audioTracks.forEach { $0.isEnabled = enabled }
    }
    
    public func toggleVideo(enabled: Bool) {
        localStream?.videoTracks.forEach { $0.isEnabled = enabled }
    }
    
    public func disconnect() {
        leaveCall()
        socket?.disconnect()
        socket = nil
    }
}

// MARK: - RTCPeerConnectionDelegate

extension XaviaCallingService: RTCPeerConnectionDelegate {
    public func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        guard let participantId = peerConnections.first(where: { $0.value === peerConnection })?.key else { return }
        
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
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        guard let participantId = peerConnections.first(where: { $0.value === peerConnection })?.key else { return }
        remoteStreams[participantId] = stream
        delegate?.didReceiveRemoteStream(stream, from: participantId)
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        // optional logging
    }
    
    // Minimal required stubs
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCSignalingState) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    public func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}

// MARK: - ICE Server Helper

extension RTCIceServer {
    convenience init?(dictionary: [String: Any]) {
        guard let urls = dictionary["urls"] as? [String] else { return nil }
        let username = dictionary["username"] as? String
        let credential = dictionary["credential"] as? String
        self.init(urlStrings: urls, username: username, credential: credential)
    }
}