import Foundation
import WebRTC

protocol WebRTCManagerProtocol: AnyObject {
    func updateICEServers(_ iceServers: [ICEServer])
    func addLocalStream(_ stream: RTCMediaStream)
    func createPeerConnection(participantId: String, isInitiator: Bool) async
    func handleSignal(_ data: SignalData) async
    func removePeerConnection(participantId: String)
    func cleanup()
}

class WebRTCManager: NSObject, WebRTCManagerProtocol {
    private weak var webRTCService: WebRTCService?
    private var peerConnections: [String: RTCPeerConnection] = [:]
    private var localStream: RTCMediaStream?
    private var remoteStreams: [String: RTCMediaStream] = [:]
    
    private let factory: RTCPeerConnectionFactory
    private var iceServers: [RTCIceServer] = []
    
    private var currentCallId: String? {
        webRTCService?.currentCallId
    }
    
    private var currentParticipantId: String? {
        webRTCService?.currentParticipantId
    }
    
    init(webRTCService: WebRTCService) {
        self.webRTCService = webRTCService
        
        // Initialize WebRTC
        RTCInitializeSSL()
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        self.factory = RTCPeerConnectionFactory(
            encoderFactory: videoEncoderFactory,
            decoderFactory: videoDecoderFactory
        )
        
        super.init()
    }
    
    deinit {
        cleanup()
    }
    
    func updateICEServers(_ iceServers: [ICEServer]) {
        self.iceServers = iceServers.map { iceServer in
            RTCIceServer(
                urlStrings: iceServer.urls,
                username: iceServer.username ?? "",
                credential: iceServer.credential ?? ""
            )
        }
    }
    
    func addLocalStream(_ stream: RTCMediaStream) {
        self.localStream = stream
    }
    
    /// Create peer connection
    func createPeerConnection(participantId: String, isInitiator: Bool) async {
        Logger.log("🔗 Creating peer connection with \(participantId), initiator: \(isInitiator)")
        
        let config = RTCConfiguration()
        config.iceServers = iceServers.isEmpty ? 
            [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])] : 
            iceServers
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually
        config.bundlePolicy = .maxBundle
        config.rtcpMuxPolicy = .require
        config.tcpCandidatePolicy = .enabled
        
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue,
                kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueTrue
            ],
            optionalConstraints: nil
        )
        
        guard let pc = factory.peerConnection(with: config, constraints: constraints, delegate: self) else {
            Logger.error("Failed to create peer connection for \(participantId)")
            return
        }
        
        // Add local stream tracks
        if let localStream = localStream {
            for track in localStream.videoTracks {
                pc.add(track, streamIds: [localStream.streamId])
                Logger.log("➕ Added local video track to \(participantId)")
            }
            
            for track in localStream.audioTracks {
                pc.add(track, streamIds: [localStream.streamId])
                Logger.log("➕ Added local audio track to \(participantId)")
            }
        }
        
        peerConnections[participantId] = pc
        
        // If initiator, create and send offer
        if isInitiator {
            await createAndSendOffer(to: participantId)
        }
    }
    
    /// Handle incoming signals
    func handleSignal(_ data: SignalData) async {
        Logger.log("📡 Received signal from \(data.fromId): \(data.type.rawValue)")
        
        guard let pc = peerConnections[data.fromId] else {
            // Create peer connection if doesn't exist (for answering calls)
            await createPeerConnection(participantId: data.fromId, isInitiator: false)
            return
        }
        
        do {
            switch data.type {
            case .offer:
                try await handleOffer(data, peerConnection: pc)
            case .answer:
                try await handleAnswer(data, peerConnection: pc)
            case .iceCandidate:
                try await handleICECandidate(data, peerConnection: pc)
            }
        } catch {
            Logger.error("Handle signal error: \(error)")
        }
    }
    
    private func createAndSendOffer(to participantId: String) async {
        guard let pc = peerConnections[participantId],
              let callId = currentCallId,
              let fromId = currentParticipantId else {
            Logger.error("Missing required data for creating offer")
            return
        }
        
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue,
                kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueTrue
            ],
            optionalConstraints: nil
        )
        
        do {
            let offer = try await pc.offer(for: constraints)
            try await pc.setLocalDescription(offer)
            
            Logger.log("📤 Sending offer to \(participantId)")
            
            let signal = SignalData(
                fromId: fromId,
                targetId: participantId,
                callId: callId,
                signal: SignalPayload(
                    sdp: offer.sdp, 
                    type: String(offer.type.rawValue) 
                ),
                type: .offer
            )
            
            webRTCService?.sendSignal(signal)
        } catch {
            Logger.error("Create offer error for \(participantId): \(error)")
        }
    }
    
    private func handleOffer(_ data: SignalData, peerConnection: RTCPeerConnection) async throws {
        guard let sdpString = data.signal.sdp,
              let typeString = data.signal.type,
              let type = RTCSdpType.fromString(typeString) else {
            throw WebRTCError.webRTCError("Invalid SDP data in offer")
        }
        
        let sdp = RTCSessionDescription(type: type, sdp: sdpString)
        try await peerConnection.setRemoteDescription(sdp)
        
        let answer = try await peerConnection.answer(for: nil)
        try await peerConnection.setLocalDescription(answer)
        
        Logger.log("📤 Sending answer to \(data.fromId)")
        
        let signal = SignalData(
            fromId: currentParticipantId ?? "",
            targetId: data.fromId,
            callId: currentCallId,
            signal: SignalPayload(
                sdp: answer.sdp, 
                type: String(answer.type.rawValue)
            ),
            type: .answer
        )
        
        webRTCService?.sendSignal(signal)
    }
    
    private func handleAnswer(_ data: SignalData, peerConnection: RTCPeerConnection) async throws {
        guard let sdpString = data.signal.sdp,
              let typeString = data.signal.type,
              let type = RTCSdpType.fromString(typeString) else {
            throw WebRTCError.webRTCError("Invalid SDP data in answer")
        }
        
        let sdp = RTCSessionDescription(type: type, sdp: sdpString)
        try await peerConnection.setRemoteDescription(sdp)
    }
    
    private func handleICECandidate(_ data: SignalData, peerConnection: RTCPeerConnection) async throws {
        guard let candidate = data.signal.candidate,
              let sdpMid = data.signal.sdpMid,
              let sdpMLineIndex = data.signal.sdpMLineIndex else {
            return
        }
        
        let iceCandidate = RTCIceCandidate(
            sdp: candidate,
            sdpMLineIndex: Int32(sdpMLineIndex),
            sdpMid: sdpMid
        )
        
        try await peerConnection.add(iceCandidate)
    }
    
    /// Remove peer connection
    func removePeerConnection(participantId: String) {
        if let pc = peerConnections[participantId] {
            Logger.log("🗑️ Removing peer connection for \(participantId)")
            pc.close()
            peerConnections.removeValue(forKey: participantId)
        }
        
        if remoteStreams.removeValue(forKey: participantId) != nil {
            webRTCService?.onRemoteStreamRemoved(participantId: participantId)
        }
    }
    
    /// Cleanup all resources
    func cleanup() {
        Logger.log("🧹 Cleaning up WebRTC manager")
        
        for (participantId, pc) in peerConnections {
            Logger.log("Closing connection to \(participantId)")
            pc.close()
        }
        peerConnections.removeAll()
        remoteStreams.removeAll()
        localStream = nil
    }
}

