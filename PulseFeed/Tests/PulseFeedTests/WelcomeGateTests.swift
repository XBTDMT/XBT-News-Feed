import XCTest
import GRDB
@testable import PulseFeed

/// Who sees the welcome flow (spec §6 "Who sees it"): a fresh install, never an install in use.
final class WelcomeGateTests: XCTestCase {
    private var suite: String!
    private var d: UserDefaults!
    private var dir: URL!

    override func setUpWithError() throws {
        suite = "WelcomeGateTests-\(UUID().uuidString)"
        d = UserDefaults(suiteName: suite)
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("WelcomeGateTests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        d.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: dir)
    }

    func testAnInstallWithStoriesNeverSeesItAndIsMarkedDone() {
        let plan = WelcomeGate.launchPlan(d, hasHistory: true)
        XCTAssertEqual(plan, WelcomeGate.LaunchPlan(showWelcome: false, prepareFreshInstall: false, askNotificationsAtLaunch: true))
        XCTAssertTrue(d.bool(forKey: WelcomeGate.completedKey))
    }

    func testAFreshInstallSeesItAndStartsEmpty() async throws {
        let plan = WelcomeGate.launchPlan(d, hasHistory: false)
        XCTAssertEqual(plan, WelcomeGate.LaunchPlan(showWelcome: true, prepareFreshInstall: true, askNotificationsAtLaunch: false))
        XCTAssertFalse(d.bool(forKey: WelcomeGate.completedKey))

        let db = try AppDatabase(path: dir.appendingPathComponent("t.sqlite").path)
        try await db.syncCatalog(Catalog.load(from: CatalogTests.catalogURL), enableNew: false)
        try db.prepareFreshInstall()
        let (on, interests, unchosen, total) = try await db.dbPool.read { db in
            (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM feed WHERE isEnabled = 1") ?? -1,
             try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM userInterest") ?? -1,
             try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM feed WHERE catalogAdded = 1") ?? -1,
             try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM feed") ?? -1)
        }
        XCTAssertEqual(on, 0)
        XCTAssertEqual(interests, 0)
        XCTAssertEqual(unchosen, total)
    }

    func testCompletedNeverShowsAgain() {
        WelcomeGate.markCompleted(d)
        XCTAssertFalse(WelcomeGate.launchPlan(d, hasHistory: false).showWelcome)
        XCTAssertFalse(WelcomeGate.launchPlan(d, hasHistory: false).prepareFreshInstall)
    }

    func testNotificationsAreAskedInTheFlowNotAtLaunch() {
        XCTAssertFalse(WelcomeGate.launchPlan(d, hasHistory: false).askNotificationsAtLaunch)
        WelcomeGate.markCompleted(d)
        XCTAssertTrue(WelcomeGate.launchPlan(d, hasHistory: false).askNotificationsAtLaunch)
    }

    /// The reset never touches a database with stories, whoever calls it.
    func testTheResetRefusesADatabaseWithStories() async throws {
        let db = try AppDatabase(path: dir.appendingPathComponent("t2.sqlite").path)
        let feedID = try await db.dbPool.read { try String.fetchOne($0, sql: "SELECT id FROM feed WHERE isEnabled = 1 LIMIT 1") }!
        _ = try await db.insertArticles([Article(articleID: "a1", feedID: feedID, uniqueID: "1", dateArrived: Date().sqliteString)])
        // The public flavour seeds no interests; give the install one of its own for the reset to keep.
        try await db.addInterest(keyword: "typed", weight: 1.0, category: nil)
        let before = try await db.dbPool.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM feed WHERE isEnabled = 1") ?? 0 }
        try db.prepareFreshInstall()
        let after = try await db.dbPool.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM feed WHERE isEnabled = 1") ?? 0 }
        let interests = try await db.dbPool.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM userInterest") ?? 0 }
        XCTAssertGreaterThan(before, 0)
        XCTAssertEqual(after, before)
        XCTAssertGreaterThan(interests, 0)
    }
}
