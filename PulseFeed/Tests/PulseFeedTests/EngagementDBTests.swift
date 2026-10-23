import XCTest
import GRDB
@testable import PulseFeed

final class EngagementDBTests: XCTestCase {
    private func makeDB() throws -> AppDatabase {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("EngagementDBTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return try AppDatabase(path: dir.appendingPathComponent("t.sqlite").path)
    }

    func testEventsRoundTripJoinedToTheirFeedAndCategory() async throws {
        let db = try makeDB()
        try await db.addFeed(title: "Skift", url: "https://skift.example/feed", category: "travel")
        let feedID = try await db.feed(withURL: "https://skift.example/feed")!.id
        let now = Date().sqliteString
        _ = try await db.insertArticles([Article(articleID: "a1", feedID: feedID, uniqueID: "1", dateArrived: now, topics: "hotels,loyalty")])
        try await db.logEngagement([(event: .shown, articleID: "a1", value: nil), (event: .dwell, articleID: "a1", value: 42)])
        let rows = try await db.fetchEngagement(since: Date.distantPast)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.map(\.event).sorted(), ["dwell", "shown"])
        XCTAssertEqual(rows[0].feedID, feedID); XCTAssertEqual(rows[0].category, "travel"); XCTAssertEqual(rows[0].feedTitle, "Skift")
        XCTAssertEqual(rows.first(where: { $0.event == "dwell" })?.value, 42)
    }

    func testNotInterestedMarksReadAndLogsIt() async throws {
        let db = try makeDB()
        try await db.addFeed(title: "A", url: "https://a.example/feed", category: "tech")
        let feedID = try await db.dbPool.read { try Feed.fetchAll($0) }.first!.id
        _ = try await db.insertArticles([Article(articleID: "a1", feedID: feedID, uniqueID: "1", dateArrived: Date().sqliteString)])
        try await db.dismiss(articleID: "a1", log: true)
        let read = try await db.dbPool.read { try ArticleStatus.fetchOne($0, key: "a1")?.isRead ?? false }
        XCTAssertTrue(read)
        let events = try await db.fetchEngagement(since: Date.distantPast).map(\.event)
        XCTAssertEqual(events, ["dismissed"])
    }

    func testDismissWithoutLogMarksReadOnly() async throws {
        let db = try makeDB()
        try await db.addFeed(title: "A", url: "https://a.example/feed", category: "tech")
        let feedID = try await db.dbPool.read { try Feed.fetchAll($0) }.first!.id
        _ = try await db.insertArticles([Article(articleID: "a1", feedID: feedID, uniqueID: "1", dateArrived: Date().sqliteString)])
        try await db.dismiss(articleID: "a1", log: false)
        let read = try await db.dbPool.read { try ArticleStatus.fetchOne($0, key: "a1")?.isRead ?? false }
        XCTAssertTrue(read)
        let count = try await db.engagementCount()
        XCTAssertEqual(count, 0)
    }
}
