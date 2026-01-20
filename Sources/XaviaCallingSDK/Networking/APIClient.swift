import Foundation

class APIClient {
    private let baseUrl: String
    private let session: URLSession
    
    init(baseUrl: String) {
        self.baseUrl = baseUrl
        self.session = URLSession(configuration: .default)
    }
    
    func createCall(request: CreateCallRequest) async throws -> CreateCallResponse {
        let url = URL(string: "\(baseUrl)/api/calls")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        
        let (data, _) = try await session.data(for: urlRequest)
        return try JSONDecoder().decode(CreateCallResponse.self, from: data)
    }
    
    func joinCall(callId: String, request: JoinCallRequest) async throws -> JoinCallResponse {
        let url = URL(string: "\(baseUrl)/api/calls/\(callId)/join")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        
        let (data, _) = try await session.data(for: urlRequest)
        return try JSONDecoder().decode(JoinCallResponse.self, from: data)
    }
}