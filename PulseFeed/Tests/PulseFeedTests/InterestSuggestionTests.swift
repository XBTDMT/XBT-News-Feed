import XCTest
@testable import PulseFeed

/// Only what the catalog places exactly, or fully explains, is applied; anything partial is offered as a
/// suggestion the person taps (G-5). A wrong suggestion therefore changes nothing. Audit round 5.
final class InterestSuggestionTests: XCTestCase {
    private func catalog() throws -> Catalog { try Catalog.load(from: CatalogTests.catalogURL) }

    private func sort(_ text: String, _ context: InterestContext = .topics) throws -> InterestResult {
        InterestMatcher.sort(InterestMatcher.phrases(text), catalog: try catalog(), context: context)
    }

    private func follows(_ m: [InterestMatch]) -> [String] {
        m.compactMap { if case .follow(let name, _) = $0 { return name } else { return nil } }
    }

    private func topics(_ m: [InterestMatch]) -> [String] {
        m.compactMap { if case .topic(let id) = $0 { return id } else { return nil } }
    }

    func testTrapPhrasesApplyNoFollowAndNoTopic() throws {
        for trap in ["tiger king", "bengal tiger", "the sinner", "bing crosby", "chuck norris", "hamilton musical",
                     "red bull energy drink", "san antonio spurs", "golden state killer", "space cowboys", "the open road",
                     "amazon rainforest", "ball python", "starship troopers", "mistral wind", "arsenal of democracy",
                     "apple pie", "barcelona trip", "rangers fc"] {
            let r = try sort(trap)
            XCTAssertEqual(follows(r.sure), [], trap)
            XCTAssertEqual(topics(r.sure), [], trap)
            XCTAssertTrue(r.sure.contains(.newSearch(phrase: trap, category: r.sure.compactMap {
                if case .newSearch(_, let c) = $0 { return c } else { return nil } }.first ?? "")), "\(trap) is still searched for")
        }
    }

    func testExactAndFullyExplainedNamesAreApplied() throws {
        for (typed, follow, topic) in [("max verstappen", "verstappen", "f1"), ("los angeles lakers", "lakers", "nba"),
                                       ("lakers fan", "lakers", "nba"), ("porsche 911", "porsche", "cars"),
                                       ("miami heat", "heat", "nba"), ("lakers news", "lakers", "nba")] {
            let r = try sort(typed)
            XCTAssertTrue(follows(r.sure).contains(follow), "\(typed) → \(r)")
            XCTAssertTrue(topics(r.sure).contains(topic), "\(typed) → \(r)")
        }
        XCTAssertTrue(topics(try sort("nba and f1").sure).contains("f1"))
    }

    func testANameWithAnotherWordIsSuggested() throws {
        let r = try sort("apple stock")
        XCTAssertTrue(follows(r.suggested).contains("apple"), "\(r)")
        XCTAssertEqual(follows(r.sure), [])
        XCTAssertTrue(r.sure.contains { if case .newSearch(phrase: "apple stock", _) = $0 { return true } else { return false } })
    }

    func testAnUnknownNameInTheFollowStepIsFollowedAndSearched() throws {
        let r = try sort("oscar piastri", .follow)
        XCTAssertTrue(follows(r.sure).contains("oscar piastri"))
    }

    /// A topic alias typed in the Follow step is also a follow ("ufc"), round 5 minor 3.
    func testATopicAliasInTheFollowStepIsAlsoAFollow() throws {
        let r = try sort("ufc", .follow)
        XCTAssertTrue(topics(r.sure).contains("ufc"))
        XCTAssertTrue(follows(r.sure).contains("ufc"))
    }

    func testCommonShortNamesHaveFullForms() throws {
        XCTAssertTrue(follows(try sort("man utd").sure).contains("manchester united"))
        XCTAssertTrue(follows(try sort("mahomes").sure).contains("patrick mahomes"))
    }

    /// "<a> and <b>" applies exactly what "<a>" and "<b>" apply alone, for every catalog name: nothing extra
    /// switched on, nothing silently dropped (audit round 6, N-1).
    func testAndJoinedNamesApplyExactlyEachPart() throws {
        let c = try catalog()
        var names = Set<String>()
        for t in c.topics {
            names.formUnion([t.id, t.label.lowercased()] + t.aliases.map { $0.lowercased() })
            for f in t.follows { names.formUnion(t.forms(of: f)) }
        }
        let f1 = Set(InterestMatcher.sort(["f1"], catalog: c, context: .topics).sure)
        var wrong: [String] = []
        // Names that themselves contain a spaced joiner ("food & drink", "points and miles") are split by
        // design when joined to another name; they are the only exclusions.
        for n in names.sorted() where n.count >= 2 && ![" and ", " & ", " + ", " or "].contains(where: n.contains) {
            let alone = Set(InterestMatcher.sort([n], catalog: c, context: .topics).sure)
            let joined = Set(InterestMatcher.sort(["\(n) and f1"], catalog: c, context: .topics).sure)
            if joined != alone.union(f1) { wrong.append(n) }
        }
        XCTAssertEqual(wrong, [], "\(wrong.count) names misbehave when joined: \(wrong.prefix(12))")
    }

