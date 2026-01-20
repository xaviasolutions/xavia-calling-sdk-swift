# XaviaCallingSDK Implementation Guide

## Architecture Overview

This document explains the internal architecture and design decisions of XaviaCallingSDK.

### Component Hierarchy

```
┌─────────────────────────────────────────────────────────────────┐
│                    XaviaCallingSDK (Public API)                 │
│                      - Main entry point                         │
│                      - Orchestrates all components              │
│                      - Delegates to specialized managers        │
└─────────────────────────────────────────────────────────────────┘
           ↓              ↓                 ↓
  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐
  │  Signaling   │  │   WebRTC     │  │     Media        │
  │  Service     │  │   Call       │  │    Stream        │
  │              │  │   Manager    │  │    Manager       │
  │ - REST API   │  │              │  │                  │
  │ - WebSocket  │  │ - Peer Conn  │  │ - Audio tracks   │
  │ - Events     │  │ - SDP neg.   │  │ - Video tracks   │
  │              │  │ - ICE cands. │  │ - Constraints    │
  └──────────────┘  └──────────────┘  └──────────────────┘
```

### Data Flow

#### Connection Flow
```
User calls initialize()
    ↓
SignalingService connects to WebSocket
    ↓
Emits "register-user"
    ↓
Receives "users-online" event
    ↓
onConnected callback triggered
    ↓
SDK ready for calls
```

#### Call Creation Flow
```
User calls createCall()
    ↓
POST /api/calls → Backend
    ↓
Returns call ID + ICE servers
    ↓
WebRTCCallManager configures servers
    ↓
Returns Call model to user
```

#### Call Join Flow
```
User calls joinCall(callId)
    ↓
POST /api/calls/{id}/join → Backend
    ↓
Emits "join-call" socket event
    ↓
Backend broadcasts call-joined event
    ↓
onCallJoined triggered
    ↓
Create peer connections for existing participants
    ↓
Get local media stream
    ↓
createPeerConnection creates offer (if initiator)
```

#### Peer Connection Flow
```
createPeerConnection(participantId, isInitiator)
    ↓
Create RTCConfiguration with ICE servers
    ↓
Create RTCPeerConnection
    ↓
Add local stream tracks
    ↓
Setup ICE candidate handler → sends via signaling
    ↓
If initiator:
    - Create offer → set as local description
    - Send offer via signaling
Else:
    - Wait for offer from peer
```

#### Signaling Flow (Offer/Answer)
```
Receive "signal" event with offer
    ↓
handleSignal() called
    ↓
setRemoteDescription(offer)
    ↓
createAnswer()
    ↓
setLocalDescription(answer)
    ↓
Send answer back via signaling
    ↓
Receive "signal" event with answer
    ↓
setRemoteDescription(answer)
    ↓
Peer connection established!
```

## Thread Safety Model

### Dispatch Queues

Each component uses a dedicated concurrent dispatch queue:

```swift
// XaviaCallingSDK
operationQueue = DispatchQueue(label: "com.xavia.sdk", attributes: .concurrent)

// SignalingService
queue = DispatchQueue(label: "com.xavia.signaling", attributes: .concurrent)

// WebRTCCallManager
queue = DispatchQueue(label: "com.xavia.webrtc", attributes: .concurrent)

// MediaStreamManager
queue = DispatchQueue(label: "com.xavia.mediastream", attributes: .concurrent)
```

### State Protection

All mutable state is protected with concurrent queue barriers:

```swift
// Writing (requires barrier)
queue.async(flags: .barrier) {
    state = newValue
}

// Reading (concurrent)
queue.async {
    value = state
}
```

### Callback Threading

Event callbacks are invoked on the queue where they're triggered, which is typically a background queue. Callers should dispatch to main queue if UI updates needed:

```swift
sdk.onRemoteStreamReceived = { participantId, stream in
    DispatchQueue.main.async {
        // Update UI
        displayRemoteStream(stream)
    }
}
```

## Key Design Patterns

### 1. Async/Await Everywhere

No completion handlers, only `async/await`:

```swift
// ✅ Good
func joinCall(...) async throws

// ❌ Avoid
func joinCall(..., completion: @escaping (Result<Void, Error>) -> Void)
```

### 2. Event-Driven Architecture

State changes trigger callbacks:

