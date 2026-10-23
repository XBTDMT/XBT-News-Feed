import XCTest
import GRDB
@testable import PulseFeed

/// Finish writes the draft through the paths Settings uses, on a fresh install's database.
final class ApplyWelcomeTests: XCTestCase {
    private var dir: URL!
    private var appDB: AppDatabase!
    private var catalog: Catalog!
    private var suite: String!
    private var d: UserDefaults!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ApplyWelcomeTests-\(UUID().uuidString)")
        appDB = try AppDatabase(path: dir.appendingPathComponent("t.sqlite").path)
        catalog = try Catalog.load(from: CatalogTests.catalogURL).forBuild(providers: ["espn", "balldontlie"])
        try await appDB.syncCatalog(catalog, enableNew: false)
        try appDB.prepareFreshInstall()
        suite = "ApplyWelcomeTests-\(UUID().uuidString)"
        d = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        d.removePersistentDomain(forName: suite)
        appDB = nil
        try? FileManager.default.removeItem(at: dir)
    }

    private func enabledURLs() async throws -> Set<String> {
        Set(try await appDB.dbPool.read { db in try String.fetchAll(db, sql: "SELECT url FROM feed WHERE isEnabled = 1") })
    }

    private func pack(_ id: String) -> WelcomePack { WelcomePack.all.first { $0.id == id }! }

    func testFinishEnablesWhatWasPickedAndNothingElse() async throws {
        var draft = WelcomeDraft.initial(d)
        draft.toggle(pack: pack("tech"))
        _ = try await appDB.applyWelcome(draft, catalog: catalog, region: "us", runningDesign: .deck, defaults: d)
        let topics = Set(pack("tech").topics)
        let expected = Set(catalog.sources.filter { topics.contains($0.topic) && $0.isOffered && $0.startsOff != true }.map(\.url))
        let on = try await enabledURLs()
        XCTAssertEqual(on, expected)
    }

    func testNeverOfferedSourcesStayOff() async throws {
        var draft = WelcomeDraft.initial(d)
        draft.toggle(topic: "world")
        _ = try await appDB.applyWelcome(draft, catalog: catalog, region: "us", runningDesign: .deck, defaults: d)
        let on = try await enabledURLs()
        XCTAssertFalse(on.contains("https://restofworld.org/feed/latest/"))
    }

    func testASourceSwitchedOffStaysOff() async throws {
        var draft = WelcomeDraft.initial(d)
        draft.toggle(topic: "tech")
        let first = try XCTUnwrap(draft.sources(catalog: catalog, region: "us").first?.sources.first)
        draft.sourceSwitches[first.url] = false
        _ = try await appDB.applyWelcome(draft, catalog: catalog, region: "us", runningDesign: .deck, defaults: d)
        let on = try await enabledURLs()
        XCTAssertFalse(on.contains(first.url))
    }

    func testAddedSiteIsAdded() async throws {
        var draft = WelcomeDraft.initial(d)
        draft.toggle(topic: "tech")
        draft.addedSites = [AddedSite(title: "Mine", url: "https://mine.example/feed", category: "tech")]
        _ = try await appDB.applyWelcome(draft, catalog: catalog, region: "us", runningDesign: .deck, defaults: d)
        let on = try await enabledURLs()
        XCTAssertTrue(on.contains("https://mine.example/feed"))
    }

    func testFollowsBecomeScopedRulesAndInterests() async throws {
        var draft = WelcomeDraft.initial(d)
        draft.toggle(topic: "nba")
        draft.follows = [.follow(name: "lakers", topicID: "nba")]
        _ = try await appDB.applyWelcome(draft, catalog: catalog, region: "us", runningDesign: .deck, defaults: d)
        XCTAssertTrue(UrgencyRules.stored(d).followed.contains("sports: lakers"))
        let rows: [(String, Double, String)] = try await appDB.dbPool.read { db in
            try Row.fetchAll(db, sql: "SELECT keyword, weight, category FROM userInterest").map { ($0["keyword"], $0["weight"], $0["category"]) }
        }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.0, "lakers")
        XCTAssertEqual(rows.first?.1, 2.0)
        XCTAssertEqual(rows.first?.2, "sports")
    }

    func testTypedOnlyDraftApplies() async throws {
        var draft = WelcomeDraft.initial(d)
        draft.typedMatches = [.newSearch(phrase: "austin housing", category: "finance")]
        _ = try await appDB.applyWelcome(draft, catalog: catalog, region: "us", runningDesign: .deck, defaults: d)
        let searches = try await appDB.dbPool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM feed WHERE topic LIKE 'search:%' AND isEnabled = 1") ?? 0
        }
        XCTAssertEqual(searches, 1)
    }

    func testSettingsAreWritten() async throws {
        var draft = WelcomeDraft.initial(d)
        draft.toggle(topic: "markets")
        draft.alertMode = .recapOnly
        draft.recapInterval = 1800
        draft.appearance = .dark
        draft.instruments = ["bitcoin", "spy"]
        draft.pricesInMenuBar = true
        _ = try await appDB.applyWelcome(draft, catalog: catalog, region: "us", runningDesign: .deck, defaults: d)
        XCTAssertEqual(AlertMode.stored(d), .recapOnly)
        XCTAssertEqual(d.double(forKey: SummaryComposer.intervalKey), 1800)
        XCTAssertEqual(d.string(forKey: AppAppearance.defaultsKey), "dark")
        XCTAssertEqual(MarketInstrument.stored(d), ["bitcoin", "spy"])
        XCTAssertTrue(d.bool(forKey: "menubar_btc_capsule"))
        XCTAssertTrue(d.bool(forKey: WelcomeGate.completedKey))
    }

    func testRelaunchOnlyWhenTheDesignChanged() async throws {
        var draft = WelcomeDraft.initial(d)
        draft.toggle(topic: "tech")
        draft.design = .deck
        let same = try await appDB.applyWelcome(draft, catalog: catalog, region: "us", runningDesign: .deck, defaults: d)
        XCTAssertFalse(same)
        XCTAssertNil(d.string(forKey: AppDesign.defaultsKey))
        draft.design = .stream
        let changed = try await appDB.applyWelcome(draft, catalog: catalog, region: "us", runningDesign: .deck, defaults: d)
        XCTAssertTrue(changed)
        XCTAssertEqual(d.string(forKey: AppDesign.defaultsKey), "stream")
    }

    /// "Run the welcome again" on an install in use: picking a topic it already has leaves the sources the
    /// person set by hand as they are, and a source the flow never offers keeps its state.
    func testARerunKeepsHandSetSources() async throws {
        let dir2 = dir.appendingPathComponent("inuse")
        let inUse = try AppDatabase(path: dir2.appendingPathComponent("t.sqlite").path)
        try await inUse.syncCatalog(catalog, enableNew: false)
        let bbc = "https://feeds.bbci.co.uk/news/world/rss.xml"
        let found = try await inUse.feed(withURL: bbc)
        let row = try XCTUnwrap(found)
        try await inUse.updateFeedEnabled(feedID: row.id, isEnabled: false)
        let before = try await inUse.sourceStates()

        var draft = WelcomeDraft.initial(d)
        draft.current = WelcomeDraft.currentStates(before, catalog: catalog)
        draft.toggle(topic: "world")
        _ = try await inUse.applyWelcome(draft, catalog: catalog, region: "us", runningDesign: .deck, defaults: d)
        let after = try await inUse.sourceStates()
        XCTAssertEqual(after[bbc], false, "switched off by hand, stays off")
        let row2 = "https://restofworld.org/feed/latest/"
        XCTAssertEqual(after[row2], before[row2], "never offered: left as it was")
        XCTAssertEqual(after.filter { before[$0.key] != $0.value }, [:], "nothing the person did not touch changes")
    }

    func testARerunShowsTheCurrentState() {
        var draft = WelcomeDraft.initial(d)
        let bbc = catalog.sources.first { $0.url == "https://feeds.bbci.co.uk/news/world/rss.xml" }!
        draft.current = [bbc.url: false]
        XCTAssertFalse(draft.isOn(bbc))
        draft.sourceSwitches[bbc.url] = true
        XCTAssertTrue(draft.isOn(bbc))
    }

    /// A re-run can add a topic the install does not have: its sources come on as for a fresh pick.
    func testARerunCanAddATopicThatIsOff() async throws {
        let dir2 = dir.appendingPathComponent("inuse2")
        let inUse = try AppDatabase(path: dir2.appendingPathComponent("t.sqlite").path)
        try await inUse.syncCatalog(catalog, enableNew: false)
        let states = try await inUse.sourceStates()
        var draft = WelcomeDraft.initial(d)
        draft.current = WelcomeDraft.currentStates(states, catalog: catalog)
        let pets = catalog.sources.filter { $0.topic == "pets" && $0.isOffered }
        XCTAssertTrue(pets.allSatisfy { states[$0.url] == false }, "pets is off on this install")
        draft.toggle(topic: "pets")
        XCTAssertGreaterThan(draft.counts(catalog: catalog).sources, 0)
        XCTAssertTrue(pets.allSatisfy { draft.isOn($0) == !($0.startsOff ?? false) })
        _ = try await inUse.applyWelcome(draft, catalog: catalog, region: "us", runningDesign: .deck, defaults: d)
        let after = try await inUse.sourceStates()
        XCTAssertTrue(pets.allSatisfy { after[$0.url] == true }, "the new topic's sources are on")
    }

    func testCurrentStatesSpeakOnlyForTopicsThatAreOn() {
        let world = catalog.sources.filter { $0.topic == "world" }
        let travel = catalog.sources.filter { $0.topic == "travel" }
        var states: [String: Bool] = [:]
        for s in world { states[s.url] = false }
        states[world[0].url] = true
        for s in travel { states[s.url] = false }
        let current = WelcomeDraft.currentStates(states, catalog: catalog)
        XCTAssertEqual(current[world[0].url], true)
        XCTAssertEqual(current[world[1].url], false)
        XCTAssertNil(current[travel[0].url])
    }

    private func catalogAddedByURL(_ db: AppDatabase) async throws -> [String: Bool] {
        try await db.dbPool.read { db in
            var out: [String: Bool] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT url, catalogAdded FROM feed") { out[row["url"]] = row["catalogAdded"] }
            return out
        }
    }

    /// Finish chooses only what it turns on: a source it leaves off stays unchosen, so a later category
    /// tick (Settings › Sources › Categories) does not switch it on.
    func testFinishKeepsUnchosenSourcesUnchosen() async throws {
        var draft = WelcomeDraft.initial(d)
        draft.toggle(topic: "ai")
        draft.toggle(topic: "world")
        let bbc = "https://feeds.bbci.co.uk/news/world/rss.xml"
        draft.sourceSwitches[bbc] = false
        _ = try await appDB.applyWelcome(draft, catalog: catalog, region: "us", runningDesign: .deck, defaults: d)
        for c in ["ai", "world"] {
            try await appDB.setCategoryEnabled(c, false)
            try await appDB.setCategoryEnabled(c, true)
        }
        let on = try await enabledURLs()
        XCTAssertFalse(on.contains("https://rss.arxiv.org/rss/cs.AI"), "startsOff, never chosen")
        XCTAssertFalse(on.contains("https://restofworld.org/feed/latest/"), "never offered")
        XCTAssertFalse(on.contains(bbc), "switched off in the flow")
    }

    /// A re-run that switches nothing leaves every row's chosen mark as it was.
    func testARerunLeavesChosenMarksAlone() async throws {
        let inUse = try AppDatabase(path: dir.appendingPathComponent("inuse3/t.sqlite").path)
        try await inUse.syncCatalog(catalog, enableNew: false)
        let before = try await catalogAddedByURL(inUse)
        var draft = WelcomeDraft.initial(d)
        draft.current = WelcomeDraft.currentStates(try await inUse.sourceStates(), catalog: catalog)
        draft.toggle(topic: "apple")
        _ = try await inUse.applyWelcome(draft, catalog: catalog, region: "us", runningDesign: .deck, defaults: d)
        let after = try await catalogAddedByURL(inUse)
        let states = try await inUse.sourceStates()
        let changed = after.filter { before[$0.key] != $0.value && states[$0.key] != true }
        XCTAssertEqual(changed, [:], "only a source Finish turned on may become chosen")
    }
}