    /// A search filed by word matching goes under General: a guess never turns a chip on (round 6, M-1).
    func testAWordMatchedSearchIsNotFiledUnderAGuessedChip() throws {
        let r = try sort("apple pie")
        XCTAssertTrue(r.sure.contains(.newSearch(phrase: "apple pie", category: "general")), "\(r)")
    }

    /// A topic alias followed in the Follow step stays inside its topic's chip (round 6, M-3).
    func testATopicAliasFollowedInTheFollowStepIsScopedToItsTopic() throws {
        let r = try sort("ufc", .follow)
        XCTAssertTrue(r.sure.contains(.follow(name: "ufc", topicID: "ufc")), "\(r)")
    }

    func testTheReadersOwnFollowsAreCatalogNames() throws {
        XCTAssertTrue(follows(try sort("lebron james").sure).contains("lebron"))
        XCTAssertTrue(follows(try sort("luka doncic").sure).contains("luka"))
        XCTAssertTrue(topics(try sort("eth").sure).contains("crypto"))
    }

    /// An Oxford-comma list keeps its last item ("lakers, f1, and ufc"), round 7 I-1.
    func testAnOxfordCommaListKeepsItsLastItem() throws {
        let r = try sort("Lakers, F1, and UFC")
        XCTAssertTrue(topics(r.sure).contains("ufc"), "\(r)")
        XCTAssertFalse(r.sure.contains { if case .newSearch = $0 { return true } else { return false } }, "\(r)")
        let f = try sort("lebron, verstappen, and luka", .follow)
        XCTAssertTrue(f.sure.contains(.follow(name: "luka", topicID: "nba")), "\(f)")
        XCTAssertFalse(follows(f.sure).contains("and luka"))
    }

    func testAPhraseOfOnlyJoinersOrFillerIsNothing() {
        XCTAssertEqual(InterestMatcher.phrases("and, or, &"), [])
        XCTAssertEqual(InterestMatcher.phrases("x, news and fans"), ["news and fans"], "filler is still searched for")
        XCTAssertEqual(InterestMatcher.phrases("nba,and f1"), ["nba", "f1"])
    }

    /// How people type names with apostrophes and dots (round 7 m-5).
    func testApostrophesAndDotsAreNotWordBreaks() throws {
        XCTAssertTrue(try sort("christies").sure.contains { if case .follow = $0 { return true } else { return false } })
        XCTAssertTrue(topics(try sort("u.s.").sure).contains("us-news"))
    }

    /// A joiner is trimmed only where a list put it ("…, and ufc"); a first item keeps its own words
    /// ("And Just Like That"), round 8 minor 1.
    func testOnlyAListJoinerIsTrimmed() {
        XCTAssertEqual(InterestMatcher.phrases("And Just Like That"), ["and just like that"])
        XCTAssertEqual(InterestMatcher.phrases("& Juliet, and #fredagain"), ["& juliet", "fredagain"])
    }

    /// A lone filler word is still searched for: nothing typed is dropped (round 8 minor 2).
    func testALoneFillerWordIsSearchedFor() throws {
        XCTAssertTrue(try sort("highlights").sure.contains(.newSearch(phrase: "highlights", category: "general")))
    }

    func testAnApostropheTypedAsASpaceStillMatches() throws {
        XCTAssertTrue(follows(try sort("giro d italia").sure).contains("giro d'italia"))
    }

    /// Every catalog name as the last item of an Oxford-comma list, through `phrases()`.
    func testEveryNameKeepsItsPlaceInAnOxfordCommaList() throws {
        let c = try catalog()
        var names = Set<String>()
        for t in c.topics {
            names.formUnion([t.label.lowercased()] + t.aliases.map { $0.lowercased() })
            for f in t.follows { names.formUnion(t.forms(of: f)) }
        }
        let lakers = Set(InterestMatcher.sort(["lakers"], catalog: c, context: .topics).sure)
        var wrong: [String] = []
        for n in names.sorted() where n.count >= 2 {
            let alone = Set(InterestMatcher.sort(InterestMatcher.phrases(n), catalog: c, context: .topics).sure)
            let listed = Set(InterestMatcher.sort(InterestMatcher.phrases("lakers, and \(n)"), catalog: c, context: .topics).sure)
            if listed != alone.union(lakers) { wrong.append(n) }
        }
        XCTAssertEqual(wrong, [], "\(wrong.prefix(12))")
    }
}
