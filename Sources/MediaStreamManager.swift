import Foundation
import WebRTC

/// Manages media streams (audio/video) for local and remote participants
public class MediaStreamManager {
    
    // MARK: - Properties
    private let rtcAudioSession = RTCAudioSession.sharedInstance()
    private(set) var localStream: RTCMediaStream?
    private var videoTrack: RTCVideoTrack?
    private var audioTrack: RTCMediaAudioTrack?
    private var videoCapturer: RTCCameraCapturer?
    
    private let queue = DispatchQueue(label: "com.xavia.mediastream", attributes: .concurrent)
    
    // MARK: - Initialization
    public init() {
        setupAudioSession()
    }
    
    // MARK: - Audio Session Setup
    private func setupAudioSession() {
        rtcAudioSession.lockForConfiguration()
        defer { rtcAudioSession.unlockForConfiguration() }
        
        do {
            try rtcAudioSession.setCategory(
                AVAudioSession.Category.playAndRecord.rawValue,
                with: [.defaultToSpeaker, .duckOthers]
            )
            try rtcAudioSession.setMode(AVAudioSession.Mode.voiceChat.rawValue)
            try rtcAudioSession.setActive(true)
        } catch {
            print("❌ Failed to setup audio session: \(error)")
        }
    }
    
    // MARK: - Local Media Management
    
    /// Get local media stream with specified constraints
    /// - Parameters:
    ///   - videoEnabled: Enable video capture
    ///   - audioEnabled: Enable audio capture
    ///   - videoWidth: Preferred video width
    ///   - videoHeight: Preferred video height
    ///   - frameRate: Preferred frame rate
    /// - Returns: RTCMediaStream with configured tracks
    public func getLocalMedia(
        videoEnabled: Bool = true,
        audioEnabled: Bool = true,
        videoWidth: Int = 1280,
        videoHeight: Int = 720,
        frameRate: Int = 30
    ) async throws -> RTCMediaStream {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async(flags: .barrier) { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: MediaStreamError.deallocated)
                    return
                }
                
                let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
                let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
                let factory = RTCPeerConnectionFactory(
                    encoderFactory: videoEncoderFactory,
                    decoderFactory: videoDecoderFactory
                )
                let mediaStream = factory.mediaStream(withStreamId: UUID().uuidString)
                
                do {
                    if audioEnabled {
                        try self.addAudioTrack(to: mediaStream, using: factory)
                    }
                    
                    if videoEnabled {
                        try self.addVideoTrack(
                            to: mediaStream,
                            using: factory,
                            width: videoWidth,
                            height: videoHeight,
                            frameRate: frameRate
                        )
                    }
                    
                    self.localStream = mediaStream
                    print("✅ Local media obtained with \(mediaStream.audioTracks.count) audio and \(mediaStream.videoTracks.count) video tracks")
                    
                    continuation.resume(returning: mediaStream)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func addAudioTrack(to stream: RTCMediaStream, using factory: RTCPeerConnectionFactory) throws {
        let audioSource = factory.audioSource(with: RTCMediaConstraints())
        let audioTrack = factory.audioTrack(with: audioSource, trackId: "audio_\(UUID().uuidString)")
        stream.addAudioTrack(audioTrack)
        self.audioTrack = audioTrack
        print("➕ Added audio track")
    }
    
    private func addVideoTrack(
        to stream: RTCMediaStream,
        using factory: RTCPeerConnectionFactory,
        width: Int,
        height: Int,
        frameRate: Int
    ) throws {
        let videoSource = factory.videoSource()
        
        #if targetEnvironment(simulator)
        // For simulator, use custom frame source
        let videoCapturer = RTCFileVideoCapturer(delegate: videoSource)
        self.videoCapturer = videoCapturer
        #else
        // For device, use camera capturer
        guard let videoCapturer = RTCCameraCapturer(delegate: videoSource) else {
            throw MediaStreamError.videoCapturerInitializationFailed
        }
        self.videoCapturer = videoCapturer
        
        // Start capturing from front camera
        let devices = RTCCameraVideoCapturer.captureDevices()
        guard let frontCamera = devices.first(where: { $0.position == .front }) else {
            throw MediaStreamError.noCameraAvailable
        }
        
        let format = RTCCameraVideoCapturer.supportedFormats(for: frontCamera)
            .first(where: {
                let dimension = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
                return dimension.width >= Int32(width) && dimension.height >= Int32(height)
            }) ?? devices.first.map { RTCCameraVideoCapturer.supportedFormats(for: $0).last } ?? nil
        
        if let format = format {
            videoCapturer.startCapture(
                with: frontCamera,
                format: format,
                fps: frameRate
            ) { error in
                if let error = error {
                    print("❌ Camera capture error: \(error)")
                }
            }
        }
        #endif
        
        let videoTrack = factory.videoTrack(with: videoSource, trackId: "video_\(UUID().uuidString)")
        stream.addVideoTrack(videoTrack)
        self.videoTrack = videoTrack
        print("➕ Added video track")
    }
    
    // MARK: - Track Control
    
    /// Toggle audio track enabled state
    public func setAudioEnabled(_ enabled: Bool) {
        queue.async(flags: .barrier) { [weak self] in
            self?.localStream?.audioTracks.forEach { $0.isEnabled = enabled }
            print("🎤 Audio: \(enabled ? "enabled" : "disabled")")
        }
    }
    
    /// Toggle video track enabled state
    public func setVideoEnabled(_ enabled: Bool) {
        queue.async(flags: .barrier) { [weak self] in
            self?.localStream?.videoTracks.forEach { $0.isEnabled = enabled }
            print("📹 Video: \(enabled ? "enabled" : "disabled")")
        }
    }
    
    /// Stop all local media tracks
    public func stopLocalMedia() {
        queue.async(flags: .barrier) { [weak self] in
            self?.localStream?.audioTracks.forEach { $0.isEnabled = false }
            self?.localStream?.videoTracks.forEach { $0.isEnabled = false }
            
            #if !targetEnvironment(simulator)
            if let videoCapturer = self?.videoCapturer as? RTCCameraCapturer {
                videoCapturer.stopCapture()
            }
            #endif
            
            self?.localStream = nil
            self?.audioTrack = nil
            self?.videoTrack = nil
            print("⏹️ Local media stopped")
        }
    }
}

// MARK: - Error Types
enum MediaStreamError: LocalizedError {
    case deallocated
    case videoCapturerInitializationFailed
    case noCameraAvailable
    case audioSessionSetupFailed
    
    var errorDescription: String? {
        switch self {
        case .deallocated:
            return "MediaStreamManager was deallocated"
        case .videoCapturerInitializationFailed:
            return "Failed to initialize video capturer"
        case .noCameraAvailable:
            return "No camera available on device"
        case .audioSessionSetupFailed:
            return "Failed to setup audio session"
        }
    }
}
