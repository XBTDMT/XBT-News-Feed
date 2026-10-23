import XCTest
@testable import PulseFeed

/// Typed interests → catalog topics, names to follow, and news searches for the rest. Nothing typed
/// is lost: what neither the catalog nor the model places becomes a search.
final class InterestMatcherTests: XCTestCase {
    private func topic(_ id: String, _ label: String, _ category: String, aliases: [String] = [], follows: [String] = []) -> CatalogTopic {
        CatalogTopic(id: id, label: label, category: category, group: .news, aliases: aliases, follows: follows, regions: ["global"])
    }

    private lazy var catalog = Catalog(version: 1, topics: [
        topic("nba", "NBA", "sports", aliases: ["basketball"], follows: ["lakers", "celtics"]),
        topic("f1", "Formula 1", "f1", aliases: ["f1", "formula one"], follows: ["verstappen", "ferrari"]),
        topic("apple", "Apple", "tech", aliases: ["iphone"]),
        topic("tech", "Tech", "tech", follows: ["apple", "nvidia"]),
        topic("baking", "Baking", "food", aliases: ["sourdough", "bread"]),
        topic("premier-league", "Premier League", "sports", aliases: ["epl"], follows: ["arsenal"]),
    ], sources: [])

    func testSplitsAndBoundsMessyInput() {
        XCTAssertEqual(InterestMatcher.phrases("Arsenal, sourdough; Formula E;\n  🍣 sushi,,"),
                       ["arsenal", "sourdough", "formula e", "🍣 sushi"])
        XCTAssertEqual(InterestMatcher.phrases("NBA, F1, nba"), ["nba", "f1"])
        let long = String(repeating: "verylongword ", count: 200) + ", tail"
        XCTAssertFalse(InterestMatcher.phrases(long).contains("tail"), "only the first 500 characters are read")
        XCTAssertEqual(InterestMatcher.phrases("   ,;  \n"), [])
    }

    func testWordMatchFindsTopicsAndFollows() {
        let m = InterestMatcher.wordMatch(["basketball", "verstappen"], catalog: catalog, context: .topics)
        XCTAssertEqual(m, [.topic(id: "nba"), .follow(name: "verstappen", topicID: "f1"), .topic(id: "f1")],
                       "following a name also turns its topic on, so stories about it arrive")
    }

    func testFollowAlsoTurnsItsTopicOn() {
        let m = InterestMatcher.wordMatch(["arsenal"], catalog: catalog, context: .topics)
        XCTAssertTrue(m.contains(.follow(name: "arsenal", topicID: "premier-league")))
        XCTAssertTrue(m.contains(.topic(id: "premier-league")))
    }

    func testUnmatchedInTopicsBecomesSearch() {
        XCTAssertEqual(InterestMatcher.wordMatch(["japanese whisky"], catalog: catalog, context: .topics),
                       [.newSearch(phrase: "japanese whisky", category: "general")])
    }

    func testUnmatchedInFollowBecomesFollowAndSearch() {
        XCTAssertEqual(InterestMatcher.wordMatch(["oscar piastri"], catalog: catalog, context: .follow),
                       [.follow(name: "oscar piastri", topicID: nil), .newSearch(phrase: "oscar piastri", category: "general")])
    }

    func testAmbiguousPhraseReturnsEveryExactMatch() {
        let m = InterestMatcher.wordMatch(["apple"], catalog: catalog, context: .topics)
        XCTAssertTrue(m.contains(.topic(id: "apple")))
        XCTAssertTrue(m.contains(.follow(name: "apple", topicID: "tech")))
    }

    func testShortSubstringsDoNotMatch() {
        // "f" or "ba" must not drag in Formula 1 or Baking.
        XCTAssertEqual(InterestMatcher.wordMatch(["ba"], catalog: catalog, context: .topics),
                       [.newSearch(phrase: "ba", category: "general")])
        let r = InterestMatcher.sort(["sourdough baking"], catalog: catalog, context: .topics)
        XCTAssertEqual(r.suggested, [.topic(id: "baking")], "two names side by side are a suggestion, not a choice")
    }

