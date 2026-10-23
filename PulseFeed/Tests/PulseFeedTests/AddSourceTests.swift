import XCTest
import GRDB
@testable import PulseFeed

/// Settings › Sources › Add / Remove against a real (temporary) database: an added feed is enabled and
/// switches its category on, the category tick still governs it, adding the same URL twice is
/// reported rather than duplicated, and removing a feed takes its stories with it.
final class AddSourceTests: XCTestCase {
    private var dir: URL!
    private var appDB: AppDatabase!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("AddSourceTests-\(UUID().uuidString)")
        appDB = try AppDatabase(path: dir.appendingPathComponent("t.sqlite").path)
    }

    override func tearDownWithError() throws {
        appDB = nil
        try? FileManager.default.removeItem(at: dir)
    }

    private func enabledCategories() async throws -> Set<String> {
        try await appDB.dbPool.read { db in
            Set(try String.fetchAll(db, sql: "SELECT DISTINCT category FROM feed WHERE isEnabled = 1"))
        }
    }

    func testAddedSourceIsEnabledAndTurnsItsCategoryOn() async throws {
        try await appDB.setCategoryEnabled("gaming", false)
        var on = try await enabledCategories()
        XCTAssertFalse(on.contains("gaming"))

        let outcome = try await appDB.addSource(title: "Rock Paper Shotgun", url: "https://www.rockpapershotgun.com/feed", category: "gaming")
        guard case .added(let feed) = outcome else { return XCTFail("expected .added, got \(outcome)") }
        XCTAssertEqual(feed.title, "Rock Paper Shotgun")
        XCTAssertEqual(feed.url, "https://www.rockpapershotgun.com/feed")
        XCTAssertEqual(feed.category, "gaming")
        XCTAssertEqual(feed.type, "rss")
        XCTAssertTrue(feed.isEnabled)

        on = try await enabledCategories()
        XCTAssertTrue(on.contains("gaming"), "a category is on when one of its feeds is enabled")
    }

    func testCategoryTickStillGovernsAnAddedFeed() async throws {
        guard case .added(let feed) = try await appDB.addSource(title: "X", url: "https://x.example.com/feed", category: "gaming") else {
            return XCTFail("expected .added")
        }
        try await appDB.setCategoryEnabled("gaming", false)
        let off = try await appDB.feed(withURL: feed.url)
        XCTAssertEqual(off?.isEnabled, false)
        try await appDB.setCategoryEnabled("gaming", true)
        let on = try await appDB.feed(withURL: feed.url)
        XCTAssertEqual(on?.isEnabled, true)
    }

    func testAddingTheSameURLAgainIsReportedNotDuplicated() async throws {
        _ = try await appDB.addSource(title: "First", url: "https://dup.example.com/feed", category: "tech")
        let first = try await appDB.feed(withURL: "https://dup.example.com/feed")
        try await appDB.updateFeedEnabled(feedID: try XCTUnwrap(first).id, isEnabled: false)

        let again = try await appDB.addSource(title: "Second", url: "https://dup.example.com/feed", category: "world")
        guard case .alreadyPresent(let feed) = again else { return XCTFail("expected .alreadyPresent, got \(again)") }
        XCTAssertEqual(feed.title, "First", "the existing row wins")
        XCTAssertEqual(feed.category, "tech")
        XCTAssertTrue(feed.isEnabled, "adding an existing source switches it back on")

        let count = try await appDB.dbPool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM feed WHERE url = ?", arguments: ["https://dup.example.com/feed"]) ?? 0
        }
        XCTAssertEqual(count, 1)
    }

    func testRemovingASourceRemovesItsStories() async throws {
        guard case .added(let feed) = try await appDB.addSource(title: "Gone", url: "https://gone.example.com/feed", category: "tech") else {
            return XCTFail("expected .added")
        }
        let article = Article(
            articleID: Article.makeID(feedID: feed.id, uniqueID: "1"), feedID: feed.id, uniqueID: "1",
            title: "Story", contentText: "Body", dateArrived: Date().sqliteString)
        _ = try await appDB.insertArticles([article])
        let before = try await appDB.articleCount(feedID: feed.id)
        XCTAssertEqual(before, 1)

        try await appDB.deleteFeed(feedID: feed.id)
        let gone = try await appDB.feed(withURL: feed.url)
        XCTAssertNil(gone)
        let after = try await appDB.articleCount(feedID: feed.id)
        XCTAssertEqual(after, 0)
        let orphanStatus = try await appDB.dbPool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM articleStatus WHERE articleID = ?", arguments: [article.articleID]) ?? 0
        }
        XCTAssertEqual(orphanStatus, 0, "articleStatus cascades with the article")
    }
}
