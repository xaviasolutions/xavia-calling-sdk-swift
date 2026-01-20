# XaviaCallingSDK Examples

## Basic Usage

### Simple 1-on-1 Video Call

```swift
import XaviaCallingSDK

class VideoCallViewController {
    let sdk = XaviaCallingSDK.shared
    var remoteStream: RTCMediaStream?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupSDK()
        Task {
            await initializeSDK()
        }
    }
    
    func setupSDK() {
        // Connection events
        sdk.onConnectionStateChanged = { [weak self] isConnected in
            DispatchQueue.main.async {
                self?.updateConnectionStatus(isConnected)
            }
        }
        
        // Local media ready
        sdk.onLocalStreamReady = { [weak self] stream in
            DispatchQueue.main.async {
                self?.displayLocalStream(stream)
            }
        }
        
        // Remote stream received
        sdk.onRemoteStreamReceived = { [weak self] participantId, stream in
            self?.remoteStream = stream
            DispatchQueue.main.async {
                self?.displayRemoteStream(stream)
            }
        }
        
        // Remote stream removed
        sdk.onRemoteStreamRemoved = { [weak self] participantId in
            DispatchQueue.main.async {
                self?.remoteStream = nil
                self?.hideRemoteStream()
            }
        }
        
        // Participant joined
        sdk.onParticipantJoined = { [weak self] participant in
            DispatchQueue.main.async {
                self?.updateParticipantList()
            }
        }
        
        // Participant left
        sdk.onParticipantLeft = { [weak self] participant in
            DispatchQueue.main.async {
                self?.updateParticipantList()
            }
        }
        
        // Errors
        sdk.onError = { [weak self] error in
            DispatchQueue.main.async {
                self?.showError(error)
            }
        }
    }
    
    func initializeSDK() async {
        do {
            try await sdk.initialize(
                serverUrl: "wss://calling-server.example.com",
                userId: "user@example.com",
                userName: "John Doe"
            )
            print("✅ SDK initialized")
        } catch {
            showError(error)
        }
    }
    
    func startCall(with userId: String) {
        Task {
            do {
                // Create new call
                let call = try await sdk.createCall(
                    callType: "video",
                    isGroup: false
                )
                
                // Send invitation to other user
                try await sdk.sendCallInvitation(
                    targetUserId: userId,
                    callId: call.callId,
                    callType: "video",
                    callerId: "user@example.com",
                    callerName: "John Doe"
                )
                
                print("📞 Call invitation sent")
            } catch {
                showError(error)
            }
        }
    }
    
    func handleIncomingCall() {
        sdk.onIncomingCall = { [weak self] call in
            DispatchQueue.main.async {
                self?.showIncomingCallUI(call)
            }
        }
    }
    
    func acceptIncomingCall(callId: String, callerId: String) {
        Task {
            do {
                try await sdk.acceptCall(
                    callId: callId,
                    callerId: callerId
                )
                
                // Join the call
                try await sdk.joinCall(
                    callId: callId,
                    userId: "user@example.com",
                    userName: "John Doe"
                )
                
                print("✅ Joined call")
            } catch {
                showError(error)
            }
        }
    }
    
    func rejectIncomingCall(callId: String, callerId: String) {
        sdk.rejectCall(callId: callId, callerId: callerId)
        print("❌ Call rejected")
    }
    
    func toggleAudio(_ enabled: Bool) {
        sdk.setAudioEnabled(enabled)
        print("🎤 Audio: \(enabled ? "on" : "off")")
    }
    
    func toggleVideo(_ enabled: Bool) {
        sdk.setVideoEnabled(enabled)
        print("📹 Video: \(enabled ? "on" : "off")")
    }
    
    func endCall() {
        Task {
            await sdk.endCall()
            DispatchQueue.main.async {
                self?.clearUI()
            }
        }
    }
    
    deinit {
        Task {
            await sdk.disconnect()
        }
    }
    
    // MARK: - UI Methods
    
    func updateConnectionStatus(_ isConnected: Bool) {
        print("Connection: \(isConnected ? "✅ Connected" : "❌ Disconnected")")
    }
    
    func displayLocalStream(_ stream: RTCMediaStream) {
        print("📹 Local stream ready with \(stream.videoTracks.count) video track(s)")
    }
    
    func displayRemoteStream(_ stream: RTCMediaStream) {
        print("📹 Remote stream received with \(stream.videoTracks.count) video track(s)")
    }
    
    func hideRemoteStream() {
        print("🗑️ Remote stream removed")
    }
    
    func updateParticipantList() {
        print("👥 Participant list updated")
    }
    
    func showIncomingCallUI(_ call: IncomingCall) {
        print("📞 Incoming call from: \(call.callerName)")
    }
    
    func showError(_ error: Error) {
        print("❌ Error: \(error.localizedDescription)")
    }
    
    func clearUI() {
        print("🧹 UI cleared")
    }
}
```

