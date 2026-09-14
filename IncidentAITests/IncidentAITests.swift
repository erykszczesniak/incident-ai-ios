@testable import IncidentAI
import IncidentCore
import XCTest

@MainActor final class IncidentAITests: XCTestCase {
    func testDetailLoadsRelatedContextAndUpdatesStatus() async {
        let api = MockAPIClient()
        let model = IncidentDetailModel(id: DemoData.primaryID, api: api)
        await model.load()
        XCTAssertEqual(model.state.value?.service, "checkout-api")
        XCTAssertEqual(model.logs.count, 6)
        XCTAssertEqual(model.alerts.count, 1)
        let updated = await model.update(.resolved)
        XCTAssertTrue(updated)
        XCTAssertEqual(model.state.value?.status, .resolved)
        XCTAssertNil(model.operationError)
        XCTAssertFalse(model.updating)
    }

    func testMissingIncidentHasRecoverableError() async {
        let model = IncidentDetailModel(id: UUID(), api: MockAPIClient())
        await model.load()
        if case let .failed(message) = model.state {
            XCTAssertFalse(message.isEmpty)
        } else {
            XCTFail("Expected failure state")
        }
        let updated = await model.update(.resolved)
        XCTAssertFalse(updated)
        XCTAssertNotNil(model.operationError)
        XCTAssertFalse(model.updating)
    }
}
