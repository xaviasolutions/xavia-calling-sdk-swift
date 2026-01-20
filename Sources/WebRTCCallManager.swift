import Foundation
import WebRTC

/// Manages WebRTC peer connections and SDP/ICE negotiation
public class WebRTCCallManager {
    
    // MARK: - Properties
    private let peerConnectionFactory: RTCPeerConnectionFactory
    private(set) var peerConnections: [String: RTCPeerConnection] = [:]
    private(set) var remoteStreams: [String: RTCMediaStream] = [:]
    
    private let queue = DispatchQueue(label: "com.xavia.webrtc", attributes: .concurrent)
    private let statsQueue = DispatchQueue(label: "com.xavia.webrtc.stats")
    
    var iceServers: [RTCIceServer] = []
    var currentCallId: String?
    var currentParticipantId: String?
    
    // MARK: - Callbacks
    public var onICECandidate: ((String, RTCIceCandidate) -> Void)?
    public var onRemoteStream: ((String, RTCMediaStream) -> Void)?
    public var onRemoteStreamRemoved: ((String) -> Void)?
    public var onConnectionStateChange: ((String, RTCPeerConnectionState) -> Void)?
    public var onSignalingStateChange: ((String, RTCSignalingState) -> Void)?
    public var onIceConnectionStateChange: ((String, RTCIceConnectionState) -> Void)?
    
    // MARK: - Initialization
    public init() {
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        self.peerConnectionFactory = RTCPeerConnectionFactory(
            encoderFactory: videoEncoderFactory,
            decoderFactory: videoDecoderFactory
        )
        print("✅ WebRTCCallManager initialized")
    }
    
    // MARK: - Configuration
    
    /// Configure ICE servers for STUN/TURN
    /// - Parameter servers: Array of ICE server configurations
    public func configureICEServers(_ servers: [ICEServer]) {
        queue.async(flags: .barrier) { [weak self] in
            self?.iceServers = servers.map { config in
                let iceServer = RTCIceServer(uris: config.urls)
                if let username = config.username {
                    iceServer.username = username
                }
                if let credential = config.credential {
                    iceServer.credential = credential
                }
                return iceServer
            }
            print("📡 ICE servers configured: \(servers.count)")
        }
    }
    
    // MARK: - Peer Connection Management
    
    /// Create a new peer connection
    /// - Parameters:
    ///   - participantId: Unique identifier for the participant
    ///   - isInitiator: Whether this peer will initiate the offer
    ///   - localStream: Local media stream to add to connection
    /// - Returns: Configured RTCPeerConnection
    public func createPeerConnection(
        participantId: String,
        isInitiator: Bool,
        localStream: RTCMediaStream?
    ) async throws -> RTCPeerConnection {
        return try await queue.async(flags: .barrier) { [weak self] in
            guard let self = self else {
                throw WebRTCError.deallocated
            }
            
            let constraints = RTCMediaConstraints(
                mandatoryConstraints: nil,
                optionalConstraints: nil
            )
            
            let rtcConfig = RTCConfiguration()
            rtcConfig.iceServers = self.iceServers.isEmpty ? [
                RTCIceServer(uris: ["stun:stun.l.google.com:19302"])
            ] : self.iceServers
            rtcConfig.bundlePolicy = .maxBundle
            rtcConfig.rtcpMuxPolicy = .require
            rtcConfig.tcpCandidatePolicy = .enabled
            rtcConfig.continualGatheringPolicy = .gatherContinually
            
            guard let peerConnection = self.peerConnectionFactory.peerConnection(
                with: rtcConfig,
                constraints: constraints,
                delegate: self
            ) else {
                throw WebRTCError.peerConnectionCreationFailed
            }
            
            // Add local stream
            if let localStream = localStream {
                localStream.audioTracks.forEach { peerConnection.add($0, streamIds: [localStream.streamId]) }
                localStream.videoTracks.forEach { peerConnection.add($0, streamIds: [localStream.streamId]) }
                print("➕ Added local stream to peer connection for \(participantId)")
            }
            
            self.peerConnections[participantId] = peerConnection
            
            print("🔗 Created peer connection with \(participantId), initiator: \(isInitiator)")
            
            if isInitiator {
                try await self.createAndSendOffer(participantId: participantId)
            }
            
            return peerConnection
        }
    }
    
