import XCTest
import GRDB
@testable import PulseFeed

/// The catalog reaches a database without disturbing it: existing rows keep their category and
/// enabled state and gain a topic, new sources arrive switched off, a row the person filed elsewhere
/// is left alone, and running it twice changes nothing.
final class CatalogSyncTests: XCTestCase {
    private var dir: URL!
    private var appDB: AppDatabase!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("CatalogSyncTests-\(UUID().uuidString)")
        appDB = try AppDatabase(path: dir.appendingPathComponent("t.sqlite").path)
    }

    override func tearDownWithError() throws {
        appDB = nil
        try? FileManager.default.removeItem(at: dir)
    }

    private func bundled() throws -> Catalog { try Catalog.load(from: CatalogTests.catalogURL) }

    private func feeds() async throws -> [Feed] {
        try await appDB.dbPool.read { db in try Feed.fetchAll(db, sql: "SELECT * FROM feed ORDER BY url") }
    }

    private func source(_ url: String, topic: String, title: String = "New") -> CatalogSource {
        CatalogSource(url: url, title: title, topic: topic, region: "global", type: "rss", pollInterval: 900, checkedAt: nil, itemCount: nil)
    }

    func testExistingInstallKeepsEnabledAndCategory() async throws {
        try await appDB.setCategoryEnabled("gaming", false)
        let before = try await feeds()
        let catalog = try bundled()
        let result = try await appDB.syncCatalog(catalog, enableNew: false)
        let existing = Set(before.map(\.url))
        let after = try await feeds()
        let kept = after.filter { existing.contains($0.url) }
        XCTAssertEqual(result.inserted, catalog.sources.count - before.count)
        XCTAssertEqual(result.topicsAssigned, 78, "79 seeds (no ESPN or Binance row) less the market-data row v12 retires")
        XCTAssertEqual(before.map(\.isEnabled), kept.map(\.isEnabled))
        XCTAssertEqual(before.map(\.category), kept.map(\.category))
        XCTAssertTrue(kept.allSatisfy { $0.topic != nil })
        XCTAssertTrue(after.filter { !existing.contains($0.url) }.allSatisfy { !$0.isEnabled }, "new catalog sources arrive off")
        XCTAssertEqual(after.first { $0.url == "https://www.mmafighting.com/rss/index.xml" }?.topic, "ufc")
    }

    func testNewSourcesArriveDisabled() async throws {
        var c = try bundled()
        _ = try await appDB.syncCatalog(c, enableNew: false)
        c.sources.append(source("https://example.com/nba.xml", topic: "nba"))
        let result = try await appDB.syncCatalog(c, enableNew: false)
        XCTAssertEqual(result.inserted, 1)
        let row = try await appDB.feed(withURL: "https://example.com/nba.xml")
        XCTAssertEqual(row?.isEnabled, false)
        XCTAssertEqual(row?.category, "sports")
        XCTAssertEqual(row?.topic, "nba")
        XCTAssertEqual(row?.pollInterval, 900)
    }

    func testEnableNewSwitchesNewSourcesOn() async throws {
        var c = try bundled()
        c.sources.append(source("https://example.com/f1.xml", topic: "f1"))
        _ = try await appDB.syncCatalog(c, enableNew: true)
        let row = try await appDB.feed(withURL: "https://example.com/f1.xml")
        XCTAssertEqual(row?.isEnabled, true)
    }

    func testSyncIsIdempotent() async throws {
        let c = try bundled()
        _ = try await appDB.syncCatalog(c, enableNew: false)
        let second = try await appDB.syncCatalog(c, enableNew: false)
        XCTAssertEqual(second.inserted, 0)
        XCTAssertEqual(second.topicsAssigned, 0)
    }

    func testUserAddedFeedNotInCatalogIsUntouched() async throws {
        _ = try await appDB.addSource(title: "Mine", url: "https://mine.example/feed", category: "tech")
        _ = try await appDB.syncCatalog(try bundled(), enableNew: false)
        let row = try await appDB.feed(withURL: "https://mine.example/feed")
        XCTAssertNil(row?.topic)
        XCTAssertEqual(row?.isEnabled, true)
    }

    func testUserRowInAnotherCategoryKeepsItsCategory() async throws {
        _ = try await appDB.addSource(title: "Filed by me", url: "https://example.com/politics.xml", category: "world")
        var c = try bundled()
        c.sources.append(source("https://example.com/politics.xml", topic: "politics"))
        _ = try await appDB.syncCatalog(c, enableNew: false)
        let row = try await appDB.feed(withURL: "https://example.com/politics.xml")
        XCTAssertEqual(row?.category, "world")
        XCTAssertNil(row?.topic)
    }

    func testSetTopicEnabledFlipsOnlyThatTopic() async throws {
        _ = try await appDB.syncCatalog(try bundled(), enableNew: false)
        try await appDB.setCategoryEnabled("sports", false)
        try await appDB.setTopicEnabled("ufc", true)
        let sports = try await feeds().filter { $0.category == "sports" }
        XCTAssertTrue(sports.filter { $0.topic == "ufc" }.allSatisfy(\.isEnabled))
        XCTAssertTrue(sports.filter { $0.topic != "ufc" }.allSatisfy { !$0.isEnabled })
    }

    // MARK: - A category tick never switches on sources nobody chose (audit 2026-10-22, finding 1)

    private func enabledURLs(category: String) async throws -> Set<String> {
        Set(try await appDB.dbPool.read { db in
            try String.fetchAll(db, sql: "SELECT url FROM feed WHERE category = ? AND isEnabled = 1", arguments: [category])
        })
    }

    func testReTickingACategoryDoesNotEnableCatalogSources() async throws {
        let seeded = try await enabledURLs(category: "sports")
        _ = try await appDB.syncCatalog(try bundled(), enableNew: false)
        try await appDB.setCategoryEnabled("sports", false)
        try await appDB.setCategoryEnabled("sports", true)
        let after = try await enabledURLs(category: "sports")
        XCTAssertEqual(after, seeded, "only the sources the install already had come back on")
    }

    func testATopicTurnedOnBecomesPartOfItsCategory() async throws {
        _ = try await appDB.syncCatalog(try bundled(), enableNew: false)
        try await appDB.setTopicEnabled("nfl", true)
        try await appDB.setCategoryEnabled("sports", false)
        try await appDB.setCategoryEnabled("sports", true)
        let nfl = try await appDB.dbPool.read { db in
            try Bool.fetchAll(db, sql: "SELECT isEnabled FROM feed WHERE topic = 'nfl'")
        }
        XCTAssertFalse(nfl.isEmpty)
        XCTAssertTrue(nfl.allSatisfy { $0 }, "a topic the person chose comes back with its category")
    }

    /// Rows a version-2 sync inserted before the marker existed are marked on the next sync.
    func testEarlierSyncedRowsAreMarked() async throws {
        let c = try bundled()
        let added = try XCTUnwrap(c.sources.first { ($0.since ?? 1) > 1 && $0.topic == "nfl" })
        try await appDB.dbPool.write { db in
            try db.execute(sql: "INSERT INTO feed (id, title, url, category, topic, type, pollInterval, isEnabled) VALUES ('x', 'X', ?, 'sports', 'nfl', 'rss', 900, 0)", arguments: [added.url])
        }
        _ = try await appDB.syncCatalog(c, enableNew: false, previousVersion: 2)
        try await appDB.setCategoryEnabled("sports", true)
        let row = try await appDB.feed(withURL: added.url)
        XCTAssertEqual(row?.isEnabled, false)
    }

    // MARK: - Audit round 2 (2026-10-22): A, B and the backfill

    /// Food and Life hold only catalog sources: ticking one on is choosing it.
    func testACategoryOfOnlyCatalogSourcesCanBeTickedOn() async throws {
        _ = try await appDB.syncCatalog(try bundled(), enableNew: false)
        try await appDB.setCategoryEnabled("food", true)
        let on = try await appDB.dbPool.read { db in try Bool.fetchAll(db, sql: "SELECT isEnabled FROM feed WHERE category = 'food'") }
        XCTAssertFalse(on.isEmpty)
        XCTAssertTrue(on.allSatisfy { $0 })
        try await appDB.setCategoryEnabled("food", false)
        try await appDB.setCategoryEnabled("food", true)
        let again = try await appDB.dbPool.read { db in try Bool.fetchAll(db, sql: "SELECT isEnabled FROM feed WHERE category = 'food'") }
        XCTAssertTrue(again.allSatisfy { $0 }, "chosen once, it comes back with its category")
    }

    func testASourceSwitchedOnByHandSurvivesAReTick() async throws {
        _ = try await appDB.syncCatalog(try bundled(), enableNew: false)
        let nflRow = try await appDB.dbPool.read { db in try Feed.fetchOne(db, sql: "SELECT * FROM feed WHERE topic = 'nfl'") }
        let nfl = try XCTUnwrap(nflRow)
        try await appDB.updateFeedEnabled(feedID: nfl.id, isEnabled: true)
        try await appDB.setCategoryEnabled("sports", false)
        try await appDB.setCategoryEnabled("sports", true)
        let row = try await appDB.feed(withURL: nfl.url)
        XCTAssertEqual(row?.isEnabled, true)
    }

    func testAddingACatalogURLBySettingsIsAChoice() async throws {
        _ = try await appDB.syncCatalog(try bundled(), enableNew: false)
        let mlbRow = try await appDB.dbPool.read { db in try Feed.fetchOne(db, sql: "SELECT * FROM feed WHERE topic = 'mlb'") }
        let mlb = try XCTUnwrap(mlbRow)
        _ = try await appDB.addSource(title: mlb.title, url: mlb.url, category: "sports")
        try await appDB.setCategoryEnabled("sports", false)
        try await appDB.setCategoryEnabled("sports", true)
        let row = try await appDB.feed(withURL: mlb.url)
        XCTAssertEqual(row?.isEnabled, true)
    }

    /// The backfill for rows a v2 sync inserted runs once (the first sync after version 2), and also
    /// marks a row whose source has since left the catalog (Blockworks on one install).
    func testBackfillRunsOnceAndCoversRemovedSources() async throws {
        let c = try bundled()
        try await appDB.dbPool.write { db in
            try db.execute(sql: "INSERT INTO feed (id, title, url, category, topic, type, pollInterval, isEnabled) VALUES ('gone', 'Gone', 'https://removed.example/feed', 'crypto', 'crypto', 'rss', 900, 0)")
        }
        _ = try await appDB.syncCatalog(c, enableNew: false, previousVersion: 2)
        try await appDB.setCategoryEnabled("crypto", true)
        let gone = try await appDB.feed(withURL: "https://removed.example/feed")
        XCTAssertEqual(gone?.isEnabled, false)

        // A chosen topic turned off later is not re-marked by a later sync.
        try await appDB.setTopicEnabled("nfl", true)
        try await appDB.setTopicEnabled("nfl", false)
        _ = try await appDB.syncCatalog(c, enableNew: false, previousVersion: 3)
        try await appDB.setCategoryEnabled("sports", true)
        let nfl = try await appDB.dbPool.read { db in try Bool.fetchAll(db, sql: "SELECT isEnabled FROM feed WHERE topic = 'nfl'") }
        XCTAssertTrue(nfl.allSatisfy { $0 })
    }

    /// One hand-added source in Food does not stop a tick from choosing Food's catalog sources (round 3, minor 5).
    func testOneHandAddedSourceDoesNotBlockChoosingACategory() async throws {
        _ = try await appDB.syncCatalog(try bundled(), enableNew: false)
        _ = try await appDB.addSource(title: "My bakery", url: "https://bakery.example/feed", category: "food")
        try await appDB.setCategoryEnabled("food", false)
        try await appDB.setCategoryEnabled("food", true)
        let on = try await appDB.dbPool.read { db in try Bool.fetchAll(db, sql: "SELECT isEnabled FROM feed WHERE category = 'food'") }
        XCTAssertTrue(on.count > 1 && on.allSatisfy { $0 })
    }

    /// An OPML import is choosing its sources, and the count is of real additions (round 3, minor 2).
    func testImportingOPMLChoosesItsSources() async throws {
        _ = try await appDB.syncCatalog(try bundled(), enableNew: false)
        let nflRow = try await appDB.dbPool.read { db in try Feed.fetchOne(db, sql: "SELECT * FROM feed WHERE topic = 'nfl'") }
        let nfl = try XCTUnwrap(nflRow)
        let added = try await appDB.importFeeds([
            OPMLService.OPMLFeed(title: nfl.title, url: nfl.url, homePageURL: nil, category: "sports"),
            OPMLService.OPMLFeed(title: "New", url: "https://new.example/feed", homePageURL: nil, category: "tech"),
        ])
        XCTAssertEqual(added, 2)
        try await appDB.setCategoryEnabled("sports", false)
        try await appDB.setCategoryEnabled("sports", true)
        let row = try await appDB.feed(withURL: nfl.url)
        XCTAssertEqual(row?.isEnabled, true)
    }

    /// Exporting and re-importing the app's own OPML changes nothing (audit round 4, N-2).
    func testOwnOPMLRoundTripChangesNothing() async throws {
        _ = try await appDB.syncCatalog(try bundled(), enableNew: false)
        let before = try await feeds()
        let xml = OPMLService().exportOPML(feeds: before)
        let parsed = OPMLService().parseOPML(data: Data(xml.utf8))
        XCTAssertEqual(parsed.count, before.count)
        let changed = try await appDB.importFeeds(parsed)
        XCTAssertEqual(changed, 0)
        let after = try await feeds()
        XCTAssertEqual(before.map(\.isEnabled), after.map(\.isEnabled))
        XCTAssertEqual(before.map(\.catalogAdded), after.map(\.catalogAdded))
    }

    /// A foreign OPML naming a catalog source that is off switches it on (importing it is choosing it);
    /// a source the person switched off themselves stays off.
    func testForeignOPMLChoosesCatalogSourcesButKeepsDeliberateOffs() async throws {
        _ = try await appDB.syncCatalog(try bundled(), enableNew: false)
        let nflRow = try await appDB.dbPool.read { db in try Feed.fetchOne(db, sql: "SELECT * FROM feed WHERE topic = 'nfl'") }
        let nfl = try XCTUnwrap(nflRow)
        let mine = try await appDB.addSource(title: "Mine", url: "https://mine.example/feed", category: "tech")
        guard case .added(let mineRow) = mine else { return XCTFail() }
        try await appDB.updateFeedEnabled(feedID: mineRow.id, isEnabled: false)
        let changed = try await appDB.importFeeds([
            OPMLService.OPMLFeed(title: nfl.title, url: nfl.url, homePageURL: nil, category: "sports"),
            OPMLService.OPMLFeed(title: "Mine", url: "https://mine.example/feed", homePageURL: nil, category: "tech"),
        ])
        XCTAssertEqual(changed, 1)
        let nflAfter = try await appDB.feed(withURL: nfl.url)
        let mineAfter = try await appDB.feed(withURL: "https://mine.example/feed")
        XCTAssertEqual(nflAfter?.isEnabled, true)
        XCTAssertEqual(mineAfter?.isEnabled, false)
    }

    /// A backup this app exported before the on/off attribute existed is recognised by its title and
    /// leaves every existing source as it is (round 5 minor 5); the title names no person.
    func testAnOldFormatOwnBackupLeavesStateAlone() async throws {
        _ = try await appDB.syncCatalog(try bundled(), enableNew: false)
        let before = try await feeds()
        let old = OPMLService().exportOPML(feeds: before)
            .replacingOccurrences(of: #" pulsefeedEnabled="[01]""#, with: "", options: .regularExpression)
            .replacingOccurrences(of: OPMLService.exportTitle, with: "XBTDMT Feed Subscriptions")
        let data = Data(old.utf8)
        let changed = try await appDB.importFeeds(OPMLService().parseOPML(data: data), ownExport: OPMLService.isOwnExport(data))
        XCTAssertEqual(changed, 0)
        let after = try await feeds()
        XCTAssertEqual(before.map(\.isEnabled), after.map(\.isEnabled))
        XCTAssertFalse(OPMLService.exportTitle.contains("XBTDMT"))
    }

    func testV12RetiresTheMarketDataRows() async throws {
        let ids = try await appDB.dbPool.read { db in try String.fetchAll(db, sql: "SELECT id FROM feed") }
        XCTAssertFalse(ids.contains("feed-coingecko"))
        XCTAssertFalse(ids.contains("feed-binance-ws"))
    }

    func testV12KeepsARowThatHasStories() throws {
        let path = dir.appendingPathComponent("v11.sqlite").path
        let pool = try DatabasePool(path: path)
        try AppDatabase.migrator.migrate(pool, upTo: "v11_catalog_added")
        try pool.write { db in
            try db.execute(sql: "INSERT INTO article (articleID, feedID, uniqueID, title, dateArrived) VALUES ('a1', 'feed-coingecko', 'u1', 'Kept', datetime('now'))")
        }
        try AppDatabase.migrator.migrate(pool)
        let ids = try pool.read { db in try String.fetchAll(db, sql: "SELECT id FROM feed") }
        XCTAssertTrue(ids.contains("feed-coingecko"))
        XCTAssertFalse(ids.contains("feed-binance-ws"))
    }

    /// A tick never switches on a held-back catalog source nobody chose (arXiv starts off; Rest of World,
    /// Nature and Mixmag are never offered); a row someone chose behaves as before.
    func testTicksHoldBackUnchosenStartsOffAndNeverOfferedSources() async throws {
        let catalog = try bundled()
        let held = Catalog.heldBack(in: catalog)
        XCTAssertTrue(held.contains("https://rss.arxiv.org/rss/cs.AI"))
        XCTAssertTrue(held.contains("https://restofworld.org/feed/latest/"))
        try await appDB.syncCatalog(catalog, enableNew: false)
        try appDB.prepareFreshInstall()
        try await appDB.setCategoryEnabled("ai", true, holdBack: held)
        try await appDB.setTopicEnabled("world", true, holdBack: held)
        let on = Set(try await feeds().filter(\.isEnabled).map(\.url))
        XCTAssertFalse(on.contains("https://rss.arxiv.org/rss/cs.AI"))
        XCTAssertFalse(on.contains("https://restofworld.org/feed/latest/"))
        XCTAssertTrue(on.contains("https://deepmind.google/blog/rss.xml"), "the rest of the category comes on")
    }

    func testAChosenHeldBackRowStillFollowsItsCategory() async throws {
        let catalog = try bundled()
        try await appDB.syncCatalog(catalog, enableNew: false)
        // On an install in use the arXiv seed row is chosen (catalogAdded 0): a category re-tick keeps today's behaviour.
        try await appDB.setCategoryEnabled("ai", false)
        try await appDB.setCategoryEnabled("ai", true, holdBack: Catalog.heldBack(in: catalog))
        let arxiv = try await feeds().first { $0.url == "https://rss.arxiv.org/rss/cs.AI" }
        XCTAssertEqual(arxiv?.isEnabled, true)
    }
}
