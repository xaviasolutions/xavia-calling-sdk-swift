import Foundation
import SocketIO

/// Handles all signaling via REST API and WebSocket (Socket.IO)
public class SignalingService {
    
    // MARK: - Properties
    private let urlSession: URLSession
    private var manager: SocketManager?
    private var socket: SocketIOClient?
    private var baseUrl: String?
    
    private let queue = DispatchQueue(label: "com.xavia.signaling", attributes: .concurrent)
    
    // MARK: - Socket State
    private var isConnected = false
    
    // MARK: - Callbacks
    public var onConnected: (() -> Void)?
    public var onDisconnected: (() -> Void)?
    public var onUsersOnline: (([OnlineUser]) -> Void)?
    public var onIncomingCall: ((IncomingCall) -> Void)?
    public var onCallAccepted: ((CallAccepted) -> Void)?
    public var onCallRejected: ((CallRejected) -> Void)?
    public var onCallJoined: ((JoinCallResponse) -> Void)?
    public var onParticipantJoined: ((ParticipantJoined) -> Void)?
    public var onParticipantLeft: ((ParticipantLeft) -> Void)?
    public var onSignal: ((Signal) -> Void)?
    public var onError: ((String) -> Void)?
    
    // MARK: - Initialization
    public init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        self.urlSession = URLSession(configuration: configuration)
    }
    
    // MARK: - Connection Management
    
    /// Connect to WebSocket server and authenticate
    /// - Parameters:
    ///   - serverUrl: Backend server URL
    ///   - userId: User identifier
    ///   - userName: User name
    public func connect(serverUrl: String, userId: String, userName: String) async throws {
        try await queue.async(flags: .barrier) { [weak self] in
            self?.baseUrl = serverUrl
            
            // Disconnect existing connection
            await self?.disconnect()
            
            // Setup Socket.IO
            guard let url = URL(string: serverUrl) else {
                throw SignalingError.invalidURL
            }
            
            let manager = SocketManager(socketURL: url, config: [
                .log(true),
                .compress,
                .reconnects(true),
                .reconnectAttempts(5),
                .reconnectWait(1),
                .reconnectWaitMax(5),
                .forceWebsockets(false)
            ])
            
            guard let socket = manager.defaultSocket else {
                throw SignalingError.socketCreationFailed
            }
            
            self?.manager = manager
            self?.socket = socket
            
            // Setup event handlers
            self?.setupSocketListeners(userId: userId, userName: userName)
            
            // Connect
            socket.connect()
            
            print("🔌 Connecting to signaling server: \(serverUrl)")
        }
    }
    
    /// Disconnect from WebSocket server
    public func disconnect() async {
        await queue.async(flags: .barrier) { [weak self] in
            self?.socket?.disconnect()
            self?.socket = nil
            self?.manager = nil
            self?.isConnected = false
            print("❌ Disconnected from signaling server")
        }
    }
    
    // MARK: - Socket Event Setup
    
    private func setupSocketListeners(userId: String, userName: String) {
        guard let socket = socket else { return }
        
        // Connection
        socket.on(clientEvent: .connect) { [weak self] _, _ in
            self?.queue.async(flags: .barrier) { [weak self] in
                self?.isConnected = true
                print("✅ Socket connected")
                
                // Register user
                socket.emit("register-user", [
                    "userId": userId,
                    "userName": userName
                ])
                
                self?.onConnected?()
            }
        }
        
        socket.on(clientEvent: .disconnect) { [weak self] _, _ in
            self?.queue.async(flags: .barrier) { [weak self] in
                self?.isConnected = false
                print("❌ Socket disconnected")
                self?.onDisconnected?()
            }
        }
        
        socket.on(clientEvent: .error) { [weak self] data, _ in
            print("⚠️ Socket error: \(data)")
            self?.onError?("Socket error: \(data)")
        }
        
        // Online users
        socket.on("users-online") { [weak self] data, _ in
            self?.queue.async { [weak self] in
                guard let jsonData = data.first as? [[String: Any]] else { return }
                
                let users = jsonData.compactMap { dict -> OnlineUser? in
                    guard let userId = dict["userId"] as? String,
                          let userName = dict["userName"] as? String else {
                        return nil
                    }
                    return OnlineUser(userId: userId, userName: userName)
                }
                
                print("📢 Online users: \(users.count)")
                self?.onUsersOnline?(users)
            }
        }
        
        // Incoming call
        socket.on("incoming-call") { [weak self] data, _ in
            self?.queue.async { [weak self] in
                guard let dict = data.first as? [String: Any],
                      let callId = dict["callId"] as? String,
                      let callerId = dict["callerId"] as? String,
                      let callerName = dict["callerName"] as? String,
                      let callType = dict["callType"] as? String else {
                    return
                }
                
                let incomingCall = IncomingCall(
                    callId: callId,
                    callerId: callerId,
                    callerName: callerName,
                    callType: callType
                )
                
                print("📞 Incoming call from: \(callerName)")
                self?.onIncomingCall?(incomingCall)
            }
        }
        
        // Call accepted
        socket.on("call-accepted") { [weak self] data, _ in
            self?.queue.async { [weak self] in
                guard let dict = data.first as? [String: Any],
                      let callId = dict["callId"] as? String,
                      let acceptedById = dict["acceptedById"] as? String,
                      let acceptedByName = dict["acceptedByName"] as? String else {
                    return
                }
                
                let accepted = CallAccepted(
                    callId: callId,
                    acceptedById: acceptedById,
                    acceptedByName: acceptedByName
                )
                
                print("✅ Call accepted by: \(acceptedByName)")
                self?.onCallAccepted?(accepted)
            }
        }
        
        // Call rejected
        socket.on("call-rejected") { [weak self] data, _ in
            self?.queue.async { [weak self] in
                guard let dict = data.first as? [String: Any],
                      let callId = dict["callId"] as? String,
                      let rejectedById = dict["rejectedById"] as? String,
                      let rejectedByName = dict["rejectedByName"] as? String else {
                    return
                }
                
                let rejected = CallRejected(
                    callId: callId,
                    rejectedById: rejectedById,
                    rejectedByName: rejectedByName
                )
                
                print("❌ Call rejected by: \(rejectedByName)")
                self?.onCallRejected?(rejected)
            }
        }
        
        // Call joined
        socket.on("call-joined") { [weak self] data, _ in
            self?.queue.async { [weak self] in
                guard let dict = data.first as? [String: Any],
                      let callId = dict["callId"] as? String,
                      let participantId = dict["participantId"] as? String else {
                    return
                }
                
                var participants: [Participant] = []
                if let participantsData = dict["participants"] as? [[String: Any]] {
                    participants = participantsData.compactMap { p in
                        guard let id = p["id"] as? String,
                              let name = p["userName"] as? String else {
                            return nil
                        }
                        return Participant(id: id, name: name)
                    }
                }
                
                var iceServers: [ICEServer] = [ICEServer(urls: ["stun:stun.l.google.com:19302"])]
                if let configData = dict["config"] as? [String: Any],
                   let serversData = configData["iceServers"] as? [[String: Any]] {
                    iceServers = serversData.compactMap { server in
                        guard let urls = server["urls"] as? [String] else { return nil }
                        let username = server["username"] as? String
                        let credential = server["credential"] as? String
                        return ICEServer(urls: urls, username: username, credential: credential)
                    }
                }
                
                let response = JoinCallResponse(
                    success: true,
                    callId: callId,
                    participantId: participantId,
                    participants: participants,
                    config: WebRTCConfig(iceServers: iceServers),
                    error: nil
                )
                
                print("✅ Joined call: \(callId)")
                self?.onCallJoined?(response)
            }
        }
        
        // Participant joined
        socket.on("participant-joined") { [weak self] data, _ in
            self?.queue.async { [weak self] in
                guard let dict = data.first as? [String: Any],
                      let callId = dict["callId"] as? String,
                      let participantId = dict["participantId"] as? String,
                      let userName = dict["userName"] as? String else {
                    return
                }
                
                let joined = ParticipantJoined(
                    callId: callId,
                    participantId: participantId,
                    userName: userName
                )
                
                print("👤 Participant joined: \(userName)")
                self?.onParticipantJoined?(joined)
            }
        }
        
        // Participant left
        socket.on("participant-left") { [weak self] data, _ in
            self?.queue.async { [weak self] in
                guard let dict = data.first as? [String: Any],
                      let callId = dict["callId"] as? String,
                      let participantId = dict["participantId"] as? String else {
                    return
                }
                
                let left = ParticipantLeft(
                    callId: callId,
                    participantId: participantId
                )
                
                print("👋 Participant left: \(participantId)")
                self?.onParticipantLeft?(left)
            }
        }
        
        // Signal
        socket.on("signal") { [weak self] data, _ in
            self?.queue.async { [weak self] in
                guard let dict = data.first as? [String: Any],
                      let callId = dict["callId"] as? String,
                      let fromId = dict["fromId"] as? String,
                      let type = dict["type"] as? String,
                      let signalData = dict["signal"] as? [String: Any] else {
                    return
                }
                
                let sdp = signalData["sdp"] as? String
                let sdpType = signalData["type"] as? String
                let candidate = signalData["candidate"] as? String
                let sdpMid = signalData["sdpMid"] as? String
                let sdpMLineIndex = signalData["sdpMLineIndex"] as? Int
                
                let signal = Signal(
                    callId: callId,
                    targetId: nil,
                    fromId: fromId,
                    signal: SignalPayload(
                        sdp: sdp,
                        type: sdpType,
                        candidate: candidate,
                        sdpMid: sdpMid,
                        sdpMLineIndex: sdpMLineIndex
                    ),
                    type: type
                )
                
                print("📡 Signal received from \(fromId): \(type)")
                self?.onSignal?(signal)
            }
        }
        
        // Error
        socket.on("error") { [weak self] data, _ in
            self?.queue.async { [weak self] in
                guard let dict = data.first as? [String: Any],
                      let message = dict["message"] as? String else {
                    return
                }
                
                print("❌ Server error: \(message)")
                self?.onError?(message)
            }
        }
    }
    
    // MARK: - REST API Calls
    
    /// Create a new call
    /// - Parameters:
    ///   - callType: Type of call (video/audio)
    ///   - isGroup: Whether it's a group call
    ///   - maxParticipants: Maximum participants allowed
    /// - Returns: Call information
    public func createCall(
        callType: String = "video",
        isGroup: Bool = false,
        maxParticipants: Int = 1000
    ) async throws -> Call {
        guard let baseUrl = baseUrl else {
            throw SignalingError.notConnected
        }
        
        let url = URL(string: "\(baseUrl)/api/calls")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "callType": callType,
            "isGroup": isGroup,
            "maxParticipants": maxParticipants
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw SignalingError.httpError
        }
        
        let call = try JSONDecoder().decode(Call.self, from: data)
        print("✅ Call created: \(call.callId)")
        
        return call
    }
    
    /// Join an existing call
    /// - Parameters:
    ///   - callId: Call identifier
    ///   - userId: User identifier
    ///   - userName: User name
    /// - Returns: Join response with participants and config
    public func joinCall(
        callId: String,
        userId: String,
        userName: String
    ) async throws -> JoinCallResponse {
        guard let baseUrl = baseUrl else {
            throw SignalingError.notConnected
        }
        
        let url = URL(string: "\(baseUrl)/api/calls/\(callId)/join")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "userId": userId,
            "userName": userName
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw SignalingError.httpError
        }
        
        let joinResponse = try JSONDecoder().decode(JoinCallResponse.self, from: data)
        print("✅ Joined call via API: \(joinResponse.callId)")
        
        return joinResponse
    }
    
    // MARK: - Socket Emit Methods
    
    /// Join call via socket
    public func joinCallSocket(callId: String, participantId: String, userName: String) {
        queue.async { [weak self] in
            self?.socket?.emit("join-call", [
                "callId": callId,
                "participantId": participantId,
                "userName": userName
            ])
            print("📤 Emitted join-call socket event")
        }
    }
    
    /// Send call invitation
    public func sendCallInvitation(
        targetUserId: String,
        callId: String,
        callType: String,
        callerId: String,
        callerName: String
    ) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                self?.socket?.emitWithAck("send-call-invitation", [
                    "targetUserId": targetUserId,
                    "callId": callId,
                    "callType": callType,
                    "callerId": callerId,
                    "callerName": callerName
                ]) { data in
                    guard let response = data.first as? [String: Any],
                          let success = response["success"] as? Bool else {
                        continuation.resume(throwing: SignalingError.invalidResponse)
                        return
                    }
                    
                    if success {
                        continuation.resume()
                    } else {
                        let error = response["error"] as? String ?? "Unknown error"
                        continuation.resume(throwing: SignalingError.serverError(error))
                    }
                }
            }
        }
    }
    
    /// Accept incoming call
    public func acceptCall(callId: String, callerId: String) {
        queue.async { [weak self] in
            self?.socket?.emit("accept-call", [
                "callId": callId,
                "callerId": callerId
            ])
            print("✅ Emitted accept-call socket event")
        }
    }
    
    /// Reject incoming call
    public func rejectCall(callId: String, callerId: String) {
        queue.async { [weak self] in
            self?.socket?.emit("reject-call", [
                "callId": callId,
                "callerId": callerId
            ])
            print("❌ Emitted reject-call socket event")
        }
    }
    
    /// Send WebRTC signal
    public func sendSignal(
        callId: String,
        targetId: String,
        signal: SignalPayload,
        type: String
    ) {
        queue.async { [weak self] in
            var signalDict: [String: Any] = [:]
            if let sdp = signal.sdp { signalDict["sdp"] = sdp }
            if let type = signal.type { signalDict["type"] = type }
            if let candidate = signal.candidate { signalDict["candidate"] = candidate }
            if let sdpMid = signal.sdpMid { signalDict["sdpMid"] = sdpMid }
            if let sdpMLineIndex = signal.sdpMLineIndex { signalDict["sdpMLineIndex"] = sdpMLineIndex }
            
            self?.socket?.emit("signal", [
                "callId": callId,
                "targetId": targetId,
                "signal": signalDict,
                "type": type
            ])
            
            print("📡 Sent \(type) signal to \(targetId)")
        }
    }
    
    /// Leave call
    public func leaveCall(callId: String, reason: String = "left") {
        queue.async { [weak self] in
            self?.socket?.emit("leave-call", [
                "callId": callId,
                "reason": reason
            ])
            print("👋 Emitted leave-call socket event")
        }
    }
}

// MARK: - Error Types
enum SignalingError: LocalizedError {
    case invalidURL
    case socketCreationFailed
    case notConnected
    case httpError
    case invalidResponse
    case serverError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL"
        case .socketCreationFailed:
            return "Failed to create socket connection"
        case .notConnected:
            return "Not connected to signaling server"
        case .httpError:
            return "HTTP request failed"
        case .invalidResponse:
            return "Invalid server response"
        case .serverError(let message):
            return "Server error: \(message)"
        }
    }
}
