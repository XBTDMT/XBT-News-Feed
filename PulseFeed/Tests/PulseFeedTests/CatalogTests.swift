import XCTest
import GRDB
@testable import PulseFeed

/// The bundled catalog: every topic sits under one of the chip-level categories, every source under
/// one topic, nothing is duplicated, and every source a fresh install starts with is in it.
final class CatalogTests: XCTestCase {
    static let catalogURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("PulseFeed/Resources/Catalog/catalog.json")

    private func catalog() throws -> Catalog { try Catalog.load(from: Self.catalogURL) }

    func testBundledCatalogDecodes() throws {
        let c = try catalog()
        XCTAssertGreaterThan(c.version, 0)
        XCTAssertFalse(c.topics.isEmpty)
        XCTAssertFalse(c.sources.isEmpty)
    }

    func testCatalogHasNoProblems() throws {
        XCTAssertEqual(try catalog().problems(), [])
    }

    func testProblemsAreReported() {
        let c = Catalog(version: 1, topics: [
            CatalogTopic(id: "a", label: "A", category: "tech", group: .techScience, aliases: [], follows: [], regions: ["global"]),
            CatalogTopic(id: "a", label: "A again", category: "nonsense", group: .news, aliases: [], follows: [], regions: ["mars"]),
        ], sources: [
            CatalogSource(url: "https://x/feed", title: "X", topic: "a", region: "global", type: "rss", pollInterval: 600, checkedAt: nil, itemCount: nil),
            CatalogSource(url: "https://x/feed", title: "X2", topic: "missing", region: "moon", type: "rss", pollInterval: 600, checkedAt: nil, itemCount: nil),
        ])
        let p = c.problems()
        XCTAssertTrue(p.contains("duplicate topic id: a"), "\(p)")
        XCTAssertTrue(p.contains("topic a again: unknown category nonsense"), "\(p)")
        XCTAssertTrue(p.contains("topic a again: unknown region mars"), "\(p)")
        XCTAssertTrue(p.contains("duplicate source url: https://x/feed"), "\(p)")
        XCTAssertTrue(p.contains("source X2: unknown topic missing"), "\(p)")
        XCTAssertTrue(p.contains("source X2: unknown region moon"), "\(p)")
    }

    func testEveryCurrentFeedIsInTheCatalog() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("CatalogTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = try AppDatabase(path: dir.appendingPathComponent("t.sqlite").path)
        let seeded = try await db.dbPool.read { db in try String.fetchAll(db, sql: "SELECT url FROM feed") }
        let urls = Set(try catalog().sources.map(\.url))
        XCTAssertEqual(seeded.count, 78, "79 seeds (no ESPN or Binance row) less the market-data row v12 retires")
        XCTAssertEqual(Set(seeded).subtracting(urls), [])
    }

    func testTopicLookupAndSourcesByTopic() throws {
        let c = try catalog()
        XCTAssertEqual(c.topic("nba")?.category, "sports")
        XCTAssertTrue(c.sources(topic: "nba").contains { $0.url == "https://www.espn.com/espn/rss/nba/news" })
        XCTAssertNil(c.topic("no-such-topic"))
    }

    /// Every topic the welcome flow offers has at least three feed sources that `make check-catalog`
    /// fetched and parsed with the app's own code (JSON APIs and sockets do not count).
    func testEveryTopicHasThreeCheckedSources() throws {
        let c = try catalog()
        for t in c.topics {
            let checked = c.sources(topic: t.id).filter { $0.type == "rss" && $0.checkedAt != nil && ($0.itemCount ?? 0) > 0 }
            XCTAssertGreaterThanOrEqual(checked.count, 3, t.id)
        }
    }

    /// Topics whose outlets differ by country serve a US and a UK/EU reader alike.
    func testCountryShapedTopicsHaveUSAndEuropeanOutlets() throws {
        let c = try catalog()
        for id in ["world", "politics", "business", "economy", "markets", "soccer", "tennis", "rugby", "golf", "music"] {
            let regions = Set(c.sources(topic: id).map(\.region))
            XCTAssertTrue(regions.contains("us"), "\(id) has no US outlet")
            XCTAssertTrue(regions.contains("uk") || regions.contains("eu"), "\(id) has no UK/EU outlet")
        }
    }

    func testCatalogCoversTheSixGroups() throws {
        let c = try catalog()
        XCTAssertEqual(Set(c.topics.map(\.group)), Set(CatalogGroup.allCases))
        XCTAssertGreaterThanOrEqual(c.topics.count, 60)
        XCTAssertGreaterThanOrEqual(c.sources.count, 300)
    }

    func testBundledCatalogV5IsSound() throws {
        let c = try catalog()
        XCTAssertEqual(c.version, 5)
        XCTAssertEqual(c.problems(), [])
        XCTAssertFalse(c.sources.contains { $0.url.contains("coingecko") || $0.url.contains("binance") })
        XCTAssertEqual(c.sources.first { $0.title == "arXiv cs.AI" }?.startsOff, true)
        // The public copy's catalog has no ESPN source (the export cuts it); this flavour of the private
        // repo still reads the whole file. Either way, ESPN's NBA JSON source is tagged with its provider
        // (the RSS feed of the same title has none).
        XCTAssertTrue(c.sources.allSatisfy { $0.title != "ESPN NBA" || $0.type != "json_api" || $0.provider == "espn" })
        let bdl = try XCTUnwrap(c.sources.first { $0.provider == "balldontlie" })
        XCTAssertEqual(bdl.url, "https://api.balldontlie.io/v1/games")
        XCTAssertEqual(bdl.topic, "nba")
        XCTAssertEqual(bdl.type, "json_api")
    }

    func testPublicBuildCatalogHasNoESPN() throws {
        let c = try catalog()
        let pub = c.forBuild(providers: ["balldontlie"])
        XCTAssertFalse(pub.sources.contains { $0.provider == "espn" })
        XCTAssertTrue(pub.sources.contains { $0.provider == "balldontlie" })
        let priv = c.forBuild(providers: ["espn", "balldontlie"])
        XCTAssertEqual(priv.sources.count, c.sources.count)
    }

    func testNeverOfferedUntilChecked() throws {
        let c = try catalog()
        for title in ["Rest of World", "Nature", "Mixmag"] {
            XCTAssertEqual(c.sources.first { $0.title == title }?.isOffered, false, title)
        }
        XCTAssertEqual(c.sources.first { $0.title == "F1 Schedule" }?.isOffered, true)
    }

    func testUnknownProviderIsAProblem() {
        var src = CatalogSource(url: "https://x/feed", title: "X", topic: "a", region: "global", type: "json_api", pollInterval: 600, checkedAt: nil, itemCount: nil)
        src.provider = "yahoo"
        let c = Catalog(version: 1, topics: [
            CatalogTopic(id: "a", label: "A", category: "tech", group: .techScience, aliases: [], follows: [], regions: ["global"]),
        ], sources: [src])
        XCTAssertTrue(c.problems().contains("source X: unknown provider yahoo"), "\(c.problems())")
    }
}
