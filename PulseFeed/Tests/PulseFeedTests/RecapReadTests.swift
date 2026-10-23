import XCTest
import GRDB
@testable import PulseFeed

/// Reading the recap counts as reading the stories it covered — and their copies from other outlets.
/// Stories that arrive later stay unread; they belong to the next recap.
final class RecapReadTests: XCTestCase {
    private func makeDB() throws -> AppDatabase {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("RecapReadTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return try AppDatabase(path: dir.appendingPathComponent("t.sqlite").path)
    }

    func testMarkingARecapReadCoversItsStoriesAndTheirOtherOutlets() async throws {
        let db = try makeDB()
        try await db.addFeed(title: "A", url: "https://a.example/feed", category: "tech")
        let feedID = try await db.dbPool.read { try Feed.fetchAll($0) }.first!.id
        let now = Date().sqliteString
        _ = try await db.insertArticles([
            Article(articleID: "p1", feedID: feedID, uniqueID: "u1", dateArrived: now),
            Article(articleID: "s1", feedID: feedID, uniqueID: "u2", dateArrived: now, clusterID: "p1"),
            Article(articleID: "p2", feedID: feedID, uniqueID: "u3", dateArrived: now),
        ])

        try await db.markReadIncludingCluster(ids: ["p1"])

        let read = try await db.dbPool.read { d in
            try ["p1", "s1", "p2"].map { try ArticleStatus.fetchOne(d, key: $0)?.isRead ?? false }
        }
        XCTAssertEqual(read, [true, true, false])
    }

    func testEmptyRecapMarksNothing() async throws {
        let db = try makeDB()
        try await db.markReadIncludingCluster(ids: [])
    }

    func testRecapStoryIDsSurviveARelaunch() {
        let d = UserDefaults(suiteName: "RecapReadTests-\(UUID().uuidString)")!
        XCTAssertEqual(SummaryComposer.loadLastIDs(in: d), [])
        SummaryComposer.saveLastIDs(["a", "b"], in: d)
        XCTAssertEqual(SummaryComposer.loadLastIDs(in: d), ["a", "b"])
        SummaryComposer.saveLastIDs([], in: d)
        XCTAssertEqual(SummaryComposer.loadLastIDs(in: d), [])
    }
}
