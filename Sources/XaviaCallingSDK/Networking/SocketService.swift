import Foundation

protocol SocketServiceProtocol: AnyObject {
    func connect(userId: String, userName: String) async throws
    func disconnect()
    func joinCall(_ data: JoinCallSocketData)
    func sendCallInvitation(_ invitation: CallInvitationData) async throws
    func acceptCall(callId: String, callerId: String)
    func rejectCall(callId: String, callerId: String)
    func leaveCall(callId: String, reason: String)
    func sendSignal(_ signal: SignalData)
    
    var isConnected: Bool { get }
    var onOnlineUsers: (([OnlineUser]) -> Void)? { get set }
    var onIncomingCall: ((IncomingCallData) -> Void)? { get set }
    var onCallAccepted: ((CallAcceptedData) -> Void)? { get set }
    var onCallRejected: ((CallRejectedData) -> Void)? { get set }
    var onCallJoined: ((CallJoinedData) -> Void)? { get set }
    var onParticipantJoined: ((ParticipantData) -> Void)? { get set }
    var onParticipantLeft: ((ParticipantLeftData) -> Void)? { get set }
    var onSignal: ((SignalData) -> Void)? { get set }
    var onError: ((String) -> Void)? { get set }
    var onConnectionChange: ((Bool) -> Void)? { get set }
}

class SocketService: NSObject, SocketServiceProtocol, URLSessionWebSocketDelegate {
    private var webSocketTask: URLSessionWebSocketTask?
    private let baseUrl: String
    private weak var webRTCService: WebRTCService?
    private var session: URLSession
    
    var isConnected: Bool = false
    
    // Event handlers
    var onOnlineUsers: (([OnlineUser]) -> Void)?
    var onIncomingCall: ((IncomingCallData) -> Void)?
    var onCallAccepted: ((CallAcceptedData) -> Void)?
    var onCallRejected: ((CallRejectedData) -> Void)?
    var onCallJoined: ((CallJoinedData) -> Void)?
    var onParticipantJoined: ((ParticipantData) -> Void)?
    var onParticipantLeft: ((ParticipantLeftData) -> Void)?
    var onSignal: ((SignalData) -> Void)?
    var onError: ((String) -> Void)?
    var onConnectionChange: ((Bool) -> Void)?
    
    private var connectionContinuation: CheckedContinuation<Void, Error>?
    private var invitationContinuation: CheckedContinuation<Void, Error>?
    
    init(baseUrl: String, webRTCService: WebRTCService) {
        self.baseUrl = baseUrl
        self.webRTCService = webRTCService
        self.session = URLSession(configuration: .default)
        super.init()
    }
    
    func connect(userId: String, userName: String) async throws {
        let urlString = baseUrl.replacingOccurrences(of: "http", with: "ws")
            .replacingOccurrences(of: "https", with: "wss")
        guard let url = URL(string: urlString) else {
            throw WebRTCError.socketError("Invalid URL: \(urlString)")
        }
        
        Logger.log("🔌 Connecting to WebSocket: \(urlString)")
        
        // Create URLSession with delegate
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        
        // Start receiving messages
        receiveMessage()
        
        // Wait for connection with timeout
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.connectionContinuation = continuation
            
            // Set timeout
            Task {
                try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                if !self.isConnected {
                    continuation.resume(throwing: WebRTCError.socketError("Connection timeout"))
                    self.connectionContinuation = nil
                }
            }
        }
        
        // Register user after successful connection
        registerUser(userId: userId, userName: userName)
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                // Continue receiving messages
                self.receiveMessage()
                