```swift
// Model changes state
pc.onicecandidate = { candidate in
    // Notify listeners
    onICECandidate?(participantId, candidate)
}

// User listens
sdk.onICECandidate = { participantId, candidate in
    // React to change
}
```

### 3. Service Separation

Three independent services:

- **SignalingService**: Network communication only
- **WebRTCCallManager**: Peer connections only
- **MediaStreamManager**: Media streams only

Each can be tested independently.

### 4. Resource Cleanup

Explicit cleanup methods:

```swift
// Close connections
webrtcManager.closeAllConnections()

// Stop media
mediaManager.stopLocalMedia()

// Disconnect socket
signaling.disconnect()
```

## Error Handling

### Error Hierarchy

```
LocalizedError
├── SignalingError
│   ├── invalidURL
│   ├── socketCreationFailed
│   ├── notConnected
│   ├── httpError
│   ├── invalidResponse
│   └── serverError(String)
├── WebRTCError
│   ├── deallocated
│   ├── peerConnectionCreationFailed
│   ├── peerConnectionNotFound
│   ├── iceAdditionFailed(String)
│   └── descriptionSetFailed(String)
└── MediaStreamError
    ├── deallocated
    ├── videoCapturerInitializationFailed
    ├── noCameraAvailable
    └── audioSessionSetupFailed
```

### Error Propagation

1. **Sync operations**: Throw immediately
2. **Async operations**: Throw via async/await
3. **Callbacks**: Pass to `onError` callback

```swift
// Sync
try signaling.connect(...)

// Async
let response = try await signaling.joinCall(...)

// Callback
sdk.onError = { error in
    print("Error: \(error)")
}
```

## Performance Considerations

### 1. Memory Usage

- Peer connections are lazily created
- Remote streams are cached by participantId
- Media streams use weak references to avoid cycles

### 2. Network Optimization

- Reconnection with exponential backoff
- Polling fallback when WebSocket fails
- Minimal signaling messages

### 3. CPU Usage

- Concurrent queues prevent blocking
- Video encoding optimized by WebRTC
- Audio processing with echo cancellation

## Extending the SDK

### Adding New Events

1. Add callback property:
```swift
public var onCustomEvent: ((Data) -> Void)?
```

2. Trigger from appropriate component:
```swift
onCustomEvent?(data)
```

3. Document in README

### Adding New APIs

1. Add method to XaviaCallingSDK:
```swift
public func newAPI() async throws {
    // Implementation
}
```

2. Add underlying support in manager:
```swift
public func newAPIImpl() async throws {
    // Implementation
}
```

3. Add to public API exports

### Adding New Signal Types

1. Add case to `handleSignal()`:
```swift
case "new-signal":
    // Handle new signal type
```

2. Add corresponding socket event handler
3. Document signal format

## Testing Strategy

### Unit Tests

- Test models serialization/deserialization
- Test error handling
- Test state transitions

### Integration Tests

- Mock backend with test WebSocket server
- Test full call lifecycle
- Test multi-peer scenarios

### Example

```swift
func testJoinCall() async throws {
    let sdk = XaviaCallingSDK()
    try await sdk.initialize(serverUrl: mockURL, userId: "test", userName: "Test")
    
    let call = try await sdk.createCall()
    try await sdk.joinCall(callId: call.callId, userId: "test", userName: "Test")
    
    XCTAssertNotNil(sdk.getLocalStream())
}
```

## Debugging

### Enable Logging

The SDK uses `print()` for logging. Enable through console:

```
✅ Connected events
❌ Disconnected events
📞 Call events
📡 Signal events
🎥 Media events
⚠️ Warning events
```

### Common Issues

#### "Peer connection not found"
- Happens when receiving signal before peer connection created
- Solution: Ensure participants are created first

#### "Not connected to signaling server"
- Happens when calling joinCall before initialize
- Solution: Call initialize() first

#### "Audio session setup failed"
- Happens when app doesn't have audio permissions
- Solution: Request microphone permission

## Future Enhancements

- [ ] Screen sharing support
- [ ] Recording capability
- [ ] Simulcast for better multi-peer performance
- [ ] Metrics/stats collection
- [ ] Call history persistence
- [ ] Offline message queuing
- [ ] Encrypted signaling

## Version History

### 1.0.0 (Current)
- Initial release
- Core calling functionality
- Multi-participant support
- WebRTC peer connections
- Socket.IO signaling
