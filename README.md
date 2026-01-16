# XaviaCallingSDK for iOS

A native iOS WebRTC calling SDK for seamless video and audio calling integration. Built with Swift, Xavia Calling SDK provides a complete solution for peer-to-peer and group video calling capabilities.

## Features

- 🎥 **HD Video Calling** - Crystal-clear video calling with adaptive bitrate
- 🎤 **Crystal Clear Audio** - Echo cancellation, noise suppression, and automatic gain control
- 👥 **Group Calling** - Support for multi-party video calls
- 🔗 **WebRTC P2P** - Direct peer-to-peer connections for low latency
- 📱 **Real-time Signaling** - Socket.IO based signaling for call management
- 🔒 **Native WebRTC** - Pure native implementation using GoogleWebRTC
- ⚡ **Async/Await** - Modern Swift concurrency patterns
- 🎯 **Easy Integration** - Simple, intuitive API design

## Minimum iOS Requirements

- **iOS 12.0** or higher
- **Swift 5.5** or higher (for async/await support)
- Xcode 13.0 or higher

## Installation Guide

### Using CocoaPods

1. **Add to Podfile**

   ```ruby
   pod 'XaviaCallingSDK'
   ```

2. **Install Dependencies**

   ```bash
   pod install
   ```

   The SDK automatically installs these dependencies:
   - `GoogleWebRTC` - WebRTC peer connections and media handling
   - `Socket.IO-Client-Swift` - Real-time bidirectional signaling

3. **Update Xcode Project**

   ```bash
   pod install --repo-update
   ```

## Required Info.plist Permissions

Add the following permissions to your app's `Info.plist` to enable camera and microphone access:

```xml
<key>NSCameraUsageDescription</key>
<string>This app needs access to your camera to make video calls.</string>

<key>NSMicrophoneUsageDescription</key>
<string>This app needs access to your microphone to make audio calls.</string>
```

Alternatively, in Xcode:
1. Select your target
2. Go to **Info** tab
3. Add two new rows:
   - **Privacy - Camera Usage Description** - "This app needs access to your camera to make video calls."
   - **Privacy - Microphone Usage Description** - "This app needs access to your microphone to make audio calls."

## Initialization Example

### 1. Import the SDK

```swift
import XaviaCallingSDK
```

### 2. Setup the Service and Delegate

```swift
class CallViewController: UIViewController, XaviaCallingDelegate {
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set the delegate to receive call events
        XaviaCallingService.shared.delegate = self
    }
}
```

### 3. Connect to the Backend

```swift
Task {
    do {
        try await XaviaCallingService.shared.connect(
            serverUrl: "https://your-backend-url.com",
            userId: "user-123",
            userName: "John Doe"
        )
        print("Connected successfully!")
    } catch {
        print("Connection failed: \(error)")
    }
}
```

## Full Usage Examples

### Connect to Backend

Establish a connection to your signaling server before initiating any calls.

```swift
Task {
    do {
        try await XaviaCallingService.shared.connect(
            serverUrl: "https://your-backend-url.com",
            userId: "user-123",
            userName: "John Doe"
        )
        // Connection established
    } catch {
        print("Failed to connect: \(error)")
    }
}
```

### Create Call

Create a new call on the server. This returns call metadata including the call ID.

```swift
Task {
    do {
        let callData = try await XaviaCallingService.shared.createCall(
            callType: "video",      // "video" or "audio"
            isGroup: false,         // Single or group call
            maxParticipants: 100    // Maximum participants allowed
        )
        
        if let callId = callData["callId"] as? String {
            print("Call created with ID: \(callId)")
            // Share callId with other participants
        }
    } catch {
        print("Failed to create call: \(error)")
    }
}
```

### Join Call

Join an existing call using the call ID. This automatically retrieves the local media stream.

```swift
Task {
    do {
        let joinData = try await XaviaCallingService.shared.joinCall(callId: "call-123")
        
        if let participantId = joinData["participantId"] as? String {
            print("Joined call with participant ID: \(participantId)")
        }
    } catch {
        print("Failed to join call: \(error)")
    }
}
```

### Send Call Invitation

Send a call invitation to a specific user.

```swift
Task {
    do {
        try await XaviaCallingService.shared.sendCallInvitation(
            targetUserId: "user-456",
            callId: "call-123",
            callType: "video"
        )
        print("Call invitation sent")
    } catch {
        print("Failed to send invitation: \(error)")
    }
}
```

### Accept Call

Accept an incoming call invitation.

```swift
// In your delegate method when receiving an incoming call
func onIncomingCall(_ data: [String: Any]) {
    if let callId = data["callId"] as? String,
       let callerId = data["callerId"] as? String {
        
        XaviaCallingService.shared.acceptCall(
            callId: callId,
            callerId: callerId
        )
    }
}
```

### Reject Call

Reject an incoming call invitation.

```swift
// In your delegate method when receiving an incoming call
func onIncomingCall(_ data: [String: Any]) {
    if let callId = data["callId"] as? String,
       let callerId = data["callerId"] as? String {
        
        XaviaCallingService.shared.rejectCall(
            callId: callId,
            callerId: callerId
        )
    }
}
```

### Leave Call

Leave the current call and clean up all peer connections.

```swift
XaviaCallingService.shared.leaveCall()
print("Left the call")
```

### Toggle Audio

Enable or disable the local audio track.

```swift
// Enable audio
XaviaCallingService.shared.toggleAudio(enabled: true)

// Disable audio (mute)
XaviaCallingService.shared.toggleAudio(enabled: false)
```

### Toggle Video

