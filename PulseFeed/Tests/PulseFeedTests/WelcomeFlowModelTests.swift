import XCTest
@testable import PulseFeed

/// The flow's live preview never sits spinning (plan Review Focus 2).
@MainActor
final class WelcomeFlowModelTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("WelcomeFlowModelTests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func testClearingTheLastTopicStopsTheSpinner() throws {
        let db = try AppDatabase(path: dir.appendingPathComponent("t.sqlite").path)
        let catalog = try Catalog.load(from: CatalogTests.catalogURL)
        let model = WelcomeFlowModel(appDB: db, catalog: catalog, dryRun: true)
        model.isLoadingPreview = true            // a fetch was in flight
        model.draft.topics = []
        model.refreshPreview()
        XCTAssertFalse(model.isLoadingPreview)
        XCTAssertEqual(model.headlines, [])
    }
}
