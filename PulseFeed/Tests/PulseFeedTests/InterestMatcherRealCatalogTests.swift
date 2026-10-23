import XCTest
@testable import PulseFeed

/// The matcher against the real catalog, with the words an audit found it mishandled (2026-10-22):
/// a partial match never adds a follow, a topic name matches only as whole words, names such as R&B
/// and AT&T stay whole, one-letter phrases are dropped, and a leading "#" is not part of a name.
final class InterestMatcherRealCatalogTests: XCTestCase {
    private func catalog() throws -> Catalog { try Catalog.load(from: CatalogTests.catalogURL) }

    private func match(_ text: String, _ context: InterestContext = .topics) throws -> [InterestMatch] {
        InterestMatcher.wordMatch(InterestMatcher.phrases(text), catalog: try catalog(), context: context)
    }

    private func follows(_ m: [InterestMatch]) -> [String] {
        m.compactMap { if case .follow(let name, _) = $0 { return name } else { return nil } }
    }

    private func topics(_ m: [InterestMatch]) -> [String] {
        m.compactMap { if case .topic(let id) = $0 { return id } else { return nil } }
    }

    func testPartialMatchesNeverAddAFollow() throws {
        for word in ["home", "formula", "united", "real", "news"] {
            XCTAssertEqual(follows(try match(word)), [], word)
        }
    }

    func testTopicNamesMatchOnlyAsWholeWords() throws {
        for word in ["trumpets", "carpets", "underdogs"] { XCTAssertFalse(topics(try match(word)).contains("pets"), word) }
        XCTAssertFalse(topics(try match("baker mayfield")).contains("baking"))
        XCTAssertFalse(topics(try match("marshall")).contains("space"))
        XCTAssertFalse(topics(try match("homeschooling")).contains("real-estate"))
        XCTAssertFalse(topics(try match("formula")).contains("parenting"))
    }

    func testWholeWordTopicNamesStillMatch() throws {
        let m = try match("nba and f1")
        XCTAssertTrue(topics(m).contains("nba") && topics(m).contains("f1"), "\(m)")
        XCTAssertFalse(m.contains { if case .newSearch = $0 { return true } else { return false } }, "fully explained: no search")
    }

    func testAmpersandNamesAndTitlesStayWhole() {
        XCTAssertEqual(InterestMatcher.phrases("R&B, AT&T; Barnes & Noble\nTom and Jerry"), ["r&b", "at&t", "barnes & noble", "tom and jerry"])
    }

    func testOneLetterPhrasesAreDropped() {
        XCTAssertEqual(InterestMatcher.phrases("x, r, ai, f1"), ["ai", "f1"])
    }

    func testALeadingHashIsNotPartOfAName() throws {
        XCTAssertEqual(InterestMatcher.phrases("#Lakers, ##piastri"), ["lakers", "piastri"])
        XCTAssertTrue(follows(try match("#lakers")).contains("lakers"))
    }

    func testFollowsWithAHashSurviveTheStoredText() {
        let r = UrgencyRules.defaults.addingFollows(["#piastri", "lebron"])
        XCTAssertEqual(UrgencyRules.parse(r.asText).followed, ["piastri", "lebron"])
    }

    /// A followed name inside a longer phrase, as whole words, is still a follow ("lakers fan").
    func testAFollowInsideAPhraseCounts() throws {
        XCTAssertTrue(follows(try match("lakers fan")).contains("lakers"))
        XCTAssertTrue(follows(try match("arsenal fc")).contains("arsenal"))
        XCTAssertTrue(topics(try match("lakers fan")).contains("nba"))
    }

    /// A follow that is an everyday word ("heat", "eagles") is flagged in the catalog, so a phrase must
    /// name it fully or stand alone (audit round 4).
    func testEverydayFollowsAreFlagged() throws {
        let everyday: Set = ["who", "heat", "thunder", "eagles", "chiefs", "bills", "rangers", "lions", "panthers",
                             "avalanche", "masters", "everest", "sec", "duke", "alabama", "mercedes", "marathon", "mac"]
        for t in try catalog().topics {
            for f in t.follows where everyday.contains(f) {
                XCTAssertTrue((t.everydayFollows ?? []).contains(f), "\(t.id): \(f) is an everyday word and is not flagged")
            }
        }
    }

    /// Names typed the way people say them reach their follow and topic (audit round 4, N-1).
    func testFullNamesReachTheirFollowAndTopic() throws {
        let cases: [(String, String, String)] = [
            ("los angeles lakers", "lakers", "nba"), ("golden state warriors", "warriors", "nba"),
            ("dallas cowboys", "cowboys", "nfl"), ("boston bruins", "bruins", "nhl"), ("detroit lions", "lions", "nfl"),
            ("max verstappen", "verstappen", "f1"), ("lewis hamilton", "hamilton", "f1"), ("porsche 911", "porsche", "cars"),
            ("nintendo switch", "nintendo", "gaming"), ("miami heat", "heat", "nba"),
        ]
        for (typed, follow, topic) in cases {
            let m = try match(typed)
            XCTAssertTrue(follows(m).contains(follow), "\(typed) → \(m)")
            XCTAssertTrue(topics(m).contains(topic), "\(typed) → \(m)")
        }
    }

    func testAnEverydayNicknameAloneOrWithFillerIsTheTeam() throws {
        XCTAssertTrue(follows(try match("heat")).contains("heat"))
        XCTAssertTrue(follows(try match("eagles fan")).contains("eagles"))
    }

    /// Filler words need no search of their own ("lakers news" is the Lakers).
    func testFillerIsNotSearchedFor() throws {
        for typed in ["lakers news", "nba news", "lakers highlights", "ethereum news"] {
            XCTAssertFalse(try match(typed).contains { if case .newSearch = $0 { return true } else { return false } }, typed)
        }
    }

    /// A follow inside a phrase counts only when the rest is filler ("lakers fan", "arsenal fc"), never
    /// from an everyday phrase (audit round 3, Important 1).
    func testEverydayPhrasesDoNotBecomeFollows() throws {
        for phrase in ["heat pump", "steam cleaner", "rust belt", "masters degree", "everest base camp", "eagles concert"] {
            let m = try match(phrase)
            XCTAssertEqual(follows(m), [], phrase)
        }
        XCTAssertFalse(topics(try match("heat pump")).contains("nba"))
        XCTAssertFalse(topics(try match("eagles concert")).contains("nfl"))
    }
}