## Group Calling

```swift
class GroupCallViewController {
    let sdk = XaviaCallingSDK.shared
    var participants: [String: RTCMediaStream] = [:]
    
    func setupGroupCall() {
        // Track all participants
        sdk.onParticipantJoined = { [weak self] participant in
            DispatchQueue.main.async {
                self?.addParticipantView(participant.participantId, name: participant.userName)
            }
        }
        
        sdk.onRemoteStreamReceived = { [weak self] participantId, stream in
            self?.participants[participantId] = stream
            DispatchQueue.main.async {
                self?.displayRemoteVideo(for: participantId, stream: stream)
            }
        }
        
        sdk.onParticipantLeft = { [weak self] participant in
            self?.participants.removeValue(forKey: participant.participantId)
            DispatchQueue.main.async {
                self?.removeParticipantView(participant.participantId)
            }
        }
    }
    
    func startGroupCall(with participantIds: [String]) {
        Task {
            do {
                // Create group call
                let call = try await sdk.createCall(
                    callType: "video",
                    isGroup: true,
                    maxParticipants: 10
                )
                
                // Invite all participants
                for participantId in participantIds {
                    try await sdk.sendCallInvitation(
                        targetUserId: participantId,
                        callId: call.callId,
                        callType: "video",
                        callerId: "user@example.com",
                        callerName: "John Doe"
                    )
                }
                
                // Join the call
                try await sdk.joinCall(
                    callId: call.callId,
                    userId: "user@example.com",
                    userName: "John Doe"
                )
                
                print("✅ Group call started")
            } catch {
                print("❌ Error: \(error)")
            }
        }
    }
    
    // MARK: - UI Methods
    
    func addParticipantView(_ participantId: String, name: String) {
        print("👤 Add view for: \(name)")
    }
    
    func displayRemoteVideo(for participantId: String, stream: RTCMediaStream) {
        print("📹 Display video for: \(participantId)")
    }
    
    func removeParticipantView(_ participantId: String) {
        print("🗑️ Remove view for: \(participantId)")
    }
}
```

## Event Handling Patterns

### 1. Connection Management

```swift
class ConnectionManager {
    let sdk = XaviaCallingSDK.shared
    
    func setupConnectionHandling() {
        sdk.onConnectionStateChanged = { [weak self] isConnected in
            if isConnected {
                self?.handleConnected()
            } else {
                self?.handleDisconnected()
            }
        }
        
        sdk.onError = { [weak self] error in
            self?.handleError(error)
        }
    }
    
    private func handleConnected() {
        print("✅ Connected to server")
        // Update UI, refresh user list, etc
    }
    
    private func handleDisconnected() {
        print("❌ Disconnected from server")
        // Show offline UI, attempt reconnect, etc
    }
    
    private func handleError(_ error: Error) {
        print("⚠️ Error: \(error.localizedDescription)")
        // Log error, show alert, etc
    }
}
```

### 2. Call State Machine

```swift
class CallStateManager {
    let sdk = XaviaCallingSDK.shared
    
    enum CallState {
        case idle
        case incoming(IncomingCall)
        case calling
        case connected
        case ended
    }
    
    var state = CallState.idle {
        didSet {
            handleStateChange(from: oldValue, to: state)
        }
    }
    
    func setupCallHandling() {
        sdk.onIncomingCall = { [weak self] call in
            self?.state = .incoming(call)
        }
        
        sdk.onCallAccepted = { [weak self] _ in
            self?.state = .connected
        }
        
        sdk.onCallRejected = { [weak self] _ in
            self?.state = .ended
        }
        
        sdk.onParticipantLeft = { [weak self] _ in
            if self?.sdk.getAllRemoteStreams().isEmpty == true {
                self?.state = .ended
            }
        }
    }
    
    private func handleStateChange(from: CallState, to: CallState) {
        print("📊 Call state: \(from) → \(to)")
    }
}
```

