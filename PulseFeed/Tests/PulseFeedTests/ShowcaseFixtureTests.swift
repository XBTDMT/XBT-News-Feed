import XCTest
import GRDB
@testable import PulseFeed

/// The README's pictures are drawn from `ShowcaseFixture`: a plausible news day from fictional outlets on
/// reserved `.example` hosts, with clusters and a breaking story so every design has something to show.
final class ShowcaseFixtureTests: XCTestCase {
    private var dir: URL!
    private var appDB: AppDatabase!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ShowcaseFixtureTests-\(UUID().uuidString)")
        appDB = try AppDatabase(path: dir.appendingPathComponent("t.sqlite").path)
    }

    override func tearDownWithError() throws {
        appDB = nil
        try? FileManager.default.removeItem(at: dir)
    }

    func testFixtureInstallsIntoAThrowawayDatabase() async throws {
        try await ShowcaseFixture.install(in: appDB)
        let (primaries, clusters, breaking, clusterSizes) = try await appDB.dbPool.read { db in
            (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM article WHERE clusterID IS NULL") ?? 0,
             try Int.fetchOne(db, sql: "SELECT COUNT(DISTINCT clusterID) FROM article WHERE clusterID IS NOT NULL") ?? 0,
             try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM article JOIN articleStatus USING (articleID)
                WHERE article.clusterID IS NULL AND article.priority = 'breaking' AND articleStatus.isRead = 0
                """) ?? 0,
             try Int.fetchAll(db, sql: "SELECT 1 + COUNT(*) FROM article WHERE clusterID IS NOT NULL GROUP BY clusterID"))
        }
        XCTAssertGreaterThanOrEqual(primaries, 35)
        XCTAssertEqual(clusters, 3)
        XCTAssertGreaterThanOrEqual(breaking, 1)
        for size in clusterSizes { XCTAssertTrue((3...5).contains(size), "a cluster of \(size) sources") }
    }

    func testFixtureLeavesOnlyItsOwnOutlets() async throws {
        try await ShowcaseFixture.install(in: appDB)
        let titles = try await appDB.dbPool.read { db in try String.fetchAll(db, sql: "SELECT title FROM feed ORDER BY title") }
        XCTAssertEqual(titles, ShowcaseFixture.outlets.map(\.title).sorted())
        XCTAssertEqual(ShowcaseFixture.outlets.count, 8)
    }

    func testFixtureNamesNoRealOutlet() async throws {
        let catalog = try Catalog.load(from: CatalogTests.catalogURL)
        let real = Set(catalog.sources.map { $0.title.lowercased() })
        let realMonograms = Set(catalog.sources.map { Monogram.make($0.title) })
        for outlet in ShowcaseFixture.outlets {
            XCTAssertFalse(real.contains(outlet.title.lowercased()), outlet.title)
            // The coverage chips show monograms: a fixture chip must not read as a real outlet's ("BR", "GT").
            XCTAssertFalse(realMonograms.contains(Monogram.make(outlet.title)), "\(outlet.title) → \(Monogram.make(outlet.title))")
        }
        try await ShowcaseFixture.install(in: appDB)
        let urls = try await appDB.dbPool.read { db in
            try String.fetchAll(db, sql: """
                SELECT url FROM feed UNION ALL SELECT homePageURL FROM feed WHERE homePageURL IS NOT NULL
                UNION ALL SELECT url FROM article WHERE url IS NOT NULL
                """)
        }
        XCTAssertFalse(urls.isEmpty)
        for url in urls {
            XCTAssertTrue(URL(string: url)?.host?.hasSuffix(".example") ?? false, url)
        }
    }

    /// Nothing a view triggers on the showcase engine marks a story read: the brief's clear and the recap's
    /// "Mark these read" leave the fixture as it was.
    @MainActor
    func testAShowcaseEngineMarksNothingRead() async throws {
        try await ShowcaseFixture.install(in: appDB)
        let unread = { try await self.appDB.dbPool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM articleStatus WHERE isRead = 0") ?? 0 } }
        let before = try await unread()
        let engine = FeedEngine(appDB: appDB)
        engine.showcase(prices: ShowcaseFixture.prices, recap: ShowcaseFixture.recap, recapIDs: ShowcaseFixture.recapIDs,
                        digest: ShowcaseFixture.digest, headlines: ShowcaseFixture.topHeadlines,
                        lastTickAt: ShowcaseFixture.now, nextTickAt: ShowcaseFixture.now, stats: ShowcaseFixture.tickStats)
        let cleared = await engine.markBriefRead()
        await engine.markRecapRead()
        XCTAssertEqual(cleared, 0)
        let after = try await unread()
        XCTAssertEqual(after, before)
        XCTAssertGreaterThan(before, 30)
        XCTAssertEqual(engine.lastRecapIDs, ShowcaseFixture.recapIDs)
    }
}
