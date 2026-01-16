# XaviaCallingSDK Integration Guide

## Installation via CocoaPods

### 1. Add to Podfile
```ruby
pod 'XaviaCallingSDK'
```

### 2. Install Dependencies
```bash
pod install
```

This will automatically install:
- `GoogleWebRTC` - WebRTC peer connections
- `Socket.IO-Client-Swift` - Real-time signaling

## Basic Usage

### 1. Import the SDK
```swift
import XaviaCallingSDK
```

### 2. Set Up Delegate
```swift
class MyViewController: UIViewController, XaviaCallingDelegate {
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set delegate
        XaviaCallingService.shared.delegate = self
    }
    
    func onConnectionChange(_ connected: Bool) {
        print("Connected: \(connected)")
    }
    
    func onLocalStream(_ stream: RTCMediaStream) {
        print("Local stream ready")
    }
    
    func onRemoteStream(participantId: String, stream: RTCMediaStream) {
        print("Remote stream from \(participantId)")
    }
    
    func onError(_ message: String) {
        print("Error: \(message)")
    }
    
    // Implement other delegate methods as needed...
}
```

### 3. Connect to Server
```swift
Task {
    do {
        try await XaviaCallingService.shared.connect(
            serverUrl: "http://your-backend-url",
            userId: "user-123",
            userName: "John Doe"
        )
    } catch {
        print("Connection failed: \(error)")
    }
}
```

### 4. Create or Join Call
```swift
// Create call
let callData = try await XaviaCallingService.shared.createCall(
    callType: "video",
    isGroup: false
)
let callId = callData["callId"] as? String ?? ""

// OR Join existing call
try await XaviaCallingService.shared.joinCall(callId: callId)
```

### 5. Control Media
```swift
XaviaCallingService.shared.toggleAudio(enabled: true)
XaviaCallingService.shared.toggleVideo(enabled: true)
```

### 6. Leave Call
```swift
XaviaCallingService.shared.leaveCall()
```

## API Reference

### Connection Management
- `connect(serverUrl:userId:userName:)` - Connect to backend
- `disconnect()` - Disconnect from backend

### Call Management
- `createCall(callType:isGroup:maxParticipants:)` - Create new call
- `joinCall(callId:)` - Join existing call
- `leaveCall()` - Leave current call
- `sendCallInvitation(targetUserId:callId:callType:)` - Send call invitation
- `acceptCall(callId:callerId:)` - Accept incoming call
- `rejectCall(callId:callerId:)` - Reject incoming call

### Media Control
- `getLocalMedia(constraints:)` - Get local audio/video
- `toggleAudio(enabled:)` - Enable/disable audio
- `toggleVideo(enabled:)` - Enable/disable video

## Delegate Methods

All delegate methods are optional (have default implementations):

- `onConnectionChange(_:)` - Connection status changed
- `onLocalStream(_:)` - Local stream acquired
- `onRemoteStream(participantId:stream:)` - Remote stream received
- `onRemoteStreamRemoved(participantId:)` - Remote stream removed
- `onOnlineUsers(_:)` - Online users list updated
- `onIncomingCall(_:)` - Incoming call received
- `onCallAccepted(_:)` - Call accepted by recipient
- `onCallRejected(_:)` - Call rejected by recipient
- `onParticipantJoined(_:)` - Participant joined call
- `onParticipantLeft(_:)` - Participant left call
- `onError(_:)` - Error occurred

## Requirements

- iOS 12.0+
- Swift 5.0+
- Xcode 12.0+

## License

MIT