// MARK: - RTCPeerConnectionDelegate
extension WebRTCManager: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        Logger.debug("Signaling state changed: \(stateChanged.rawValue)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        guard let participantId = peerConnections.first(where: { $0.value == peerConnection })?.key else {
            return
        }
        
        Logger.log("📥 Received remote stream from \(participantId)")
        remoteStreams[participantId] = stream
        webRTCService?.onRemoteStreamAdded(participantId: participantId, stream: stream)
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        guard let participantId = peerConnections.first(where: { $0.value == peerConnection })?.key else {
            return
        }
        
        Logger.log("Remote stream removed from \(participantId)")
        remoteStreams.removeValue(forKey: participantId)
        webRTCService?.onRemoteStreamRemoved(participantId: participantId)
    }
    
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        Logger.debug("Should negotiate")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        let stateString: String
        switch newState {
        case .new: stateString = "new"
        case .checking: stateString = "checking"
        case .connected: stateString = "connected"
        case .completed: stateString = "completed"
        case .failed: stateString = "failed"
        case .disconnected: stateString = "disconnected"
        case .closed: stateString = "closed"
        case .count: stateString = "count"
        @unknown default: stateString = "unknown"
        }
        
        if let participantId = peerConnections.first(where: { $0.value == peerConnection })?.key {
            Logger.log("❄️ ICE connection state with \(participantId): \(stateString)")
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        Logger.debug("ICE gathering state changed: \(newState.rawValue)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        guard let participantId = peerConnections.first(where: { $0.value == peerConnection })?.key,
              let callId = currentCallId,
              let fromId = currentParticipantId else {
            return
        }
        
        Logger.debug("📡 Sending ICE candidate to \(participantId)")
        
        let signal = SignalData(
            fromId: fromId,
            targetId: participantId,
            callId: callId,
            signal: SignalPayload(
                candidate: candidate.sdp,
                sdpMid: candidate.sdpMid,
                sdpMLineIndex: Int(candidate.sdpMLineIndex)
            ),
            type: .iceCandidate
        )
        
        webRTCService?.sendSignal(signal)
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        Logger.debug("Removed ICE candidates: \(candidates.count)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        Logger.log("Data channel opened")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        let stateString: String
        switch newState {
        case .new: stateString = "new"
        case .connecting: stateString = "connecting"
        case .connected: stateString = "connected"
        case .disconnected: stateString = "disconnected"
        case .failed: stateString = "failed"
        case .closed: stateString = "closed"
        @unknown default: stateString = "unknown"
        }
        
        if let participantId = peerConnections.first(where: { $0.value == peerConnection })?.key {
            Logger.log("🔗 Peer connection state with \(participantId): \(stateString)")
        }
    }
}

// MARK: - RTCSdpType Extension
extension RTCSdpType {
    static func fromString(_ string: String) -> RTCSdpType? {
        switch string.lowercased() {
        case "offer": return .offer
        case "answer": return .answer
        case "pranswer": return .prAnswer
        default: return nil
        }
    }
}