Enable or disable the local video track.

```swift
// Enable video
XaviaCallingService.shared.toggleVideo(enabled: true)

// Disable video (turn off camera)
XaviaCallingService.shared.toggleVideo(enabled: false)
```

## Delegate Implementation Example

Implement the `XaviaCallingDelegate` protocol to handle all call-related events:

```swift
class CallViewController: UIViewController, XaviaCallingDelegate {
    override func viewDidLoad() {
        super.viewDidLoad()
        XaviaCallingService.shared.delegate = self
    }
    
    /// Called when connection status changes
    func onConnectionChange(_ connected: Bool) {
        if connected {
            print("✅ Connected to signaling server")
            // Update UI to show connected state
        } else {
            print("❌ Disconnected from signaling server")
            // Update UI to show disconnected state
        }
    }
    
    /// Called when local media stream is obtained
    func onLocalStream(_ stream: RTCMediaStream) {
        print("📹 Local stream ready")
        // Render local video
        if let videoTrack = stream.videoTracks.first {
            // Set up video renderer for local stream
        }
    }
    
    /// Called when remote stream is received from a participant
    func onRemoteStream(participantId: String, stream: RTCMediaStream) {
        print("📹 Remote stream from \(participantId)")
        // Render remote video
        if let videoTrack = stream.videoTracks.first {
            // Set up video renderer for remote stream
        }
    }
    
    /// Called when remote stream is removed
    func onRemoteStreamRemoved(participantId: String) {
        print("🔇 Remote stream removed from \(participantId)")
        // Stop rendering remote video
    }
    
    /// Called with list of online users
    func onOnlineUsers(_ users: [[String: Any]]) {
        print("👥 Online users: \(users.count)")
        // Update UI with online users list
    }
    
    /// Called when incoming call invitation is received
    func onIncomingCall(_ data: [String: Any]) {
        if let callerId = data["callerId"] as? String,
           let callerName = data["callerName"] as? String,
           let callId = data["callId"] as? String {
            print("📞 Incoming call from \(callerName)")
            
            // Show incoming call UI
            showIncomingCallAlert(
                from: callerName,
                onAccept: {
                    XaviaCallingService.shared.acceptCall(
                        callId: callId,
                        callerId: callerId
                    )
                },
                onReject: {
                    XaviaCallingService.shared.rejectCall(
                        callId: callId,
                        callerId: callerId
                    )
                }
            )
        }
    }
    
    /// Called when call is accepted by recipient
    func onCallAccepted(_ data: [String: Any]) {
        print("✅ Call accepted by recipient")
        // Call established, update UI to show active call
    }
    
    /// Called when call is rejected by recipient
    func onCallRejected(_ data: [String: Any]) {
        print("❌ Call rejected by recipient")
        // Call rejected, update UI accordingly
    }
    
    /// Called when a new participant joins the call
    func onParticipantJoined(_ data: [String: Any]) {
        if let participantId = data["participantId"] as? String {
            print("➕ Participant joined: \(participantId)")
            // Update UI to show new participant
        }
    }
    
    /// Called when a participant leaves the call
    func onParticipantLeft(_ data: [String: Any]) {
        if let participantId = data["participantId"] as? String {
            print("➖ Participant left: \(participantId)")
            // Update UI to remove participant
        }
    }
    
    /// Called when an error occurs
    func onError(_ message: String) {
        print("⚠️ Error: \(message)")
        // Show error alert to user
        showErrorAlert(message: message)
    }
}
```

## Video Rendering Responsibility

**Important:** The SDK provides the media streams (`RTCMediaStream`) for both local and remote participants through the delegate callbacks, but **your application is responsible for rendering the video**.

### Rendering Local Video

When `onLocalStream` is called, extract the video track and render it using an `RTCVideoRenderer`:

```swift
import WebRTC

func onLocalStream(_ stream: RTCMediaStream) {
    if let videoTrack = stream.videoTracks.first {
        // Create an RTCCameraPreviewView for local video
        let localVideoView = RTCCameraPreviewView(frame: self.localVideoContainer.bounds)
        videoTrack.add(localVideoView)
        
        self.localVideoContainer.addSubview(localVideoView)
    }
}
```

### Rendering Remote Video

When `onRemoteStream` is called, extract the video track from the remote stream and render it:

```swift
func onRemoteStream(participantId: String, stream: RTCMediaStream) {
    if let videoTrack = stream.videoTracks.first {
        // Create an RTCEAGLVideoView or RTCMTLVideoView for remote video
        let remoteVideoView = RTCEAGLVideoView(frame: self.remoteVideoContainer.bounds)
        videoTrack.add(remoteVideoView)
        
        self.remoteVideoContainer.addSubview(remoteVideoView)
        
        // Store reference for later cleanup
        self.remoteVideoViews[participantId] = remoteVideoView
    }
}
```

### Cleaning Up Video Views

Remove video renderers when streams are removed:

```swift
func onRemoteStreamRemoved(participantId: String) {
    if let videoView = self.remoteVideoViews[participantId] {
        videoView.removeFromSuperview()
        self.remoteVideoViews.removeValue(forKey: participantId)
    }
}
```

### Common Video Rendering Options

The WebRTC framework provides several video view options:

- **RTCCameraPreviewView** - Optimized for local camera preview
- **RTCEAGLVideoView** - OpenGL-based rendering (good performance)
- **RTCMTLVideoView** - Metal-based rendering (better performance on newer devices)

Choose based on your target iOS versions and performance requirements.

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

## Support

For issues and support, contact: contact@xaviasolutions.com

## Developed by
xaviasolutions.com
