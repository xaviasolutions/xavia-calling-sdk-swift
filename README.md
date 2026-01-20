# XaviaCallingSDK - iOS

A production-ready native iOS Swift SDK for WebRTC calling, built to mirror the functionality of the React Native WebRTC SDK.

## Features

- ✅ **Native WebRTC Support**: Full peer-to-peer video and audio calling
- ✅ **Multi-participant Calls**: Support for group calls with multiple participants
- ✅ **Thread-Safe**: Properly concurrent queue management for thread safety
- ✅ **Event-Driven**: Closure-based event callbacks for all state changes
- ✅ **Signaling Integration**: Socket.IO-based signaling with REST API support
- ✅ **Media Management**: Complete audio/video track control
- ✅ **No UI Dependency**: Pure utility SDK for integration into any app
- ✅ **Memory Safe**: Proper resource cleanup and memory management
- ✅ **iOS 13+**: Support for iPhone and iPad

## Installation

### Swift Package Manager

Add the package to your `Package.swift`:

```swift
.package(url: "https://github.com/yourusername/XaviaCallingSDK.git", branch: "main")
```

Or in Xcode:
1. File → Add Packages
2. Enter: `https://github.com/yourusername/XaviaCallingSDK.git`
3. Select version and add to target

## Quick Start

### 1. Initialize the SDK

```swift
import XaviaCallingSDK

let sdk = XaviaCallingSDK.shared

// Setup event handlers
sdk.onConnectionStateChanged = { isConnected in
    print("Connection state: \(isConnected)")
}

sdk.onLocalStreamReady = { stream in
    print("Local stream ready")
}

sdk.onRemoteStreamReceived = { participantId, stream in
    print("Remote stream received from: \(participantId)")
}

sdk.onError = { error in
    print("Error: \(error.localizedDescription)")
}

// Connect to server
try await sdk.initialize(
    serverUrl: "ws://your-server.com",
    userId: "user@example.com",
    userName: "John Doe"
)
```

### 2. Create a Call

```swift
// Create a new video call
let call = try await sdk.createCall(callType: "video", isGroup: false)
print("Call created with ID: \(call.callId)")

// Join the call
try await sdk.joinCall(
    callId: call.callId,
    userId: "user@example.com",
    userName: "John Doe"
)
```

### 3. Manage Calls

```swift
// Send invitation to another user
try await sdk.sendCallInvitation(
    targetUserId: "other_user_id",
    callId: callId,
    callType: "video",
    callerId: "user@example.com",
    callerName: "John Doe"
)

// Handle incoming call
sdk.onIncomingCall = { call in
    print("Incoming call from: \(call.callerName)")
    
    // Accept the call
    try await sdk.acceptCall(callId: call.callId, callerId: call.callerId)
    
    // Or reject it
    sdk.rejectCall(callId: call.callId, callerId: call.callerId)
}
```

### 4. Control Media

```swift
// Mute/unmute audio
sdk.setAudioEnabled(false)  // Mute
sdk.setAudioEnabled(true)   // Unmute

// Disable/enable video
sdk.setVideoEnabled(false)  // Disable camera
sdk.setVideoEnabled(true)   // Enable camera
```

### 5. End Call

```swift
// Leave and cleanup
await sdk.endCall()

// Disconnect from server
await sdk.disconnect()
```

## Event Callbacks

The SDK provides comprehensive event callbacks for all state changes:

```swift
// Connection events
sdk.onConnectionStateChanged = { isConnected in }

// Media events
sdk.onLocalStreamReady = { stream in }
sdk.onRemoteStreamReceived = { participantId, stream in }
sdk.onRemoteStreamRemoved = { participantId in }

// Call events
sdk.onIncomingCall = { call in }
sdk.onCallAccepted = { accepted in }
sdk.onCallRejected = { rejected in }
sdk.onParticipantJoined = { participant in }
sdk.onParticipantLeft = { participant in }

// Peer connection events
sdk.onPeerConnectionStateChanged = { participantId, state in }
sdk.onICEConnectionStateChanged = { participantId, state in }

// Online users
sdk.onOnlineUsersUpdated = { users in }

// Errors
sdk.onError = { error in }
```

## Architecture

### Components

```
XaviaCallingSDK (Main Entry Point)
├── SignalingService (REST + WebSocket)
├── WebRTCCallManager (Peer Connections)
└── MediaStreamManager (Audio/Video Tracks)
```

### Thread Safety

- All internal state is protected by concurrent dispatch queues
- Event callbacks are dispatched back on the main thread or specified queue
- Safe to call from any thread

### Memory Management

