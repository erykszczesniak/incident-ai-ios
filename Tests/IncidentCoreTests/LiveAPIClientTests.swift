import Foundation
@testable import IncidentCore
import XCTest

private final class ResponseFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var status = 200
    private var body = "{}"
    private var recorded: URLRequest?
    func configure(status: Int, body: String) {
        lock.lock(); defer { lock.unlock() }
        self.status = status; self.body = body; recorded = nil
    }

    func respond(to request: URLRequest) -> (Int, Data) {
        lock.lock(); defer { lock.unlock() }
        recorded = request
        return (status, Data(body.utf8))
    }

    func request() -> URLRequest? {
        lock.lock(); defer { lock.unlock() }; return recorded
    }
}

private class StubURLProtocol: URLProtocol, @unchecked Sendable {
    static let fixture = ResponseFixture()
    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let (status, data) = Self.fixture.respond(to: request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor final class LiveAPIClientTests: XCTestCase {
    private func client() throws -> LiveAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return try LiveAPIClient(baseURL: URL(string: "https://incident.example")!, apiKey: "test-key", session: URLSession(configuration: configuration))
    }

    func testIncidentRequestUsesCanonicalIDAndAuthentication() async throws {
        StubURLProtocol.fixture.configure(status: 404, body: "{}")
        do {
            _ = try await client().incident(id: DemoData.primaryID); XCTFail("Expected not found")
        } catch { XCTAssertEqual(error as? APIError, .notFound) }
        let request = try XCTUnwrap(StubURLProtocol.fixture.request())
        XCTAssertEqual(request.url?.path, "/api/v1/incidents/a24f8100-6f08-4b76-b9eb-ab8ddacaf002")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-Key"), "test-key")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "X-Correlation-ID"))
    }

    func testUnauthorizedMapsToRecoveryError() async throws {
        StubURLProtocol.fixture.configure(status: 401, body: "{}")
        do {
            _ = try await client().dashboard(); XCTFail("Expected unauthorized")
        } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
    }

    func testIntegrationFailurePreservesServerMessage() async throws {
        StubURLProtocol.fixture.configure(status: 503, body: #"{"error":{"code":"not_configured","message":"Jira is not configured."},"correlation_id":"x"}"#)
        do {
            _ = try await client().export(id: DemoData.primaryID, destination: "jira"); XCTFail("Expected unavailable")
        } catch { XCTAssertEqual(error as? APIError, .server("Jira is not configured.")) }
    }

    func testMalformedPayloadDoesNotLeakRawResponse() async throws {
        StubURLProtocol.fixture.configure(status: 200, body: #"{"unexpected":"private content"}"#)
        do {
            _ = try await client().dashboard(); XCTFail("Expected invalid response")
        } catch { XCTAssertEqual(error as? APIError, .invalidResponse) }
    }

    func testSearchQueryIsEncodedSafely() async throws {
        StubURLProtocol.fixture.configure(status: 200, body: #"{"items":[],"total":0,"limit":50,"offset":0}"#)
        _ = try await client().incidents(status: "active", search: "checkout & payments", offset: 0)
        let request = try XCTUnwrap(StubURLProtocol.fixture.request())
        let query = try URLComponents(url: XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(query?.first(where: { $0.name == "search" })?.value, "checkout & payments")
    }
}
