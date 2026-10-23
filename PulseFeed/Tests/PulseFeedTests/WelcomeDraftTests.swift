import XCTest
@testable import PulseFeed

/// The welcome flow's choices, held in memory until Finish (spec §6).
final class WelcomeDraftTests: XCTestCase {
    private var catalog: Catalog!
    private var suite: String!
    private var d: UserDefaults!

    override func setUpWithError() throws {
        catalog = try Catalog.load(from: CatalogTests.catalogURL).forBuild(providers: ["balldontlie"])
        suite = "WelcomeDraftTests-\(UUID().uuidString)"
        d = UserDefaults(suiteName: suite)
    }

    override func tearDown() { d.removePersistentDomain(forName: suite) }

    private func pack(_ id: String) -> WelcomePack { WelcomePack.all.first { $0.id == id }! }

    func testEveryPackTopicExists() {
        XCTAssertEqual(WelcomePack.all.map(\.label), ["Markets desk", "Sports fan", "Tech & AI", "World desk", "Culture", "Life & home"])
        for p in WelcomePack.all { for t in p.topics { XCTAssertNotNil(catalog.topic(t), "\(p.id): \(t)") } }
    }

    func testPackTogglesAsAWhole() {
        var draft = WelcomeDraft.initial(d)
        draft.toggle(topic: "ai")
        draft.toggle(pack: pack("tech"))
        XCTAssertEqual(draft.topics, ["ai", "tech", "apple", "gadgets", "programming"])
        draft.toggle(pack: pack("tech"))
        XCTAssertEqual(draft.topics, [])
        draft.toggle(topic: "nba"); draft.toggle(topic: "nba")
        XCTAssertEqual(draft.topics, [])
    }

    func testCountsLine() {
        var draft = WelcomeDraft.initial(d)
        draft.toggle(pack: pack("tech"))
        let topics = Set(pack("tech").topics)
        let expected = catalog.sources.filter { topics.contains($0.topic) && $0.isOffered && $0.startsOff != true }.count
        let c = draft.counts(catalog: catalog)
        XCTAssertEqual(c.topics, 5)
        XCTAssertEqual(c.sources, expected)
        XCTAssertEqual(c.searches, 0)
        draft.typedMatches = [.newSearch(phrase: "austin housing", category: "finance")]
        draft.addedSites = [AddedSite(title: "Mine", url: "https://mine.example/feed", category: "tech")]
        XCTAssertEqual(draft.counts(catalog: catalog).searches, 1)
        XCTAssertEqual(draft.counts(catalog: catalog).sources, expected + 1)
    }

    func testSourcesOfferedOnlyAndRegionFirst() throws {
        var draft = WelcomeDraft.initial(d)
        draft.toggle(topic: "world")
        let world = try XCTUnwrap(draft.sources(catalog: catalog, region: "uk").first)
        XCTAssertEqual(world.topic.id, "world")
        XCTAssertFalse(world.sources.contains { $0.title == "Rest of World" })
        let regions = world.sources.map(\.region)
        if let lastUK = regions.lastIndex(of: "uk"), let firstOther = regions.firstIndex(where: { $0 != "uk" }) {
            XCTAssertLessThan(lastUK, firstOther, "\(regions)")
        }
        if let lastGlobal = regions.lastIndex(of: "global"), let firstRest = regions.firstIndex(where: { $0 != "uk" && $0 != "global" }) {
            XCTAssertLessThan(lastGlobal, firstRest, "\(regions)")
        }
    }

    func testArXivStartsOffButCanBeSwitchedOn() throws {
        var draft = WelcomeDraft.initial(d)
        draft.toggle(topic: "ai")
        let arxiv = try XCTUnwrap(catalog.sources.first { $0.title == "arXiv cs.AI" })
        XCTAssertFalse(draft.isOn(arxiv))
        draft.sourceSwitches[arxiv.url] = true
        XCTAssertTrue(draft.isOn(arxiv))
    }

    func testSuggestedFollowsComeFromPickedTopics() {
        var draft = WelcomeDraft.initial(d)
        XCTAssertEqual(draft.suggestedFollows(catalog: catalog), [])
        draft.toggle(topic: "nba")
        XCTAssertTrue(draft.suggestedFollows(catalog: catalog).contains(.follow(name: "lakers", topicID: "nba")))
        draft.toggle(pack: pack("sports")); draft.toggle(pack: pack("tech")); draft.toggle(pack: pack("markets"))
        XCTAssertLessThanOrEqual(draft.suggestedFollows(catalog: catalog).count, 24)
    }

    func testSuggestedFollowsNameEachOnlyOnce() {
        var draft = WelcomeDraft.initial(d)
        // nvidia is a follow of Markets, Tech and AI alike: one chip, under the first picked topic.
        draft.toggle(topic: "markets"); draft.toggle(topic: "tech"); draft.toggle(topic: "ai")
        let names = draft.suggestedFollows(catalog: catalog).compactMap { m -> String? in
            if case .follow(let name, _) = m { return name } else { return nil }
        }
        XCTAssertEqual(names.count, Set(names).count, "\(names)")
        XCTAssertTrue(draft.suggestedFollows(catalog: catalog).contains(.follow(name: "nvidia", topicID: "markets")))
    }

