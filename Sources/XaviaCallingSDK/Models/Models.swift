import Foundation
import GoogleWebRTC

// MARK: - Enums
public enum CallType: String, Codable {
    case video = "video"
    case audio = "audio"
}

public enum WebRTCError: Error {
    case missingConfiguration(String)
    case validationError(String)
    case notConnected
    case apiError(String)
    case socketError(String)
    case mediaError(String)
    case webRTCError(String)
}

// MARK: - Media Constraints
public struct MediaConstraints {
    public var video: VideoConstraints?
    public var audio: AudioConstraints?
    
    public init(video: VideoConstraints? = nil, audio: AudioConstraints? = nil) {
        self.video = video
        self.audio = audio
    }
}

public struct VideoConstraints {
    public var width: Int?
    public var height: Int?
    public var frameRate: Int?
    
    public init(width: Int? = nil, height: Int? = nil, frameRate: Int? = nil) {
        self.width = width
        self.height = height
        self.frameRate = frameRate
    }
}

public struct AudioConstraints {
    public var echoCancellation: Bool?
    public var noiseSuppression: Bool?
    public var autoGainControl: Bool?
    
    public init(echoCancellation: Bool? = nil, noiseSuppression: Bool? = nil, autoGainControl: Bool? = nil) {
        self.echoCancellation = echoCancellation
        self.noiseSuppression = noiseSuppression
        self.autoGainControl = autoGainControl
    }
}