# XaviaCallingSDK - Public API Reference

## Main SDK Class: XaviaCallingSDK

### Singleton Access
```swift
let sdk = XaviaCallingSDK.shared
```

## Connection Management

### Initialize Connection
```swift
public func initialize(
    serverUrl: String,
    userId: String,
    userName: String
) async throws
```
Connects to the WebRTC calling server.

### Disconnect
```swift
public func disconnect() async
```
Disconnects from server and cleans up resources.

## Call Management

### Create Call
```swift
public func createCall(
    callType: String = "video",
    isGroup: Bool = false,
    maxParticipants: Int = 1000
) async throws -> Call
```
Creates a new call. Returns Call object with callId.

**Parameters:**
- `callType`: "video" or "audio"
- `isGroup`: Whether this is a group call
- `maxParticipants`: Maximum participants allowed

**Returns:** Call model containing callId and config

### Join Call
```swift
public func joinCall(
    callId: String,
    userId: String,
    userName: String
) async throws
```
Joins an existing call.

**Parameters:**
- `callId`: ID of the call to join
- `userId`: Current user's unique ID
- `userName`: Current user's display name

### End Call
```swift
public func endCall() async
```
Leaves the current call and cleans up all connections.

## Call Actions

### Send Call Invitation
```swift
public func sendCallInvitation(
    targetUserId: String,
    callId: String,
    callType: String,
    callerId: String,
    callerName: String
) async throws
```
Sends a call invitation to another user.

**Parameters:**
- `targetUserId`: User to invite
- `callId`: Call ID to invite to
- `callType`: "video" or "audio"
- `callerId`: Current user's ID
- `callerName`: Current user's display name

### Accept Call
```swift
public func acceptCall(
    callId: String,
    callerId: String
) async throws
```
Accepts an incoming call invitation.

**Parameters:**
- `callId`: ID of the call to accept
- `callerId`: ID of the caller

### Reject Call
```swift
public func rejectCall(
    callId: String,
    callerId: String
)
```
Rejects an incoming call invitation.

**Parameters:**
- `callId`: ID of the call to reject
- `callerId`: ID of the caller

## Media Control

### Set Audio Enabled
```swift
public func setAudioEnabled(_ enabled: Bool)
```
Enables or disables audio transmission.

**Parameters:**
- `enabled`: true to enable, false to mute

### Set Video Enabled
```swift
public func setVideoEnabled(_ enabled: Bool)
```
Enables or disables video transmission.

**Parameters:**
- `enabled`: true to enable, false to disable camera

## State Queries

### Get Connection State
```swift
public func getConnectionState() -> Bool
```
Returns true if connected to server, false otherwise.

### Get Current Call ID
```swift
public func getCurrentCallId() -> String?
```
Returns the ID of the current call or nil.

### Get Current Participant ID
```swift
public func getCurrentParticipantId() -> String?
```
Returns the current participant ID in the call or nil.

### Get Local Stream
```swift
public func getLocalStream() -> RTCMediaStream?
```
Returns the local media stream or nil if not available.

### Get Remote Stream
```swift
public func getRemoteStream(participantId: String) -> RTCMediaStream?
```
Returns the remote stream for a specific participant.

**Parameters:**
- `participantId`: ID of the participant

### Get All Remote Streams
```swift
public func getAllRemoteStreams() -> [String: RTCMediaStream]
```
Returns a dictionary of all participant IDs to their streams.

## Event Callbacks

### Connection Events

```swift
public var onConnectionStateChanged: ((Bool) -> Void)?
```
Called when connection to server changes. Parameter is true for connected, false for disconnected.

### Media Events

```swift
public var onLocalStreamReady: ((RTCMediaStream) -> Void)?
```
Called when local media stream (audio/video) is ready.

```swift
public var onRemoteStreamReceived: ((String, RTCMediaStream) -> Void)?
```
Called when remote stream is received. Parameters are participantId and stream.

```swift
public var onRemoteStreamRemoved: ((String) -> Void)?
```
Called when remote stream is removed. Parameter is participantId.

### Call Events

```swift
public var onIncomingCall: ((IncomingCall) -> Void)?
```
Called when incoming call is received. Parameter contains call details.

```swift
public var onCallAccepted: ((CallAccepted) -> Void)?
```
Called when sent call is accepted by recipient.

```swift
public var onCallRejected: ((CallRejected) -> Void)?
```
Called when sent call is rejected by recipient.

### Participant Events

```swift
public var onParticipantJoined: ((ParticipantJoined) -> Void)?
```
Called when new participant joins the call.

```swift
public var onParticipantLeft: ((ParticipantLeft) -> Void)?
```
Called when participant leaves the call.

### User Events

```swift
public var onOnlineUsersUpdated: (([OnlineUser]) -> Void)?
```
Called when list of online users is updated.

### Peer Connection Events

```swift
public var onPeerConnectionStateChanged: ((String, RTCPeerConnectionState) -> Void)?
```
Called when peer connection state changes. Parameters are participantId and state.

```swift
public var onICEConnectionStateChanged: ((String, RTCIceConnectionState) -> Void)?
```
Called when ICE connection state changes. Parameters are participantId and state.

### Error Event

```swift
public var onError: ((Error) -> Void)?
```
Called when an error occurs anywhere in the SDK.

## Data Models

### Call
```swift
public struct Call {
    public let callId: String
    public let callType: String
    public let isGroup: Bool
    public let maxParticipants: Int
    public let config: WebRTCConfig
}
```

