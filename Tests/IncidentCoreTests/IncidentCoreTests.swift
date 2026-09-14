import Foundation
@testable import IncidentCore
import XCTest

final class IncidentCoreTests: XCTestCase {
    func testDecodesBackendIncidentWithFractionalTimestamp() throws {
        let data = Data(
            """
            {
              "id": "a24f8100-6f08-4b76-b9eb-ab8ddacaf002",
              "title": "Latency",
              "service": "api",
              "severity": "high",
              "status": "open",
              "description": "P95 high",
              "created_at": "2026-09-14T12:00:00.123456Z",
              "updated_at": "2026-09-14T12:00:00Z",
              "acknowledged_at": null,
              "resolved_at": null
            }
            """.utf8
        )
        let incident = try APIJSON.decoder().decode(Incident.self, from: data)
        XCTAssertEqual(incident.id, DemoData.primaryID)
        XCTAssertNil(incident.resolvedAt)
        XCTAssertEqual(incident.severity, .high)
    }

    func testDashboardAllowsNoResolvedDataAndFractionalTarget() throws {
        let data = Data(
            """
            {
              "total_incidents": 1,
              "active_incidents": 1,
              "resolved_incidents": 0,
              "mttr_minutes": null,
              "acknowledgement_minutes": null,
              "sla_compliance_percent": null,
              "sla_target_minutes": 30.5,
              "by_severity": [],
              "daily_counts": [],
              "services": []
            }
            """.utf8
        )
        let dashboard = try APIJSON.decoder().decode(Dashboard.self, from: data)
        XCTAssertNil(dashboard.mttrMinutes)
        XCTAssertEqual(dashboard.slaTargetMinutes, 30.5)
    }

    func testDeepLinkRejectsUntrustedHost() throws {
        XCTAssertEqual(try IncidentDeepLink.incidentID(from: XCTUnwrap(URL(string: "incidentai://incident/\(DemoData.primaryID)"))), DemoData.primaryID)
        XCTAssertNil(try IncidentDeepLink.incidentID(from: XCTUnwrap(URL(string: "https://incident/\(DemoData.primaryID)"))))
        XCTAssertNil(try IncidentDeepLink.incidentID(from: XCTUnwrap(URL(string: "incidentai://settings/\(DemoData.primaryID)"))))
    }

    func testRemoteHTTPRejected() throws {
        XCTAssertThrowsError(try LiveAPIClient(baseURL: XCTUnwrap(URL(string: "http://example.com")), apiKey: "test"))
        XCTAssertNoThrow(try LiveAPIClient(baseURL: XCTUnwrap(URL(string: "http://127.0.0.1:8000")), apiKey: "test"))
    }

    func testCompleteDemoResponseLoop() async throws {
        let api = MockAPIClient()
        let page = try await api.incidents(status: "active", search: "", offset: 0)
        XCTAssertEqual(page.total, 3)
        let id = DemoData.primaryID
        let analysis = try await api.analysis(id: id, generate: true)
        XCTAssertEqual(analysis.provider, "demo")
        XCTAssertFalse(analysis.evidence.isEmpty)
        _ = try await api.addEvent(id: id, message: "Confirmed rollback.")
        let postmortem = try await api.postmortem(id: id, generate: true)
        XCTAssertTrue(postmortem.markdown.contains("Confirmed rollback."))
        let saved = try await api.savePostmortem(id: id, markdown: postmortem.markdown + "\nReviewed.")
        XCTAssertEqual(saved.version, 2)
        let export = try await api.export(id: id, destination: "jira")
        XCTAssertTrue(export.isDemo)
        _ = try await api.updateIncident(id: id, status: .resolved)
        let remaining = try await api.incidents(status: "active", search: "", offset: 0)
        XCTAssertEqual(remaining.total, 2)
        let dashboard = try await api.dashboard()
        XCTAssertEqual(dashboard.resolvedIncidents, 2)
    }

    func testEmptyTimelineEntryRejected() async throws {
        let api = MockAPIClient()
        do {
            _ = try await api.addEvent(id: DemoData.primaryID, message: " \n "); XCTFail("Expected validation error")
        } catch { XCTAssertEqual(error as? APIError, .invalidInput("Write a timeline note first.")) }
    }

    @MainActor func testListModelLoadsFiltersAndEmptyState() async {
        let model = IncidentListModel(api: MockAPIClient())
        await model.load()
        XCTAssertEqual(model.state.value?.count, 3)
        XCTAssertEqual(model.state.value?.first?.severity, .critical)
        await model.load(search: "payments")
        XCTAssertEqual(model.state.value?.first?.service, "payments-worker")
        await model.load(search: "does-not-exist")
        XCTAssertEqual(model.state.value?.count, 0)
    }

    func testAnalysisReadBeforeGenerateIsNotFound() async {
        do {
            _ = try await MockAPIClient().analysis(id: DemoData.primaryID, generate: false); XCTFail("Should require generation")
        } catch { XCTAssertEqual(error as? APIError, .notFound) }
    }
}
