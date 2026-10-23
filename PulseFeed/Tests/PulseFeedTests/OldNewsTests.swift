import XCTest
import GRDB
@testable import PulseFeed

/// A feed's back catalogue is not news. Stories published before the unread window arrive already
/// read (and count as told), so a new feed's 1,000-post archive never shows up as "1,000 new".
final class OldNewsTests: XCTestCase {
    private func makeDB() throws -> AppDatabase {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("OldNewsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return try AppDatabase(path: dir.appendingPathComponent("t.sqlite").path)
    }

    func testPublishedBeforeTheCutoffIsOldNews() {
        let now = Date()
        let cutoff = now.addingTimeInterval(-2 * 86400)
        let old = Article(articleID: "a", feedID: "f", uniqueID: "u", datePublished: now.addingTimeInterval(-10 * 86400).sqliteString, dateArrived: now.sqliteString)
        let fresh = Article(articleID: "b", feedID: "f", uniqueID: "v", datePublished: now.addingTimeInterval(-3600).sqliteString, dateArrived: now.sqliteString)
        let undated = Article(articleID: "c", feedID: "f", uniqueID: "w", dateArrived: now.sqliteString)
        XCTAssertTrue(old.isOldNews(before: cutoff))
        XCTAssertFalse(fresh.isOldNews(before: cutoff))
        XCTAssertFalse(undated.isOldNews(before: cutoff))
    }

    func testOldNewsArrivesAlreadyReadAndTold() async throws {
        let db = try makeDB()
        try await db.addFeed(title: "A", url: "https://a.example/feed", category: "tech")
        let feedID = try await db.dbPool.read { try Feed.fetchAll($0) }.first!.id
        let now = Date()
        let cutoff = now.addingTimeInterval(-2 * 86400)
        _ = try await db.insertArticles([
            Article(articleID: "old", feedID: feedID, uniqueID: "1", datePublished: now.addingTimeInterval(-30 * 86400).sqliteString, dateArrived: now.sqliteString),
            Article(articleID: "fresh", feedID: feedID, uniqueID: "2", datePublished: now.sqliteString, dateArrived: now.sqliteString),
            Article(articleID: "undated", feedID: feedID, uniqueID: "3", dateArrived: now.sqliteString),
        ], readIfPublishedBefore: cutoff)
        let status = try await db.dbPool.read { d in
            try ["old", "fresh", "undated"].map { id -> (Bool, Bool) in
                let s = try ArticleStatus.fetchOne(d, key: id)!
                return (s.isRead, s.isNotified)
            }
        }
        XCTAssertEqual(status[0].0, true); XCTAssertEqual(status[0].1, true)
        XCTAssertEqual(status[1].0, false); XCTAssertEqual(status[1].1, false)
        XCTAssertEqual(status[2].0, false)
    }

    func testMenuBarCountSkipsStoriesARecapAlreadyCovered() async throws {
        let db = try makeDB()
        try await db.addFeed(title: "A", url: "https://a.example/feed", category: "tech")
        let feedID = try await db.dbPool.read { try Feed.fetchAll($0) }.first!.id
        let now = Date().sqliteString
        _ = try await db.insertArticles([
            Article(articleID: "x", feedID: feedID, uniqueID: "1", dateArrived: now),
            Article(articleID: "y", feedID: feedID, uniqueID: "2", dateArrived: now),
        ])
        try await db.markNotified(ids: ["x"])
        let since = Date.distantPast
        let count = try await db.dbPool.read { try AppDatabase.newSinceCount($0, since: since) }
        XCTAssertEqual(count, 1)
    }
}
