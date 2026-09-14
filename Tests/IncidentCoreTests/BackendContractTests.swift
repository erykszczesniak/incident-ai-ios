import Foundation
@testable import IncidentCore
import XCTest

@MainActor final class BackendContractTests: XCTestCase {
    func testRunningBackendContract() async throws {
        guard let server = ProcessInfo.processInfo.environment["INCIDENT_AI_TEST_SERVER"], let url = URL(string: server) else {
            throw XCTSkip("Set INCIDENT_AI_TEST_SERVER to run against a local demo backend.")
        }
        let key = ProcessInfo.processInfo.environment["INCIDENT_AI_TEST_KEY"] ?? "incident-ai-demo-key"
        let client = try LiveAPIClient(baseURL: url, apiKey: key)
        let page = try await client.incidents(status: nil, search: "", offset: 0)
        let incident = try XCTUnwrap(page.items.first)
        let detail = try await client.incident(id: incident.id)
        XCTAssertEqual(detail.id, incident.id)
        _ = try await client.alerts(id: incident.id)
        _ = try await client.logs(id: incident.id)
        _ = try await client.timeline(id: incident.id)
        let dashboard = try await client.dashboard()
        XCTAssertGreaterThanOrEqual(dashboard.totalIncidents, page.items.count)
        let search = try await client.search(query: incident.service)
        XCTAssertFalse(search.items.isEmpty)
        let analysis = try await client.analysis(id: incident.id, generate: true)
        XCTAssertTrue((0 ... 1).contains(analysis.confidence))
        let postmortem = try await client.postmortem(id: incident.id, generate: true)
        XCTAssertFalse(postmortem.markdown.isEmpty)
    }
}
