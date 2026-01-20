import Foundation
import WebRTC
import AVFoundation

class MediaManager {
    private let factory: RTCPeerConnectionFactory
    private var localStream: RTCMediaStream?
    private var videoCapturer: RTCCameraVideoCapturer?
    
    init() {
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        self.factory = RTCPeerConnectionFactory(
            encoderFactory: videoEncoderFactory,
            decoderFactory: videoDecoderFactory
        )
    }
    
    func getLocalMediaStream(constraints: MediaConstraints? = nil) async throws -> RTCMediaStream {
        // Request permissions
        try await requestPermissions()
        
        // Create stream
        let streamId = UUID().uuidString
        let stream = factory.mediaStream(withStreamId: streamId)
        
        // Configure constraints
        let videoConstraints = constraints?.video
        let audioConstraints = constraints?.audio
        
        // Add audio track
        let audioTrack = createAudioTrack(constraints: audioConstraints)
        stream.addAudioTrack(audioTrack)
        
        // Add video track if video is enabled
        if videoConstraints != nil || constraints?.video == nil {
            let videoTrack = try await createVideoTrack(constraints: videoConstraints)
            stream.addVideoTrack(videoTrack)
        }
        
        self.localStream = stream
        return stream
    }
    
    private func requestPermissions() async throws {
        // Request audio permission
        let audioStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if audioStatus == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
        
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw WebRTCError.mediaError("Audio permission denied")
        }
        
        // Request video permission if we need video
        let videoStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if videoStatus == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            throw WebRTCError.mediaError("Video permission denied")
        }
    }
    
    private func createAudioTrack(constraints: AudioConstraints?) -> RTCAudioTrack {
        let audioConstraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: [
                "googEchoCancellation": constraints?.echoCancellation.map { $0 ? "true" : "false" } ?? "true",
                "googNoiseSuppression": constraints?.noiseSuppression.map { $0 ? "true" : "false" } ?? "true",
                "googAutoGainControl": constraints?.autoGainControl.map { $0 ? "true" : "false" } ?? "true"
            ]
        )
        
        let audioSource = factory.audioSource(with: audioConstraints)
        return factory.audioTrack(with: audioSource, trackId: "audio_\(UUID().uuidString)")
    }
    
    private func createVideoTrack(constraints: VideoConstraints?) async throws -> RTCVideoTrack {
        let videoSource = factory.videoSource()
        
        // Create capturer
        let capturer = RTCCameraVideoCapturer(delegate: videoSource)
        
        // Configure capture device
        guard let device = findBestCaptureDevice() else {
            throw WebRTCError.mediaError("No video capture device found")
        }
        
        let format = selectBestFormat(for: device, constraints: constraints)
        let fps = selectBestFPS(for: format, constraints: constraints)
        
        // Start capture
        capturer.startCapture(with: device, format: format, fps: fps)
        self.videoCapturer = capturer
        
        return factory.videoTrack(with: videoSource, trackId: "video_\(UUID().uuidString)")
    }
    
    private func findBestCaptureDevice() -> AVCaptureDevice? {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera, .builtInTrueDepthCamera],
            mediaType: .video,
            position: .front
        )
        
        return discoverySession.devices.first ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
    }
    
    private func selectBestFormat(for device: AVCaptureDevice, constraints: VideoConstraints?) -> AVCaptureDevice.Format {
        let formats = RTCCameraVideoCapturer.supportedFormats(for: device)
        
        // Default values if not specified
        let targetWidth = constraints?.width ?? 1280
        let targetHeight = constraints?.height ?? 720
        
        var bestFormat: AVCaptureDevice.Format?
        var bestDiff = Int.max
        var bestFps: Double = 0
        
        for format in formats {
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let diff = abs(Int(dimensions.width) - targetWidth) + abs(Int(dimensions.height) - targetHeight)
            
            // Get max fps for this format
            let fpsRange = format.videoSupportedFrameRateRanges
                .sorted(by: { $0.maxFrameRate > $1.maxFrameRate })
                .first
            
            let maxFps = fpsRange?.maxFrameRate ?? 0
            
            if diff < bestDiff || (diff == bestDiff && maxFps > bestFps) {
                bestDiff = diff
                bestFormat = format
                bestFps = maxFps
            }
        }
        
        return bestFormat ?? formats.last!
    }
    
    private func selectBestFPS(for format: AVCaptureDevice.Format, constraints: VideoConstraints?) -> Int {
        let targetFPS = constraints?.frameRate ?? 30
        let fpsRanges = format.videoSupportedFrameRateRanges
        
        var bestRange: AVFrameRateRange?
        var bestDiff = Int.max
        
        for range in fpsRanges {
            let rangeFPS = Int(range.maxFrameRate)
            let diff = abs(rangeFPS - targetFPS)
            
            if diff < bestDiff {
                bestDiff = diff
                bestRange = range
            }
        }
        
        return min(targetFPS, Int(bestRange?.maxFrameRate ?? 30))
    }
    
    func toggleAudio(enabled: Bool) {
        localStream?.audioTracks.forEach { $0.isEnabled = enabled }
    }
    
    func toggleVideo(enabled: Bool) {
        localStream?.videoTracks.forEach { $0.isEnabled = enabled }
        videoCapturer?.stopCapture()
        
        if enabled, let device = findBestCaptureDevice(),
           let format = selectBestFormat(for: device, constraints: nil),
           let fps = localStream?.videoTracks.first?.isEnabled == true ? selectBestFPS(for: format, constraints: nil) : 30 {
            videoCapturer?.startCapture(with: device, format: format, fps: fps)
        }
    }
    
    func switchCamera() {
        guard let capturer = videoCapturer else { return }
        
        let currentPosition = capturer.device?.position ?? .front
        let newPosition: AVCaptureDevice.Position = currentPosition == .front ? .back : .front
        
        guard let device = findCaptureDevice(position: newPosition),
              let format = selectBestFormat(for: device, constraints: nil),
              let fps = localStream?.videoTracks.first?.isEnabled == true ? selectBestFPS(for: format, constraints: nil) : 30 else {
            return
        }
        
        capturer.stopCapture()
        capturer.startCapture(with: device, format: format, fps: fps)
    }
    
    private func findCaptureDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera, .builtInTrueDepthCamera],
            mediaType: .video,
            position: position
        )
        
        return discoverySession.devices.first
    }
    
    func cleanup() {
        videoCapturer?.stopCapture()
        videoCapturer = nil
        
        localStream?.audioTracks.forEach { $0.isEnabled = false }
        localStream?.videoTracks.forEach { $0.isEnabled = false }
        localStream = nil
    }
}