    func testLiveGamesOfferOnlyWithNBA() {
        var draft = WelcomeDraft.initial(d)
        draft.toggle(topic: "nfl")
        XCTAssertFalse(draft.wantsLiveGames)
        draft.follows = [.follow(name: "lakers", topicID: "nba")]
        XCTAssertTrue(draft.wantsLiveGames)
        draft.follows = []
        draft.toggle(topic: "nba")
        XCTAssertTrue(draft.wantsLiveGames)
    }

    func testMoneyTopicSuggestsInstruments() {
        var draft = WelcomeDraft.initial(d)
        draft.toggle(topic: "tech")
        draft.suggestInstrumentsIfEmpty(catalog: catalog)
        XCTAssertEqual(draft.instruments, [])
        draft.toggle(topic: "markets")
        draft.suggestInstrumentsIfEmpty(catalog: catalog)
        XCTAssertEqual(draft.instruments, MarketInstrument.suggested)
        draft.instruments = ["gold"]
        draft.suggestInstrumentsIfEmpty(catalog: catalog)
        XCTAssertEqual(draft.instruments, ["gold"])
    }

    func testSixthInstrumentRefused() {
        var draft = WelcomeDraft.initial(d)
        for id in ["bitcoin", "spy", "qqq", "gold", "dxy"] { XCTAssertTrue(draft.setInstrument(id, on: true)) }
        XCTAssertFalse(draft.setInstrument("oil", on: true))
        XCTAssertEqual(draft.instruments.count, 5)
        XCTAssertTrue(draft.setInstrument("spy", on: false))
        XCTAssertTrue(draft.setInstrument("oil", on: true))
    }

    func testTypedOnlyDraftCanAdvance() {
        var draft = WelcomeDraft.initial(d)
        XCTAssertFalse(WelcomeStep.topics.canAdvance(draft))
        draft.typedMatches = [.newSearch(phrase: "sourdough", category: "food")]
        XCTAssertTrue(WelcomeStep.topics.canAdvance(draft))
    }

    func testStepOrderAndSkips() {
        XCTAssertEqual(WelcomeStep.allCases.count, 7)
        XCTAssertEqual(WelcomeStep.sources.previous, .topics)
        XCTAssertEqual(WelcomeStep.welcome.next, .topics)
        XCTAssertNil(WelcomeStep.done.next)
        XCTAssertNil(WelcomeStep.welcome.previous)
        XCTAssertEqual(WelcomeStep.allCases.filter(\.isSkippable), [.sources, .follow, .alerts, .look])
    }

    func testMatchesToApplyAreUniqueTopicsFirst() {
        var draft = WelcomeDraft.initial(d)
        draft.toggle(topic: "nba")
        draft.typedMatches = [.topic(id: "nba"), .newSearch(phrase: "sourdough", category: "food")]
        draft.follows = [.follow(name: "lakers", topicID: "nba"), .follow(name: "lakers", topicID: "nba")]
        XCTAssertEqual(draft.matchesToApply(), [.topic(id: "nba"), .newSearch(phrase: "sourdough", category: "food"), .follow(name: "lakers", topicID: "nba")])
    }

    func testInitialReadsTheStoredSettings() {
        d.set("recap", forKey: AlertMode.defaultsKey)
        d.set(1800.0, forKey: SummaryComposer.intervalKey)
        d.set("stream", forKey: AppDesign.defaultsKey)
        d.set("dark", forKey: AppAppearance.defaultsKey)
        d.set(["bitcoin"], forKey: MarketInstrument.defaultsKey)
        d.set(true, forKey: "menubar_btc_capsule")
        let draft = WelcomeDraft.initial(d)
        XCTAssertEqual(draft.alertMode, .recapOnly)
        XCTAssertEqual(draft.recapInterval, 1800)
        XCTAssertEqual(draft.design, .stream)
        XCTAssertEqual(draft.appearance, .dark)
        XCTAssertEqual(draft.instruments, ["bitcoin"])
        XCTAssertTrue(draft.pricesInMenuBar)
        let fresh = WelcomeDraft.initial(UserDefaults(suiteName: "WelcomeDraftTests-empty-\(UUID().uuidString)")!)
        XCTAssertEqual(fresh.recapInterval, 900)
        XCTAssertEqual(fresh.alertMode, .breakingAndRecap)
    }

    /// Typed "NBA, Formula 1" must act like ticking them: sources shown, follows suggested, live-games card.
    func testTypedTopicsBehaveLikeTickedOnes() {
        var draft = WelcomeDraft.initial(d)
        draft.addTyped([.topic(id: "nba"), .follow(name: "lakers", topicID: "nba"), .newSearch(phrase: "sourdough", category: "food")])
        XCTAssertEqual(draft.topics, ["nba"])
        XCTAssertEqual(draft.follows, [.follow(name: "lakers", topicID: "nba")])
        XCTAssertEqual(draft.typedMatches, [.newSearch(phrase: "sourdough", category: "food")])
        XCTAssertEqual(draft.sources(catalog: catalog, region: "us").map(\.topic.id), ["nba"])
        XCTAssertFalse(draft.suggestedFollows(catalog: catalog).isEmpty)
        XCTAssertTrue(draft.wantsLiveGames)
        draft.addTyped([.topic(id: "nba")])
        XCTAssertEqual(draft.topics, ["nba"], "typing a picked topic again does not untick it")
    }
}