### Participant
```swift
public struct Participant {
    public let id: String
    public let name: String
}
```

### OnlineUser
```swift
public struct OnlineUser {
    public let userId: String
    public let userName: String
}
```

### IncomingCall
```swift
public struct IncomingCall {
    public let callId: String
    public let callerId: String
    public let callerName: String
    public let callType: String
}
```

### CallAccepted
```swift
public struct CallAccepted {
    public let callId: String
    public let acceptedById: String
    public let acceptedByName: String
}
```

### CallRejected
```swift
public struct CallRejected {
    public let callId: String
    public let rejectedById: String
    public let rejectedByName: String
}
```

### ParticipantJoined
```swift
public struct ParticipantJoined {
    public let callId: String
    public let participantId: String
    public let userName: String
}
```

### ParticipantLeft
```swift
public struct ParticipantLeft {
    public let callId: String
    public let participantId: String
}
```

### WebRTCConfig
```swift
public struct WebRTCConfig {
    public let iceServers: [ICEServer]
}
```

### ICEServer
```swift
public struct ICEServer {
    public let urls: [String]
    public let username: String?
    public let credential: String?
}
```

### JoinCallResponse
```swift
public struct JoinCallResponse {
    public let success: Bool
    public let callId: String
    public let participantId: String
    public let participants: [Participant]
    public let config: WebRTCConfig
    public let error: String?
}
```

## Error Types

### SignalingError
```swift
public enum SignalingError: LocalizedError {
    case invalidURL
    case socketCreationFailed
    case notConnected
    case httpError
    case invalidResponse
    case serverError(String)
}
```

### WebRTCError
```swift
public enum WebRTCError: LocalizedError {
    case deallocated
    case peerConnectionCreationFailed
    case peerConnectionNotFound
    case iceAdditionFailed(String)
    case offerCreationFailed
    case answerCreationFailed
    case descriptionSetFailed(String)
}
```

### MediaStreamError
```swift
public enum MediaStreamError: LocalizedError {
    case deallocated
    case videoCapturerInitializationFailed
    case noCameraAvailable
    case audioSessionSetupFailed
}
```

## Type Aliases (for convenience)

```swift
public typealias CallingSDK = XaviaCallingSDK
public typealias WebRTCCallConfig = WebRTCConfig
public typealias IceServerConfig = ICEServer
public typealias CallInfo = Call
public typealias JoinCallInfo = JoinCallResponse
public typealias UserInfo = OnlineUser
public typealias CallInvitation = IncomingCall
public typealias AcceptedCall = CallAccepted
public typealias RejectedCall = CallRejected
public typealias JoinedParticipant = ParticipantJoined
public typealias LeftParticipant = ParticipantLeft
public typealias WebRTCSignal = Signal
public typealias SignalData = SignalPayload
```

## WebRTC Types (from WebRTC framework)

The SDK uses these WebRTC types (re-exported from WebRTC framework):

- `RTCMediaStream` - Media stream (audio + video)
- `RTCVideoTrack` - Video track
- `RTCMediaAudioTrack` - Audio track
- `RTCPeerConnection` - Peer connection
- `RTCSessionDescription` - SDP offer/answer
- `RTCIceCandidate` - ICE candidate
- `RTCPeerConnectionState` - Connection state enum
- `RTCIceConnectionState` - ICE connection state enum

## Thread Safety

All public methods are thread-safe and can be called from any thread:

```swift
// Safe from any queue
DispatchQueue.global().async {
    sdk.setAudioEnabled(false)
    sdk.setVideoEnabled(false)
}

// Safe from main queue
DispatchQueue.main.async {
    let state = sdk.getConnectionState()
}
```

## Async/Await Pattern

All network operations use async/await:

```swift
// Must be called from async context or Task
Task {
    try await sdk.initialize(...)
    let call = try await sdk.createCall()
    try await sdk.joinCall(...)
}
```

## Closure Callbacks

All event callbacks are closure-based and dispatched to the queue where the event occurred:

```swift
// For UI updates, dispatch to main queue
sdk.onRemoteStreamReceived = { participantId, stream in
    DispatchQueue.main.async {
        // Update UI
    }
}
```

## Complete Usage Example

```swift
import XaviaCallingSDK

class CallViewController {
    let sdk = XaviaCallingSDK.shared
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCallHandling()
        connectAndCall()
    }
    
    func setupCallHandling() {
        sdk.onConnectionStateChanged = { isConnected in
            print("Connected: \(isConnected)")
        }
        
        sdk.onRemoteStreamReceived = { participantId, stream in
            print("Remote stream: \(participantId)")
        }
        
        sdk.onError = { error in
            print("Error: \(error)")
        }
    }
    
    func connectAndCall() {
        Task {
            do {
                // Connect
                try await sdk.initialize(
                    serverUrl: "wss://server.example.com",
                    userId: "user@example.com",
                    userName: "John Doe"
                )
                
                // Create call
                let call = try await sdk.createCall()
                
                // Join call
                try await sdk.joinCall(
                    callId: call.callId,
                    userId: "user@example.com",
                    userName: "John Doe"
                )
                
                // Control media
                sdk.setAudioEnabled(true)
                sdk.setVideoEnabled(true)
                
            } catch {
                print("Error: \(error)")
            }
        }
    }
    
    deinit {
        Task {
            await sdk.endCall()
            await sdk.disconnect()
        }
    }
}
```

---

This is the complete public API. All other classes and methods are internal implementation details.
