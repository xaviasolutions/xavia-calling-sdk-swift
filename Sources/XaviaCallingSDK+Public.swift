import Foundation

/// XaviaCallingSDK - Production-ready iOS WebRTC calling SDK
/// 
/// A native Swift SDK that provides complete WebRTC functionality for iOS applications.
/// This SDK handles peer connections, media streams, and signaling with a clean,
/// thread-safe API.
///
/// ## Usage Example
///
/// ```swift
/// import XaviaCallingSDK
///
/// // Initialize the SDK
/// let sdk = XaviaCallingSDK.shared
/// 
/// // Setup event handlers
/// sdk.onConnectionStateChanged = { isConnected in
///     print("Connected: \(isConnected)")
/// }
/// 
/// sdk.onRemoteStreamReceived = { participantId, stream in
///     // Handle incoming remote stream
/// }
/// 
/// // Connect to server
/// try await sdk.initialize(
///     serverUrl: "ws://your-server.com",
///     userId: "user123",
///     userName: "John Doe"
/// )
/// 
/// // Create or join a call
/// let call = try await sdk.createCall(callType: "video")
/// try await sdk.joinCall(
///     callId: call.callId,
///     userId: "user123",
///     userName: "John Doe"
/// )
/// 
/// // End the call
/// await sdk.endCall()
/// ```

// MARK: - Public API Exports

/// Main SDK class - access via `XaviaCallingSDK.shared`
public typealias CallingSDK = XaviaCallingSDK

/// Models
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
