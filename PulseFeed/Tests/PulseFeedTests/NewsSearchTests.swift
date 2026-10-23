import XCTest
@testable import PulseFeed

/// An interest the catalog lacks becomes a news-search topic: a Google News RSS search in the reader's
/// region, stored as an ordinary feed, never twice.
final class NewsSearchTests: XCTestCase {
    func testURLEncodesThePhraseAndRegion() {
        let uk = NewsSearch.url(query: "Japanese whisky", region: "uk")?.absoluteString
        XCTAssertEqual(uk, "https://news.google.com/rss/search?q=Japanese%20whisky&hl=en-GB&gl=GB&ceid=GB:en")
        let us = NewsSearch.url(query: "AT&T earnings", region: "us")?.absoluteString
        XCTAssertEqual(us, "https://news.google.com/rss/search?q=AT%26T%20earnings&hl=en-US&gl=US&ceid=US:en")
        XCTAssertEqual(NewsSearch.url(query: "x", region: "global")?.absoluteString,
                       "https://news.google.com/rss/search?q=x&hl=en-US&gl=US&ceid=US:en")
    }

    func testTopicIDIsAStableSlug() {
        XCTAssertEqual(NewsSearch.topicID(for: "Japanese  Whisky!"), "search:japanese-whisky")
        XCTAssertEqual(NewsSearch.topicID(for: "  Formula E "), "search:formula-e")
        XCTAssertEqual(NewsSearch.topicID(for: "🍣 sushi"), NewsSearch.topicID(for: "🍣 Sushi"))
    }

    /// Phrases the slug alone cannot tell apart get a stable hash: "C#" after "C++" is its own search
    /// (audit 2026-10-22, finding 6).
    func testSlugCollisionsAreSeparated() {
        let ids = ["c++", "c#", "c", "🍣", "🏀", "!!!"].map(NewsSearch.topicID(for:))
        XCTAssertEqual(Set(ids).count, ids.count, "\(ids)")
        XCTAssertFalse(ids.contains("search:"))
        XCTAssertEqual(NewsSearch.topicID(for: "C#"), NewsSearch.topicID(for: "c#"), "stable across case")
    }

    func testSameSearchTwiceIsOneFeed() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("NewsSearchTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = try AppDatabase(path: dir.appendingPathComponent("t.sqlite").path)
        let a = try await db.addNewsSearch(phrase: "Japanese whisky", category: "food", region: "us")
        let b = try await db.addNewsSearch(phrase: "japanese whisky", category: "food", region: "us")
        XCTAssertEqual(a.id, b.id)
        XCTAssertEqual(a.topic, "search:japanese-whisky")
        XCTAssertEqual(a.category, "food")
        XCTAssertEqual(a.type, "rss")
        XCTAssertTrue(a.isEnabled)
        XCTAssertEqual(a.pollInterval, 900)
        let count = try await db.dbPool.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM feed WHERE topic = 'search:japanese-whisky'") }
        XCTAssertEqual(count, 1)
    }

    func testUnknownCategoryFallsBackToGeneral() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("NewsSearchTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = try AppDatabase(path: dir.appendingPathComponent("t.sqlite").path)
        let f = try await db.addNewsSearch(phrase: "curling", category: "drinks", region: "us")
        XCTAssertEqual(f.category, "general")
    }

    func testReAddingASwitchedOffSearchTurnsItBackOn() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("NewsSearchTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = try AppDatabase(path: dir.appendingPathComponent("t.sqlite").path)
        let a = try await db.addNewsSearch(phrase: "curling", category: "sports", region: "us")
        try await db.updateFeedEnabled(feedID: a.id, isEnabled: false)
        let b = try await db.addNewsSearch(phrase: "curling", category: "sports", region: "us")
        XCTAssertTrue(b.isEnabled)
        let stored = try await db.feed(withURL: a.url)
        XCTAssertEqual(stored?.isEnabled, true)
    }
}
