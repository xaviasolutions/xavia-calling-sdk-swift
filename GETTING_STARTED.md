# XaviaCallingSDK - Getting Started Guide

## 📦 What You Have

A complete, production-ready native iOS Swift SDK for WebRTC calling that mirrors the React Native WebRTC SDK.

### Files Included

```
Sources/
├── XaviaCallingSDK.swift              (Main SDK - 400+ lines)
├── XaviaCallingSDK+Public.swift       (Public API exports)
├── SignalingService.swift             (WebSocket + REST - 400+ lines)
├── WebRTCCallManager.swift            (Peer connections - 500+ lines)
├── MediaStreamManager.swift           (Media streams - 300+ lines)
└── Models.swift                       (Data models - 300+ lines)

Documentation/
├── README.md                          (Quick start & API reference)
├── IMPLEMENTATION.md                  (Architecture deep dive)
├── EXAMPLES.md                        (Usage patterns)
├── DELIVERABLES.md                    (This summary)
└── Getting Started.md                 (This file)

Configuration/
├── Package.swift                      (SPM package config)
└── .gitignore                         (Git configuration)
```

## 🚀 Quick Start (5 minutes)

### 1. Add to Your Project

In your `Package.swift`:
```swift
dependencies: [
    .package(url: "https://github.com/yourusername/XaviaCallingSDK.git", branch: "main")
]
```

Or in Xcode:
- File → Add Packages
- Paste: `https://github.com/yourusername/XaviaCallingSDK.git`
- Select version and add to your target

### 2. Import and Initialize

```swift
import XaviaCallingSDK

class MyCallViewController {
    let sdk = XaviaCallingSDK.shared
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Setup event handlers
        sdk.onConnectionStateChanged = { isConnected in
            print("Connected: \(isConnected)")
        }
        
        sdk.onRemoteStreamReceived = { participantId, stream in
            print("Remote stream from: \(participantId)")
        }
        
        // Connect to server
        Task {
            try await sdk.initialize(
                serverUrl: "wss://your-server.com",
                userId: "user@example.com",
                userName: "John Doe"
            )
        }
    }
}
```

### 3. Create a Call

```swift
// Create new video call
let call = try await sdk.createCall(callType: "video")

// Join the call
try await sdk.joinCall(
    callId: call.callId,
    userId: "user@example.com",
    userName: "John Doe"
)
```

### 4. Handle Media

```swift
// Mute audio
sdk.setAudioEnabled(false)

// Disable video
sdk.setVideoEnabled(false)

// Get streams
if let localStream = sdk.getLocalStream() {
    print("Local stream: \(localStream)")
}
```

### 5. End Call

```swift
await sdk.endCall()
```

## 📚 Documentation Map

| Document | Purpose | When to Read |
|----------|---------|--------------|
| **README.md** | Feature overview & API reference | First thing to read |
| **EXAMPLES.md** | Copy-paste code examples | Implementing features |
| **IMPLEMENTATION.md** | Architecture & design | Understanding internals |
| **DELIVERABLES.md** | Feature checklist | Verification |
| **This file** | Quick setup | Now |

## 🔑 Key Concepts

### 1. Singleton Pattern
```swift
// Always use shared instance
let sdk = XaviaCallingSDK.shared
```

### 2. Async/Await Only
```swift
// ✅ Use async/await
try await sdk.joinCall(...)

// ❌ No completion handlers
sdk.joinCall(...) { result in ... }
```

### 3. Event-Driven
```swift
// Setup callbacks for all events
sdk.onRemoteStreamReceived = { participantId, stream in
    // Respond to events
}
```

### 4. Thread-Safe
```swift
// Safe to call from any thread
DispatchQueue.global().async {
    sdk.setAudioEnabled(false)  // Thread-safe
}
```

## 🎯 Common Tasks

### Making a 1-on-1 Call

```swift
// 1. Create call
let call = try await sdk.createCall(callType: "video", isGroup: false)

// 2. Send invitation
try await sdk.sendCallInvitation(
    targetUserId: "friend@example.com",
    callId: call.callId,
    callType: "video",
    callerId: "user@example.com",
    callerName: "John Doe"
)

// 3. Handle acceptance (on both sides)
sdk.onIncomingCall = { call in
    try await sdk.acceptCall(callId: call.callId, callerId: call.callerId)
}

// 4. Handle streams
sdk.onRemoteStreamReceived = { participantId, stream in
    // Display remote video
}

// 5. End call
await sdk.endCall()
```

### Joining a Group Call

```swift
// Join existing call
try await sdk.joinCall(
    callId: "call-id-123",
    userId: "user@example.com",
    userName: "John Doe"
)

// Get all participants' streams
for (participantId, stream) in sdk.getAllRemoteStreams() {
    print("Participant: \(participantId)")
}
```

### Handling Media

```swift
// Monitor and control media
sdk.onLocalStreamReady = { stream in
    print("Local media ready: \(stream.videoTracks.count) video")
}

sdk.setAudioEnabled(isAudioOn)
sdk.setVideoEnabled(isVideoOn)
```

## ⚙️ Configuration

### Server Setup

Your backend needs to support:
- WebSocket endpoint with Socket.IO
- REST endpoints: `POST /api/calls`, `POST /api/calls/:id/join`
- Signal events: `join-call`, `signal`, `participant-joined`, etc.