    // MARK: - SDP Negotiation
    
    /// Create and send offer to remote peer
    private func createAndSendOffer(participantId: String) async throws {
        guard let peerConnection = peerConnections[participantId] else {
            throw WebRTCError.peerConnectionNotFound
        }
        
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue,
                kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueTrue
            ],
            optionalConstraints: nil
        )
        
        let offer = await createSessionDescription(
            peerConnection: peerConnection,
            type: .offer,
            constraints: constraints
        )
        
        await setLocalDescription(offer, for: peerConnection)
        
        print("📤 Created and set local offer for \(participantId)")
        onICECandidate?(participantId, offer as! RTCIceCandidate)
    }
    
    /// Handle incoming offer and send answer
    public func handleOffer(
        _ offer: RTCSessionDescription,
        from participantId: String,
        peerConnection: RTCPeerConnection?
    ) async throws {
        let pc = peerConnection ?? peerConnections[participantId]
        guard let pc = pc else {
            throw WebRTCError.peerConnectionNotFound
        }
        
        await setRemoteDescription(offer, for: pc)
        
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue,
                kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueTrue
            ],
            optionalConstraints: nil
        )
        
        let answer = await createSessionDescription(
            peerConnection: pc,
            type: .answer,
            constraints: constraints
        )
        
        await setLocalDescription(answer, for: pc)
        print("📤 Created and set local answer for \(participantId)")
    }
    
    /// Handle incoming answer
    public func handleAnswer(
        _ answer: RTCSessionDescription,
        from participantId: String
    ) async throws {
        guard let peerConnection = peerConnections[participantId] else {
            throw WebRTCError.peerConnectionNotFound
        }
        
        await setRemoteDescription(answer, for: peerConnection)
        print("✅ Set remote answer from \(participantId)")
    }
    
    /// Handle incoming ICE candidate
    public func addICECandidate(
        _ candidate: RTCIceCandidate,
        from participantId: String
    ) async throws {
        guard let peerConnection = peerConnections[participantId] else {
            throw WebRTCError.peerConnectionNotFound
        }
        
        do {
            try await peerConnection.add(candidate)
            print("✅ Added ICE candidate from \(participantId)")
        } catch {
            print("❌ Failed to add ICE candidate: \(error)")
            throw WebRTCError.iceAdditionFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Private Helper Methods
    
    private func createSessionDescription(
        peerConnection: RTCPeerConnection,
        type: RTCSessionDescriptionType,
        constraints: RTCMediaConstraints
    ) async -> RTCSessionDescription {
        return await withCheckedContinuation { continuation in
            if type == .offer {
                peerConnection.offer(for: constraints) { sdp, error in
                    guard let sdp = sdp, error == nil else {
                        print("❌ Failed to create offer: \(error?.localizedDescription ?? "unknown")")
                        return
                    }
                    continuation.resume(returning: sdp)
                }
            } else {
                peerConnection.answer(for: constraints) { sdp, error in
                    guard let sdp = sdp, error == nil else {
                        print("❌ Failed to create answer: \(error?.localizedDescription ?? "unknown")")
                        return
                    }
                    continuation.resume(returning: sdp)
                }
            }
        }
    }
    
    private func setLocalDescription(
        _ description: RTCSessionDescription,
        for peerConnection: RTCPeerConnection
    ) async {
        return await withCheckedContinuation { continuation in
            peerConnection.setLocalDescription(description) { error in
                if let error = error {
                    print("❌ Failed to set local description: \(error.localizedDescription)")
                } else {
                    print("✅ Local description set")
                }
                continuation.resume()
            }
        }
    }
    
    private func setRemoteDescription(
        _ description: RTCSessionDescription,
        for peerConnection: RTCPeerConnection
    ) async {
        return await withCheckedContinuation { continuation in
            peerConnection.setRemoteDescription(description) { error in
                if let error = error {
                    print("❌ Failed to set remote description: \(error.localizedDescription)")
                } else {
                    print("✅ Remote description set")
                }
                continuation.resume()
            }
        }
    }
    
    // MARK: - Cleanup
    
    /// Remove peer connection and clean up resources
    public func removePeerConnection(participantId: String) {
        queue.async(flags: .barrier) { [weak self] in
            if let peerConnection = self?.peerConnections.removeValue(forKey: participantId) {
                peerConnection.close()
                print("🔌 Closed peer connection with \(participantId)")
            }
            
            if let stream = self?.remoteStreams.removeValue(forKey: participantId) {
                print("🗑️ Removed remote stream from \(participantId)")
                self?.onRemoteStreamRemoved?(participantId)
            }
        }
    }
    
    /// Close all peer connections
    public func closeAllConnections() {
        queue.async(flags: .barrier) { [weak self] in
            self?.peerConnections.forEach { id, pc in
                pc.close()
                print("🔌 Closed peer connection with \(id)")
            }
            self?.peerConnections.removeAll()
            self?.remoteStreams.removeAll()
        }
    }
}

// MARK: - RTCPeerConnectionDelegate
extension WebRTCCallManager: RTCPeerConnectionDelegate {
    
    public func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didChange stateChanged: RTCSignalingState
    ) {
        queue.async { [weak self] in
            guard let participantId = self?.findParticipantId(for: peerConnection) else { return }
            print("🔄 Signaling state changed: \(stateChanged)")
            self?.onSignalingStateChange?(participantId, stateChanged)
        }
    }
    
    public func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didAdd stream: RTCMediaStream
    ) {
        queue.async { [weak self] in
            guard let participantId = self?.findParticipantId(for: peerConnection) else { return }
            self?.remoteStreams[participantId] = stream
            print("📥 Received remote stream from \(participantId)")
            self?.onRemoteStream?(participantId, stream)
        }
    }
    
    public func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didRemove stream: RTCMediaStream
    ) {
        queue.async { [weak self] in
            guard let participantId = self?.findParticipantId(for: peerConnection) else { return }
            self?.remoteStreams.removeValue(forKey: participantId)
            print("🗑️ Remote stream removed from \(participantId)")
            self?.onRemoteStreamRemoved?(participantId)
        }
    }
    
    public func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didGenerate candidate: RTCIceCandidate
    ) {
        queue.async { [weak self] in
            guard let participantId = self?.findParticipantId(for: peerConnection) else { return }
            print("📡 Generated ICE candidate for \(participantId)")
            self?.onICECandidate?(participantId, candidate)
        }
    }
    
    public func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didChange newState: RTCIceConnectionState
    ) {
        queue.async { [weak self] in
            guard let participantId = self?.findParticipantId(for: peerConnection) else { return }
            print("❄️ ICE connection state: \(newState.rawValue) for \(participantId)")
            self?.onIceConnectionStateChange?(participantId, newState)
        }
    }
    
    public func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didChange newState: RTCPeerConnectionState
    ) {
        queue.async { [weak self] in
            guard let participantId = self?.findParticipantId(for: peerConnection) else { return }
            print("🔗 Connection state: \(newState.rawValue) for \(participantId)")
            self?.onConnectionStateChange?(participantId, newState)
        }
    }
    
    public func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        print("🔄 Peer connection should negotiate")
    }
    
    public func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didRemove candidates: [RTCIceCandidate]
    ) {
        print("🗑️ ICE candidates removed: \(candidates.count)")
    }
    
    // MARK: - Helper Methods
    
    private func findParticipantId(for peerConnection: RTCPeerConnection) -> String? {
        return peerConnections.first { $0.value === peerConnection }?.key
    }
}

// MARK: - Error Types
enum WebRTCError: LocalizedError {
    case deallocated
    case peerConnectionCreationFailed
    case peerConnectionNotFound
    case iceAdditionFailed(String)
    case offerCreationFailed
    case answerCreationFailed
    case descriptionSetFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .deallocated:
            return "WebRTCCallManager was deallocated"
        case .peerConnectionCreationFailed:
            return "Failed to create peer connection"
        case .peerConnectionNotFound:
            return "Peer connection not found"
        case .iceAdditionFailed(let reason):
            return "Failed to add ICE candidate: \(reason)"
        case .offerCreationFailed:
            return "Failed to create offer"
        case .answerCreationFailed:
            return "Failed to create answer"
        case .descriptionSetFailed(let reason):
            return "Failed to set description: \(reason)"
        }
    }
}