### 3. Media Control

```swift
class MediaController {
    let sdk = XaviaCallingSDK.shared
    private var audioEnabled = true
    private var videoEnabled = true
    
    func toggleAudio() {
        audioEnabled.toggle()
        sdk.setAudioEnabled(audioEnabled)
        print("🎤 Audio: \(audioEnabled ? "on" : "off")")
    }
    
    func toggleVideo() {
        videoEnabled.toggle()
        sdk.setVideoEnabled(videoEnabled)
        print("📹 Video: \(videoEnabled ? "on" : "off")")
    }
    
    func getAudioState() -> Bool {
        return audioEnabled
    }
    
    func getVideoState() -> Bool {
        return videoEnabled
    }
}
```

## Advanced Patterns

### 1. Call Logging

```swift
class CallLogger {
    let sdk = XaviaCallingSDK.shared
    var startTime: Date?
    var callId: String?
    
    func setupLogging() {
        sdk.onIncomingCall = { [weak self] call in
            self?.logEvent("incoming_call", parameters: [
                "callerId": call.callerId,
                "callerName": call.callerName
            ])
        }
        
        sdk.onRemoteStreamReceived = { [weak self] participantId, stream in
            self?.logEvent("remote_stream_received", parameters: [
                "participantId": participantId,
                "videoTracks": stream.videoTracks.count
            ])
        }
    }
    
    private func logEvent(_ event: String, parameters: [String: Any]) {
        print("📊 Event: \(event) - \(parameters)")
    }
}
```

### 2. Stream Management

```swift
class StreamManager {
    let sdk = XaviaCallingSDK.shared
    
    func getStreamStats(for participantId: String) -> StreamInfo? {
        guard let stream = sdk.getRemoteStream(participantId: participantId) else {
            return nil
        }
        
        return StreamInfo(
            participantId: participantId,
            hasVideo: !stream.videoTracks.isEmpty,
            hasAudio: !stream.audioTracks.isEmpty,
            videoTracks: stream.videoTracks.count,
            audioTracks: stream.audioTracks.count
        )
    }
    
    struct StreamInfo {
        let participantId: String
        let hasVideo: Bool
        let hasAudio: Bool
        let videoTracks: Int
        let audioTracks: Int
    }
}
```

### 3. Error Recovery

```swift
class ErrorRecovery {
    let sdk = XaviaCallingSDK.shared
    var retryCount = 0
    let maxRetries = 3
    
    func setupErrorHandling() {
        sdk.onError = { [weak self] error in
            self?.handleError(error)
        }
    }
    
    private func handleError(_ error: Error) {
        if retryCount < maxRetries {
            retryCount += 1
            print("🔄 Attempting retry \(retryCount)/\(maxRetries)")
            Task {
                try await Task.sleep(nanoseconds: UInt64(pow(2, Double(retryCount))) * 1_000_000_000)
                // Retry operation
            }
        } else {
            print("❌ Max retries exceeded")
            showFatalError(error)
        }
    }
    
    private func showFatalError(_ error: Error) {
        print("⚠️ Fatal error: \(error.localizedDescription)")
    }
}
```

## Testing Scenarios

### Mock Implementation for Testing

```swift
class MockXaviaCallingSDK {
    var isConnected = false
    var onConnectionStateChanged: ((Bool) -> Void)?
    
    func simulateConnection() {
        isConnected = true
        onConnectionStateChanged?(true)
    }
    
    func simulateDisconnection() {
        isConnected = false
        onConnectionStateChanged?(false)
    }
}
```

### Unit Test Example

```swift
import XCTest

class XaviaCallingSDKTests: XCTestCase {
    let sdk = XaviaCallingSDK.shared
    
    func testInitializeConnection() async throws {
        let expectation = XCTestExpectation(description: "SDK initializes")
        
        sdk.onConnectionStateChanged = { isConnected in
            if isConnected {
                expectation.fulfill()
            }
        }
        
        try await sdk.initialize(
            serverUrl: "wss://test-server.example.com",
            userId: "test@example.com",
            userName: "Test User"
        )
        
        wait(for: [expectation], timeout: 5.0)
    }
}
```

This covers common usage patterns and should help developers integrate XaviaCallingSDK into their applications.