See the JS reference (`WebRTCService.js`) for exact protocol.

### Permissions

Request in your app (not in SDK):
```swift
// In Info.plist
<key>NSMicrophoneUsageDescription</key>
<string>We need microphone access for calls</string>
<key>NSCameraUsageDescription</key>
<string>We need camera access for video calls</string>
```

### Build Settings

No special build settings needed. SDK handles:
- Audio session configuration
- Audio routing
- Device permissions handling

## 🐛 Debugging

### Enable Logging

The SDK prints to console:
```
✅ Connected events
❌ Disconnected events
📞 Call events
📡 Signal events
🎥 Media events
⚠️ Warnings
❌ Errors
```

Monitor the console in Xcode.

### Common Issues

**Issue**: "Peer connection not found"
```swift
// Happens when signal arrives before peer connection created
// Solution: Ensure you're joining before signals arrive
```

**Issue**: "Not connected to signaling server"
```swift
// Solution: Call initialize() before other operations
```

**Issue**: "Audio session setup failed"
```swift
// Solution: Ensure app has microphone permissions
```

## 📊 Architecture Overview

```
Your App
    ↓
XaviaCallingSDK (Singleton)
    ├── SignalingService (REST + WebSocket)
    ├── WebRTCCallManager (Peer connections)
    └── MediaStreamManager (Audio/Video)
    ↓
Backend Server (WebSocket + REST)
```

Each layer is independent and thread-safe.

## 🧪 Testing

### Unit Test Example

```swift
import XCTest
import XaviaCallingSDK

class SDKTests: XCTestCase {
    let sdk = XaviaCallingSDK.shared
    
    func testInitialize() async throws {
        let expectation = XCTestExpectation()
        
        sdk.onConnectionStateChanged = { isConnected in
            if isConnected { expectation.fulfill() }
        }
        
        try await sdk.initialize(
            serverUrl: "wss://test.example.com",
            userId: "test@example.com",
            userName: "Test"
        )
        
        wait(for: [expectation], timeout: 5.0)
    }
}
```

## 📖 API Highlights

### Connection
```swift
try await sdk.initialize(serverUrl, userId, userName)
await sdk.disconnect()
```

### Calls
```swift
let call = try await sdk.createCall()
try await sdk.joinCall(callId, userId, userName)
await sdk.endCall()
```

### Invitations
```swift
try await sdk.sendCallInvitation(...)
try await sdk.acceptCall(callId, callerId)
sdk.rejectCall(callId, callerId)
```

### Media
```swift
sdk.setAudioEnabled(true/false)
sdk.setVideoEnabled(true/false)
```

### State
```swift
sdk.getConnectionState() -> Bool
sdk.getCurrentCallId() -> String?
sdk.getLocalStream() -> RTCMediaStream?
sdk.getRemoteStream(participantId) -> RTCMediaStream?
```

### Events
```swift
sdk.onConnectionStateChanged = { }
sdk.onLocalStreamReady = { }
sdk.onRemoteStreamReceived = { }
sdk.onIncomingCall = { }
sdk.onError = { }
// ... and many more
```

## 🔒 Security Notes

- All signaling over WebSocket (wss://) or REST (https://)
- Token/auth handled by your backend
- SDK doesn't validate certificates - app's URLSession config applies
- Peer connections use ICE candidates securely

## 📱 Compatibility

- **iOS**: 13.0+
- **Swift**: 5.9+
- **Xcode**: 14.0+
- **iPhone/iPad**: All models supported

## 🎓 Learning Path

1. **Start**: Read README.md quick start (10 min)
2. **Explore**: Copy example from EXAMPLES.md (10 min)
3. **Implement**: Add to your project (30 min)
4. **Debug**: Use console logging (as needed)
5. **Deep Dive**: Read IMPLEMENTATION.md (30 min)
6. **Advanced**: Use patterns from EXAMPLES.md (ongoing)

## ❓ FAQ

**Q: Can I use this in production?**
A: Yes, it's production-ready with comprehensive error handling.

**Q: Do I need UI components?**
A: No, the SDK is UI-agnostic. Use any UI framework you want.

**Q: How do I handle permissions?**
A: Request permissions in your app before calling SDK methods.

**Q: Can I customize video constraints?**
A: Yes, constraints can be passed to media methods.

**Q: How do I handle background mode?**
A: SDK handles audio sessions; your app handles background capabilities.

**Q: What if the connection drops?**
A: SDK auto-reconnects with exponential backoff, then calls `onError`.

## 📞 Support

For issues:
1. Check EXAMPLES.md for usage patterns
2. Check IMPLEMENTATION.md for architecture
3. Enable console logging to see detailed events
4. Review error descriptions in onError callback

## ✅ Checklist for Integration

- [ ] Add SDK to Package.swift
- [ ] Import XaviaCallingSDK
- [ ] Create XaviaCallingSDK.shared singleton
- [ ] Implement event callbacks
- [ ] Call initialize() first
- [ ] Handle permissions in app
- [ ] Test with real backend
- [ ] Handle errors in onError callback
- [ ] Test all media controls
- [ ] Test group calls if needed

## 🎉 You're Ready!

The SDK is ready to integrate. Start with README.md and EXAMPLES.md, then refer to IMPLEMENTATION.md as needed.

Good luck! 🚀
