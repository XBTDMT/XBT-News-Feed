import XCTest
import GRDB
@testable import PulseFeed

/// What typed interests change: a topic switches on only its own feeds, a follow joins the stored
/// rules once, and a search becomes one feed.
final class ApplyInterestsTests: XCTestCase {
    private var dir: URL!
    private var appDB: AppDatabase!
    private var suite: String!
    private var d: UserDefaults!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ApplyInterestsTests-\(UUID().uuidString)")
        appDB = try AppDatabase(path: dir.appendingPathComponent("t.sqlite").path)
        suite = "ApplyInterestsTests-\(UUID().uuidString)"
        d = UserDefaults(suiteName: suite)
        try await appDB.syncCatalog(try Catalog.load(from: CatalogTests.catalogURL), enableNew: false)
    }

    override func tearDown() {
        d.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: dir)
    }

    private func catalog() throws -> Catalog { try Catalog.load(from: CatalogTests.catalogURL) }

    private func enabled(topic: String) async throws -> [Bool] {
        try await appDB.dbPool.read { db in try Bool.fetchAll(db, sql: "SELECT isEnabled FROM feed WHERE topic = ?", arguments: [topic]) }
    }

    func testTopicMatchEnablesOnlyThatTopicsFeeds() async throws {
        let before = try await enabled(topic: "nfl")
        XCTAssertTrue(before.allSatisfy { !$0 } && !before.isEmpty)
        try await appDB.applyInterests([.topic(id: "nfl")], catalog: try catalog(), region: "us", defaults: d)
        let nfl = try await enabled(topic: "nfl"), mlb = try await enabled(topic: "mlb")
        XCTAssertTrue(nfl.allSatisfy { $0 })
        XCTAssertTrue(mlb.allSatisfy { !$0 })
    }

    func testFollowIsAddedOnceToStoredRules() async throws {
        d.set(UrgencyRules.defaults.asText, forKey: UrgencyRules.defaultsKey)
        try await appDB.applyInterests([.follow(name: "Arsenal", topicID: "premier-league")], catalog: try catalog(), region: "uk", defaults: d)
        try await appDB.applyInterests([.follow(name: "arsenal", topicID: nil)], catalog: try catalog(), region: "uk", defaults: d)
        XCTAssertEqual(UrgencyRules.stored(d).followed, ["arsenal"], "the same name followed everywhere supersedes its scoped form")
    }

    func testFollowOnFreshInstallStartsFromNeutralDefaults() async throws {
        try await appDB.applyInterests([.follow(name: "nvidia", topicID: "tech")], catalog: try catalog(), region: "us", defaults: d)
        let stored = UrgencyRules.stored(d)
        XCTAssertTrue(stored.followed.contains("tech: nvidia") && stored.followed.allSatisfy { $0.hasSuffix(": nvidia") },
                      "a catalog follow is scoped to its chips: \(stored.followed)")
        XCTAssertEqual(stored.urgentPatterns, UrgencyRules.parse(UrgencyRules.defaults.asText).urgentPatterns)
    }

    func testSearchMatchAddsOneFeed() async throws {
        try await appDB.applyInterests([.newSearch(phrase: "japanese whisky", category: "food")], catalog: try catalog(), region: "us", defaults: d)
        try await appDB.applyInterests([.newSearch(phrase: "japanese whisky", category: "food")], catalog: try catalog(), region: "us", defaults: d)
        let search = try await enabled(topic: "search:japanese-whisky")
        XCTAssertEqual(search, [true])
    }

    func testAddingFollowsKeepsOrderAndDropsDuplicates() {
        var r = UrgencyRules.defaults
        r.followed = ["celtics"]
        XCTAssertEqual(r.addingFollows(["McLaren", "celtics", " mclaren ", ""]).followed, ["celtics", "mclaren"])
    }

    /// A catalog follow alerts only on stories under its own chip: "heat" is stored as "sports: heat", so
    /// "extreme heat" in World never fires it (audit round 4, N-3).
    func testACatalogFollowIsStoredScopedToItsChip() async throws {
        try await appDB.applyInterests([.follow(name: "heat", topicID: "nba"), .follow(name: "oscar piastri", topicID: nil)],
                                       catalog: try catalog(), region: "us", defaults: d)
        XCTAssertEqual(UrgencyRules.stored(d).followed, ["sports: heat", "oscar piastri"])
        XCTAssertEqual(UrgencyRules.stored(d).followedNames, ["heat", "oscar piastri"])
    }

    /// A follow the catalog lists under several chips alerts under each of them: "apple" is Tech and
    /// Finance, not only whichever topic comes first (audit round 5, I-1).
    func testAFollowListedUnderSeveralChipsIsScopedToEach() async throws {
        try await appDB.applyInterests([.follow(name: "apple", topicID: "markets")], catalog: try catalog(), region: "us", defaults: d)
        let stored = Set(UrgencyRules.stored(d).followed)
        XCTAssertTrue(stored.isSuperset(of: ["tech: apple", "finance: apple"]), "\(stored)")
    }
}
