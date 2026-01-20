import Foundation

// MARK: - Socket Event Structures

struct SocketBaseEvent: Codable {
    let event: String
}

struct SocketEvent<T: Codable>: Codable {
    let event: String
    let data: T
}

struct SocketErrorData: Codable {
    let message: String
    let code: Int?
    
    enum CodingKeys: String, CodingKey {
        case message = "message"
        case code = "code"
    }
}

// MARK: - Registration Data

struct RegistrationData: Codable {
    let userId: String
    let userName: String
}

// MARK: - Call Action Data

struct AcceptCallData: Codable {
    let callId: String
    let callerId: String
}

struct RejectCallData: Codable {
    let callId: String
    let callerId: String
}

struct LeaveCallData: Codable {
    let callId: String
    let reason: String
}