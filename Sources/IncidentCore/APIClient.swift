import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

public protocol IncidentAPI: Sendable {
    func incidents(status: String?, search: String, offset: Int) async throws -> IncidentPage
    func incident(id: UUID) async throws -> Incident
    func updateIncident(id: UUID, status: IncidentStatus) async throws -> Incident
    func alerts(id: UUID) async throws -> [IncidentAlert]
    func logs(id: UUID) async throws -> [LogEntry]
    func timeline(id: UUID) async throws -> [TimelineEvent]
    func addEvent(id: UUID, message: String) async throws -> TimelineEvent
    func analysis(id: UUID, generate: Bool) async throws -> Analysis
    func postmortem(id: UUID, generate: Bool) async throws -> Postmortem
    func savePostmortem(id: UUID, markdown: String) async throws -> Postmortem
    func export(id: UUID, destination: String) async throws -> ExportResult
    func dashboard() async throws -> Dashboard
    func search(query: String) async throws -> SearchResult
    func registerDevice(token: String) async throws
}

public enum APIJSON {
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) {
                return date
            }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid ISO 8601 date"))
        }
        return decoder
    }
}

public actor LiveAPIClient: IncidentAPI {
    private let baseURL: URL
    private let apiKey: String
    private let session: URLSession

    public init(baseURL: URL, apiKey: String, session: URLSession = .shared) throws {
        let local = ["localhost", "127.0.0.1", "::1"].contains(baseURL.host ?? "")
        guard baseURL.host != nil, baseURL.scheme == "https" || (baseURL.scheme == "http" && local) else { throw APIError.invalidURL }
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
    }

    public func incidents(status: String? = "active", search: String = "", offset: Int = 0) async throws -> IncidentPage {
        var query = [URLQueryItem(name: "limit", value: "50"), URLQueryItem(name: "offset", value: "\(offset)")]
        if let status {
            query.append(URLQueryItem(name: "status", value: status))
        }
        if !search.isEmpty {
            query.append(URLQueryItem(name: "search", value: search))
        }
        return try await request("incidents", query: query)
    }

    public func incident(id: UUID) async throws -> Incident {
        try await request("incidents/\(id.uuidString.lowercased())")
    }

    public func updateIncident(id: UUID, status: IncidentStatus) async throws -> Incident {
        try await request("incidents/\(id.uuidString.lowercased())", method: "PATCH", body: ["status": status.rawValue])
    }

    public func alerts(id: UUID) async throws -> [IncidentAlert] {
        try await request("incidents/\(id.uuidString.lowercased())/alerts")
    }

    public func logs(id: UUID) async throws -> [LogEntry] {
        try await request("incidents/\(id.uuidString.lowercased())/logs")
    }

    public func timeline(id: UUID) async throws -> [TimelineEvent] {
        try await request("incidents/\(id.uuidString.lowercased())/timeline")
    }

    public func addEvent(id: UUID, message: String) async throws -> TimelineEvent {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw APIError.invalidInput("Write a timeline note first.") }
        return try await request("incidents/\(id.uuidString.lowercased())/timeline", method: "POST", body: ["message": trimmed])
    }

    public func analysis(id: UUID, generate: Bool) async throws -> Analysis {
        try await request("incidents/\(id.uuidString.lowercased())/analysis", method: generate ? "POST" : "GET")
    }

    public func postmortem(id: UUID, generate: Bool) async throws -> Postmortem {
        try await request("incidents/\(id.uuidString.lowercased())/postmortem", method: generate ? "POST" : "GET")
    }

    public func savePostmortem(id: UUID, markdown: String) async throws -> Postmortem {
        try await request("incidents/\(id.uuidString.lowercased())/postmortem", method: "PATCH", body: ["markdown": markdown])
    }

    public func export(id: UUID, destination: String) async throws -> ExportResult {
        guard ["jira", "confluence"].contains(destination) else { throw APIError.invalidInput("Unsupported export destination.") }
        return try await request("incidents/\(id.uuidString.lowercased())/postmortem/export/\(destination)", method: "POST")
    }

    public func dashboard() async throws -> Dashboard {
        try await request("dashboard")
    }

    public func search(query: String) async throws -> SearchResult {
        try await request("search", query: [URLQueryItem(name: "q", value: query)])
    }

    public func registerDevice(token: String) async throws {
        struct Registration: Decodable { let registered: Bool }
        #if DEBUG
            let environment = "sandbox"
        #else
            let environment = "production"
        #endif
        let _: Registration = try await request("devices", method: "POST", body: ["token": token, "platform": "ios", "environment": environment])
    }

    private func request<T: Decodable & Sendable>(
        _ path: String,
        method: String = "GET",
        body: [String: String]? = nil,
        query: [URLQueryItem] = []
    ) async throws -> T {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/v1").appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else { throw APIError.invalidURL }
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Correlation-ID")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch { throw APIError.transport(error.localizedDescription) }
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        switch http.statusCode {
        case 200 ... 299: break
        case 401, 403: throw APIError.unauthorized
        case 404: throw APIError.notFound
        default:
            let message = (try? JSONDecoder().decode(Envelope.self, from: data))?.error.message
            throw APIError.server(message ?? "The server is unavailable (\(http.statusCode)). Try again.")
        }
        do {
            return try APIJSON.decoder().decode(T.self, from: data)
        } catch { throw APIError.invalidResponse }
    }
}

private struct Envelope: Decodable, Sendable {
    struct Detail: Decodable, Sendable { let message: String }
    let error: Detail
}
