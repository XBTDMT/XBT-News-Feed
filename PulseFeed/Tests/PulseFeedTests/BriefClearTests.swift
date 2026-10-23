import XCTest
import GRDB
@testable import PulseFeed

/// Clearing the brief is the "I am caught up" gesture, so it has to reach every unread story in an
/// enabled feed however it stands relative to the brief — older than its window, inside it, or
/// arrived behind it while it sat cached. Feeds that are switched off are left alone.
final class BriefClearTests: XCTestCase {
    private func makeDB() throws -> AppDatabase {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("BriefClearTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return try AppDatabase(path: dir.appendingPathComponent("t.sqlite").path)
    }

    private func isRead(_ db: AppDatabase, _ ids: [String]) async throws -> [Bool] {
        try await db.dbPool.read { d in
            try ids.map { try ArticleStatus.fetchOne(d, key: $0)?.isRead ?? false }
        }
    }

    func testClearingReadsPastPresentAndLaterArrivals() async throws {
        let db = try makeDB()
        try await db.addFeed(title: "A", url: "https://a.example/feed", category: "tech")
        let feedID = try await db.dbPool.read { try Feed.fetchAll($0) }.first!.id

        let old = Date().addingTimeInterval(-72 * 3600).sqliteString   // older than the brief's 24h window
        let now = Date().sqliteString                                  // what the brief covered
        let later = Date().addingTimeInterval(60).sqliteString         // landed behind the cached brief
        _ = try await db.insertArticles([
            Article(articleID: "past", feedID: feedID, uniqueID: "u1", dateArrived: old),
            Article(articleID: "present", feedID: feedID, uniqueID: "u2", dateArrived: now),
            Article(articleID: "future", feedID: feedID, uniqueID: "u3", dateArrived: later),
        ])

        let count = try await db.markAllUnreadReadInEnabledFeeds()

        XCTAssertEqual(count, 3)
        let read = try await isRead(db, ["past", "present", "future"])
        XCTAssertEqual(read, [true, true, true])
    }

    func testClearingLeavesDisabledFeedsAlone() async throws {
        let db = try makeDB()
        try await db.addFeed(title: "On", url: "https://on.example/feed", category: "tech")
        try await db.addFeed(title: "Off", url: "https://off.example/feed", category: "sport")
        let feeds = try await db.dbPool.read { try Feed.fetchAll($0) }
        let onID = feeds.first { $0.title == "On" }!.id
        let offID = feeds.first { $0.title == "Off" }!.id
        try await db.dbPool.write { try $0.execute(sql: "UPDATE feed SET isEnabled = 0 WHERE id = ?", arguments: [offID]) }

        let now = Date().sqliteString
        _ = try await db.insertArticles([
            Article(articleID: "shown", feedID: onID, uniqueID: "u1", dateArrived: now),
            Article(articleID: "hidden", feedID: offID, uniqueID: "u2", dateArrived: now),
        ])

        let count = try await db.markAllUnreadReadInEnabledFeeds()

        XCTAssertEqual(count, 1)
        let read = try await isRead(db, ["shown", "hidden"])
        XCTAssertEqual(read, [true, false])
    }

    /// The counts LEFT JOIN articleStatus and read a missing row as unread, so an UPDATE alone
    /// would leave such a story counted and the badge would never reach zero.
    func testAStoryWithNoStatusRowIsAlsoCleared() async throws {
        let db = try makeDB()
        try await db.addFeed(title: "A", url: "https://a.example/feed", category: "tech")
        let feedID = try await db.dbPool.read { try Feed.fetchAll($0) }.first!.id
        _ = try await db.insertArticles([
            Article(articleID: "orphan", feedID: feedID, uniqueID: "u1", dateArrived: Date().sqliteString),
        ])
        try await db.dbPool.write { try $0.execute(sql: "DELETE FROM articleStatus WHERE articleID = 'orphan'") }
        let before = try await db.dbPool.read { try AppDatabase.newSinceCount($0, since: nil) }
        XCTAssertEqual(before, 1, "a story with no status row must start out counted")

        let count = try await db.markAllUnreadReadInEnabledFeeds()

        XCTAssertEqual(count, 1)
        let read = try await isRead(db, ["orphan"])
        XCTAssertEqual(read, [true])
        let after = try await db.dbPool.read { try AppDatabase.newSinceCount($0, since: nil) }
        XCTAssertEqual(after, 0, "the badge must reach zero after a clear")
    }

    func testClearingLeavesStarredAndSavedFlagsIntact() async throws {
        let db = try makeDB()
        try await db.addFeed(title: "A", url: "https://a.example/feed", category: "tech")
        let feedID = try await db.dbPool.read { try Feed.fetchAll($0) }.first!.id
        _ = try await db.insertArticles([
            Article(articleID: "kept", feedID: feedID, uniqueID: "u1", dateArrived: Date().sqliteString),
        ])
        try await db.toggleStarred("kept")
        try await db.markSaved("kept")

        _ = try await db.markAllUnreadReadInEnabledFeeds()

        let status = try await db.dbPool.read { try ArticleStatus.fetchOne($0, key: "kept") }
        XCTAssertEqual(status?.isRead, true)
        XCTAssertEqual(status?.isStarred, true, "read is not unstar")
        XCTAssertEqual(status?.isSaved, true, "read is not unsave")
    }

    func testClearingTwiceIsAnEmptySecondPass() async throws {
        let db = try makeDB()
        try await db.addFeed(title: "A", url: "https://a.example/feed", category: "tech")
        let feedID = try await db.dbPool.read { try Feed.fetchAll($0) }.first!.id
        _ = try await db.insertArticles([
            Article(articleID: "a", feedID: feedID, uniqueID: "u1", dateArrived: Date().sqliteString),
        ])

        let first = try await db.markAllUnreadReadInEnabledFeeds()
        let second = try await db.markAllUnreadReadInEnabledFeeds()
        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 0, "a second clear has nothing left to do")
    }
}