- Automatic cleanup of peer connections when call ends
- Proper resource deallocation of media streams
- No circular references between components

## API Reference

### XaviaCallingSDK

#### Initialization

```swift
func initialize(
    serverUrl: String,
    userId: String,
    userName: String
) async throws
```

Connect to the calling server.

#### Call Management

```swift
func createCall(
    callType: String = "video",
    isGroup: Bool = false,
    maxParticipants: Int = 1000
) async throws -> Call

func joinCall(
    callId: String,
    userId: String,
    userName: String
) async throws

func endCall() async

func sendCallInvitation(
    targetUserId: String,
    callId: String,
    callType: String,
    callerId: String,
    callerName: String
) async throws

func acceptCall(callId: String, callerId: String) async throws

func rejectCall(callId: String, callerId: String)
```

#### Media Control

```swift
func setAudioEnabled(_ enabled: Bool)

func setVideoEnabled(_ enabled: Bool)
```

#### State Queries

```swift
func getConnectionState() -> Bool

func getCurrentCallId() -> String?

func getCurrentParticipantId() -> String?

func getLocalStream() -> RTCMediaStream?

func getRemoteStream(participantId: String) -> RTCMediaStream?

func getAllRemoteStreams() -> [String: RTCMediaStream]
```

#### Connection

```swift
func disconnect() async
```

## Models

### Call
- `callId: String` - Unique call identifier
- `callType: String` - "video" or "audio"
- `isGroup: Bool` - Whether it's a group call
- `maxParticipants: Int` - Maximum participants allowed
- `config: WebRTCConfig` - WebRTC configuration

### Participant
- `id: String` - Participant identifier
- `name: String` - Participant name

### IncomingCall
- `callId: String` - Call identifier
- `callerId: String` - Caller's user ID
- `callerName: String` - Caller's display name
- `callType: String` - Type of call

### OnlineUser
- `userId: String` - User identifier
- `userName: String` - User display name

## Error Handling

All operations throw typed errors:

```swift
do {
    try await sdk.joinCall(...)
} catch let error as SignalingError {
    print("Signaling error: \(error)")
} catch let error as WebRTCError {
    print("WebRTC error: \(error)")
} catch let error as MediaStreamError {
    print("Media stream error: \(error)")
} catch {
    print("Unknown error: \(error)")
}
```

## Best Practices

1. **Always initialize before use**: Call `initialize()` before attempting calls
2. **Handle all callbacks**: Register error handlers to catch issues
3. **Clean up resources**: Call `disconnect()` when done with SDK
4. **Check connection state**: Use `getConnectionState()` before operations
5. **Handle media permissions**: App should request microphone/camera permissions
6. **Async/await only**: Don't use completion handlers; use async/await patterns

## Example App Structure

```swift
class CallingViewController {
    let sdk = XaviaCallingSDK.shared
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupSDK()
    }
    
    func setupSDK() {
        sdk.onConnectionStateChanged = { [weak self] isConnected in
            self?.updateUI(connected: isConnected)
        }
        
        sdk.onRemoteStreamReceived = { [weak self] participantId, stream in
            self?.displayRemoteStream(stream)
        }
        
        sdk.onError = { [weak self] error in
            self?.showError(error)
        }
        
        Task {
            try await sdk.initialize(
                serverUrl: AppConfig.serverUrl,
                userId: AppConfig.userId,
                userName: AppConfig.userName
            )
        }
    }
    
    func startCall(to userId: String) {
        Task {
            do {
                let call = try await sdk.createCall()
                try await sdk.sendCallInvitation(
                    targetUserId: userId,
                    callId: call.callId,
                    callType: "video",
                    callerId: AppConfig.userId,
                    callerName: AppConfig.userName
                )
            } catch {
                showError(error)
            }
        }
    }
    
    deinit {
        Task {
            await sdk.disconnect()
        }
    }
}
```

## Requirements

- iOS 13.0+
- Swift 5.9+
- WebRTC framework (automatically installed via SPM)
- Socket.IO client (automatically installed via SPM)

## Troubleshooting

### Connection fails
- Check server URL is correct
- Ensure backend is running
- Verify network connectivity

### No audio/video
- Check app permissions for microphone/camera
- Verify `onLocalStreamReady` is called
- Check media is enabled with `setAudioEnabled(true)`

### Peer connection fails
- Verify ICE servers are configured
- Check firewall/NAT settings
- Enable WebRTC stats logging

### Memory leaks
- Always call `disconnect()` when done
- Ensure callbacks are cleaned up
- Don't retain SDK references unnecessarily

## License

Proprietary - Xavia Inc.

## Support

For issues or questions, contact: support@xavia.io