            case .failure(let error):
                Logger.error("Receive error: \(error)")
                self.isConnected = false
                self.onConnectionChange?(false)
                self.onError?(error.localizedDescription)
            }
        }
    }
    
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
        onConnectionChange?(false)
    }
    
    // MARK: - URLSessionWebSocketDelegate
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        Logger.log("✅ Socket connected")
        isConnected = true
        onConnectionChange?(true)
        
        // Resume connection continuation
        connectionContinuation?.resume()
        connectionContinuation = nil
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown"
        Logger.log("❌ Socket disconnected: \(reasonString) (\(closeCode.rawValue))")
        isConnected = false
        onConnectionChange?(false)
    }
    
    // MARK: - Message Handling
    
    private func handleMessage(_ text: String) {
        do {
            guard let data = text.data(using: .utf8) else {
                throw WebRTCError.socketError("Invalid message encoding")
            }
            
            let decoder = JSONDecoder()
            
            // Try to decode as a generic event first
            let baseEvent = try decoder.decode(SocketBaseEvent.self, from: data)
            
            switch baseEvent.event {
            case "users-online":
                let event = try decoder.decode(SocketEvent<[OnlineUser]>.self, from: data)
                Logger.log("📢 Online users: \(event.data.count)")
                onOnlineUsers?(event.data)
                
            case "incoming-call":
                let event = try decoder.decode(SocketEvent<IncomingCallData>.self, from: data)
                Logger.log("📞 Incoming call from: \(event.data.callerName)")
                onIncomingCall?(event.data)
                
            case "call-accepted":
                let event = try decoder.decode(SocketEvent<CallAcceptedData>.self, from: data)
                Logger.log("✅ Call accepted by: \(event.data.acceptedByName)")
                onCallAccepted?(event.data)
                
            case "call-rejected":
                let event = try decoder.decode(SocketEvent<CallRejectedData>.self, from: data)
                Logger.log("❌ Call rejected by: \(event.data.rejectedByName)")
                onCallRejected?(event.data)
                
            case "call-joined":
                let event = try decoder.decode(SocketEvent<CallJoinedData>.self, from: data)
                Logger.log("✅ Call joined: \(event.data.callId)")
                onCallJoined?(event.data)
                
            case "participant-joined":
                let event = try decoder.decode(SocketEvent<ParticipantData>.self, from: data)
                Logger.log("👤 Participant joined: \(event.data.userName)")
                onParticipantJoined?(event.data)
                
            case "participant-left":
                let event = try decoder.decode(SocketEvent<ParticipantLeftData>.self, from: data)
                Logger.log("👋 Participant left: \(event.data.participantId)")
                onParticipantLeft?(event.data)
                
            case "signal":
                let event = try decoder.decode(SocketEvent<SignalData>.self, from: data)
                Logger.log("📡 Received signal from: \(event.data.fromId)")
                onSignal?(event.data)
                
            case "error":
                let event = try decoder.decode(SocketEvent<SocketErrorData>.self, from: data)
                Logger.error("❌ Server error: \(event.data.message)")
                onError?(event.data.message)
                
                // Handle invitation errors
                if event.data.message.contains("invitation") {
                    invitationContinuation?.resume(throwing: WebRTCError.socketError(event.data.message))
                    invitationContinuation = nil
                }
                
            case "call-invitation-sent":
                Logger.log("📤 Call invitation sent successfully")
                invitationContinuation?.resume()
                invitationContinuation = nil
                
            default:
                Logger.log("Unhandled event: \(baseEvent.event)")
            }
        } catch {
            Logger.error("Failed to handle message: \(error)")
        }
    }
    
    // MARK: - Socket Methods
    
    private func registerUser(userId: String, userName: String) {
        let message = SocketEvent<RegistrationData>(
            event: "register-user",
            data: RegistrationData(userId: userId, userName: userName)
        )
        sendMessage(message)
    }
    
    func joinCall(_ data: JoinCallSocketData) {
        let message = SocketEvent<JoinCallSocketData>(
            event: "join-call",
            data: data
        )
        sendMessage(message)
    }
    
    func sendCallInvitation(_ invitation: CallInvitationData) async throws {
        let message = SocketEvent<CallInvitationData>(
            event: "send-call-invitation",
            data: invitation
        )
        
        return try await withCheckedThrowingContinuation { continuation in
            self.invitationContinuation = continuation
            sendMessage(message)
        }
    }
    
    func acceptCall(callId: String, callerId: String) {
        let message = SocketEvent<AcceptCallData>(
            event: "accept-call",
            data: AcceptCallData(callId: callId, callerId: callerId)
        )
        sendMessage(message)
    }
    
    func rejectCall(callId: String, callerId: String) {
        let message = SocketEvent<RejectCallData>(
            event: "reject-call",
            data: RejectCallData(callId: callId, callerId: callerId)
        )
        sendMessage(message)
    }
    
    func leaveCall(callId: String, reason: String) {
        let message = SocketEvent<LeaveCallData>(
            event: "leave-call",
            data: LeaveCallData(callId: callId, reason: reason)
        )
        sendMessage(message)
    }
    
    func sendSignal(_ signal: SignalData) {
        let message = SocketEvent<SignalData>(
            event: "signal",
            data: signal
        )
        sendMessage(message)
    }
    
    private func sendMessage<T: Encodable>(_ message: T) {
        do {
            let data = try JSONEncoder().encode(message)
            if let text = String(data: data, encoding: .utf8) {
                webSocketTask?.send(.string(text)) { [weak self] error in
                    if let error = error {
                        Logger.error("Send error: \(error)")
                        self?.onError?(error.localizedDescription)
                    } else {
                        Logger.debug("📤 Sent: \(message)")
                    }
                }
            }
        } catch {
            Logger.error("Failed to encode message: \(error)")
        }
    }
}