    /// The catalog places what it knows exactly, whatever the model says; the model only sorts the rest
    /// into a follow or a search and picks its chip; a phrase it skips is word-matched.
    func testCatalogWinsAndTheModelOnlySortsTheRest() {
        let answer = """
            Here you go:
            ```json
            [{"phrase": "arsenal", "kind": "other", "category": "motors"},
             {"phrase": "japanese whisky", "kind": "other", "category": "food"},
             {"phrase": "oscar piastri", "kind": "person_or_team", "category": "f1"},
             {"phrase": "curling", "kind": "topic", "category": "sports"}]
            ```
            """
        let m = InterestMatcher.parseModelAnswer(answer, phrases: ["arsenal", "japanese whisky", "oscar piastri", "curling", "basketball", "formula e"], catalog: catalog, context: .topics).sure
        XCTAssertTrue(m.contains(.follow(name: "arsenal", topicID: "premier-league")), "\(m)")
        XCTAssertTrue(m.contains(.topic(id: "premier-league")))
        XCTAssertFalse(m.contains(.newSearch(phrase: "arsenal", category: "motors")), "the model cannot override an exact catalog match")
        XCTAssertTrue(m.contains(.newSearch(phrase: "japanese whisky", category: "food")))
        XCTAssertTrue(m.contains(.follow(name: "oscar piastri", topicID: nil)))
        XCTAssertTrue(m.contains(.newSearch(phrase: "oscar piastri", category: "f1")))
        XCTAssertTrue(m.contains(.newSearch(phrase: "curling", category: "sports")))
        XCTAssertTrue(m.contains(.topic(id: "nba")), "a catalog phrase is word-matched: \(m)")
        XCTAssertTrue(m.contains(.newSearch(phrase: "formula e", category: "general")), "a phrase the answer skipped is word-matched: \(m)")
    }

    func testUnplacedPhrasesAreWhatTheModelSees() {
        XCTAssertEqual(InterestMatcher.unplaced(["arsenal", "japanese whisky", "nba"], catalog: catalog), ["japanese whisky"])
    }

    func testUnknownCategoryFromModelBecomesGeneral() {
        let answer = #"[{"phrase": "japanese whisky", "kind": "other", "topic": null, "category": "drinks"}]"#
        XCTAssertEqual(InterestMatcher.parseModelAnswer(answer, phrases: ["japanese whisky"], catalog: catalog, context: .topics).sure,
                       [.newSearch(phrase: "japanese whisky", category: "general")])
    }

    func testGarbageAnswerFallsBackEntirely() {
        XCTAssertEqual(InterestMatcher.parseModelAnswer("sorry, I can't", phrases: ["basketball"], catalog: catalog, context: .topics).sure,
                       [.topic(id: "nba")])
    }

    func testPromptCarriesNoURLsOrFollows() {
        let (system, user) = InterestMatcher.prompt(phrases: ["japanese whisky"])
        XCTAssertFalse((system + user).contains("http"))
        XCTAssertFalse((system + user).contains("verstappen"))
        XCTAssertTrue(system.contains("food"), "the chip-level categories are offered")
        XCTAssertTrue(user.contains("japanese whisky"))
    }

    /// A phrase only partly explained by the catalog keeps the topic and adds a search for the rest:
    /// "japanese whisky" is not just Asia news; "sourdough baking" is fully explained by Baking.
    func testPartialMatchAddsASearchForWhatItDoesNotCover() {
        var c = catalog
        c.topics.append(topic("asia", "Asia", "world", aliases: ["japanese", "japan"]))
        let r = InterestMatcher.sort(["japanese whisky"], catalog: c, context: .topics)
        XCTAssertEqual(r.sure, [.newSearch(phrase: "japanese whisky", category: "general")], "a guessed chip is never switched on")
        XCTAssertEqual(r.suggested, [.topic(id: "asia")], "a partial match is only suggested")
        XCTAssertEqual(InterestMatcher.wordMatch(["sourdough and baking"], catalog: c, context: .topics), [.topic(id: "baking")])
    }

    func testAFollowedNameAppearsOnceWhateverItsTopics() {
        var c = catalog
        c.topics.append(topic("soccer", "Football", "sports", follows: ["arsenal"]))
        let m = InterestMatcher.wordMatch(["arsenal"], catalog: c, context: .topics)
        XCTAssertEqual(m.filter { if case .follow = $0 { return true } else { return false } }.count, 1)
        XCTAssertTrue(m.contains(.topic(id: "premier-league")) && m.contains(.topic(id: "soccer")))
    }
}
