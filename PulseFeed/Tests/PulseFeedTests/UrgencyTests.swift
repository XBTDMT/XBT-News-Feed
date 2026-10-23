import XCTest
@testable import PulseFeed

/// Three tiers: urgent (interrupt now), headline (bold at the top of the next summary), summary.
/// The keyword layer is the always-on floor (it runs on critical battery too); the model decides
/// the rest. These tests pin the keyword layer, the market-move rule, the budget and the veto.
final class UrgencyTests: XCTestCase {
    /// The built-in rules plus the follows a person would add in the welcome flow (a new user's defaults
    /// follow nobody).
    let rules: UrgencyRules = {
        var r = UrgencyRules.defaults
        r.followed = ["celtics", "kite hollow"]
        return r
    }()

    func testWarOutbreakAndCeasefireAreUrgentTurningPoints() {
        XCTAssertEqual(UrgencyClassifier.keywordTier(title: "Russia and Ukraine agree ceasefire after Istanbul talks", category: "world", topic: nil, rules: rules), .urgent)
        XCTAssertEqual(UrgencyClassifier.keywordTier(title: "China launches invasion of Taiwan, Pentagon says", category: "world", topic: nil, rules: rules), .urgent)
        XCTAssertEqual(UrgencyClassifier.keywordTier(title: "Fighting continues along the Donbas front", category: "world", topic: nil, rules: rules), .summary)
    }
    func testFollowedEntitiesLowerTheBar() {
        XCTAssertEqual(UrgencyClassifier.keywordTier(title: "Celtics trade Jo Rivera to Hawks for two second-round picks", category: "sports", topic: nil, rules: rules), .urgent)
        XCTAssertEqual(UrgencyClassifier.keywordTier(title: "Kite Hollow announces 2027 North American tour dates", category: "music", topic: nil, rules: rules), .urgent)
        XCTAssertEqual(UrgencyClassifier.keywordTier(title: "Hawks trade a second-round pick to the Wizards", category: "sports", topic: nil, rules: rules), .summary)
    }
    func testMajorButNotTimeSensitiveIsAHeadline() {
        XCTAssertEqual(UrgencyClassifier.keywordTier(title: "Cristiano Ronaldo announces retirement from football", category: "sports", topic: nil, rules: rules), .headline)
        XCTAssertEqual(UrgencyClassifier.keywordTier(title: "Shohei Ohtani traded to the Yankees in blockbuster deal", category: "sports", topic: nil, rules: rules), .headline)
    }
    func testFrontierModelLaunchIsUrgent() {
        XCTAssertEqual(UrgencyClassifier.keywordTier(title: "OpenAI releases GPT-6 with real-time video", category: "ai", topic: nil, rules: rules), .urgent)
        XCTAssertEqual(UrgencyClassifier.keywordTier(title: "How to fine-tune a small model on your laptop", category: "ai", topic: nil, rules: rules), .summary)
    }
    func testVetoedPatternsNeverInterrupt() {
        var r = rules
        r.neverUrgent = ["rumor", "rivera"]
        XCTAssertEqual(UrgencyClassifier.keywordTier(title: "Celtics trade Jo Rivera to Hawks", category: "sports", topic: nil, rules: r), .headline)
        XCTAssertEqual(UrgencyClassifier.keywordTier(title: "Rumor: OpenAI to release GPT-6 next week", category: "ai", topic: nil, rules: r), .headline, "a veto demotes one tier: it still leads the next summary")
    }
    func testMarketMovesAreDecidedFromNumbers() {
        XCTAssertTrue(UrgencyClassifier.isMarketShock(instrument: "spy", change24h: -2.6, rules: rules))
        XCTAssertFalse(UrgencyClassifier.isMarketShock(instrument: "spy", change24h: -1.9, rules: rules))
        XCTAssertTrue(UrgencyClassifier.isMarketShock(instrument: "bitcoin", change24h: 7.4, rules: rules))
        XCTAssertFalse(UrgencyClassifier.isMarketShock(instrument: "bitcoin", change24h: 4.0, rules: rules))
        XCTAssertFalse(UrgencyClassifier.isMarketShock(instrument: "dxy", change24h: 3.0, rules: rules), "no threshold for DXY")
    }
    func testBudgetCapsUrgentAlerts() {
        var budget = UrgencyBudget(perHour: 3, perDay: 10)
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertTrue(budget.admit(at: t0)); XCTAssertTrue(budget.admit(at: t0 + 60)); XCTAssertTrue(budget.admit(at: t0 + 120))
        XCTAssertFalse(budget.admit(at: t0 + 180), "fourth in the hour is refused")
        XCTAssertTrue(budget.admit(at: t0 + 3700), "the hour window has moved on")
    }
    func testRulesRoundTripThroughText() {
        let text = rules.asText
        let parsed = UrgencyRules.parse(text)
        XCTAssertEqual(parsed.followed, rules.followed)
        XCTAssertEqual(parsed.spyThreshold, rules.spyThreshold)
        XCTAssertEqual(parsed.neverUrgent, rules.neverUrgent)
    }
}

/// The 15-minute summary: only new, unread, non-urgent stories; nothing new means no notification;
/// headlines lead; critical battery gets a plain top-three list instead of a model call.
final class SummaryNotificationTests: XCTestCase {
    func testNothingNewMeansNoNotification() {
        XCTAssertNil(SummaryComposer.plainSummary(headlines: [], others: []))
    }
    func testPlainSummaryLeadsWithHeadlinesThenTopThree() {
        let s = SummaryComposer.plainSummary(headlines: ["Ronaldo retires"], others: ["A", "B", "C", "D"])!
        XCTAssertEqual(s.title, "What's new · 5 stories")
        XCTAssertTrue(s.body.hasPrefix("Ronaldo retires"))
        XCTAssertTrue(s.body.contains("A") && s.body.contains("C") && !s.body.contains("D"))
    }
    func testDueOnlyAfterTheInterval() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertTrue(SummaryComposer.isDue(lastSentAt: nil, now: t0, interval: 900))
        XCTAssertFalse(SummaryComposer.isDue(lastSentAt: t0, now: t0 + 600, interval: 900))
        XCTAssertTrue(SummaryComposer.isDue(lastSentAt: t0, now: t0 + 901, interval: 900))
    }
}

/// The on-device model answers the recap prompt as JSON; anything that echoes the input markers,
/// comes back empty, or is not JSON is rejected so the plain list goes out instead.
final class RecapParserTests: XCTestCase {
    func testExtractsTheRecapField() {
        XCTAssertEqual(SummaryComposer.parseRecap(#"{"recap": "Ronaldo retired. Bitcoin fell 3%."}"#), "Ronaldo retired. Bitcoin fell 3%.")
    }
    func testStripsCodeFencesAndWhitespace() {
        XCTAssertEqual(SummaryComposer.parseRecap("```json\n{\"recap\":\"  Two things happened.  \"}\n```"), "Two things happened.")
    }
    func testRejectsEchoedMarkersEmptyAndNonJSON() {
        XCTAssertNil(SummaryComposer.parseRecap(#"{"recap": "LEAD: Mother convicted\nAuthorities cite"}"#))
        XCTAssertNil(SummaryComposer.parseRecap(#"{"recap": ""}"#))
        XCTAssertNil(SummaryComposer.parseRecap("Here is your recap: things happened."))
    }
    func testPromptCarriesNoMarkerTheModelCouldCopy() {
        let p = SummaryComposer.prompt(headlines: ["A"], others: ["B"])
        XCTAssertFalse(p.user.contains("HEADLINE:"))
        XCTAssertTrue(p.system.contains("\"recap\""))
    }

    // MARK: - Scoped patterns (a new user's alerts follow the topics they picked)

    private func tier(_ title: String, _ category: String, topic: String? = nil, _ r: UrgencyRules = .defaults) -> UrgencyTier {
        UrgencyClassifier.keywordTier(title: title, category: category, topic: topic, rules: r)
    }

    func testScopedPatternFiresOnlyInItsScope() {
        var r = UrgencyRules.defaults
        r.urgentPatterns = ["crypto: exchange hack"]
        XCTAssertEqual(tier("Crypto exchange hack drains $200m", "crypto", r), .urgent)
        XCTAssertEqual(tier("Crypto exchange hack drains $200m", "tech", r), .summary)
    }

    func testScopeMayBeATopic() {
        var r = UrgencyRules.defaults
        r.urgentPatterns = ["nba: trade deadline"]
        XCTAssertEqual(tier("Trade deadline: every deal", "sports", topic: "nba", r), .urgent)
        XCTAssertEqual(tier("Trade deadline: every deal", "sports", topic: "ufc", r), .summary)
    }

    func testColonInsidePatternIsNotAScope() {
        XCTAssertEqual(tier("Report: ceasefire talks resume", "world"), .headline, "report: still vetoes one tier")
    }

    func testNeutralDefaultsFollowNobody() {
        XCTAssertTrue(UrgencyRules.defaults.followed.isEmpty)
        XCTAssertEqual(tier("Celtics trade Jo Rivera to the Knicks", "sports"), .summary)
    }

    func testNeutralDefaultsKeepUniversalEvents() {
        XCTAssertEqual(tier("Ceasefire agreed in the north", "world"), .urgent)
        XCTAssertEqual(tier("Coup attempt reported in the capital", "politics"), .urgent)
    }

    func testCryptoAIAndMusicPatternsAreScoped() {
        XCTAssertEqual(tier("Exchange hacked, withdrawals frozen", "crypto"), .urgent)
        XCTAssertEqual(tier("Exchange hacked, withdrawals frozen", "sports"), .summary)
        XCTAssertEqual(tier("Anthropic announces Claude 6 release", "ai"), .urgent)
        XCTAssertEqual(tier("Anthropic announces Claude 6 release", "world"), .summary)
        XCTAssertEqual(tier("Band announces world tour", "music"), .urgent)
        XCTAssertEqual(tier("Band announces world tour", "travel"), .summary)
    }

    func testScopedPatternsRoundTripThroughText() {
        let parsed = UrgencyRules.parse(UrgencyRules.defaults.asText)
        XCTAssertEqual(parsed.urgentPatterns.filter { $0.contains(": ") }, UrgencyRules.defaults.urgentPatterns.filter { $0.contains(": ") })
    }

    // MARK: - Followed names match as whole words (audit round 2, finding C)

    private func followTier(_ title: String, follows: [String]) -> UrgencyTier {
        var r = UrgencyRules.defaults
        r.urgentPatterns = []; r.headlinePatterns = []
        r.followed = follows
        return UrgencyClassifier.keywordTier(title: title, category: "tech", topic: nil, rules: r)
    }

    func testAFollowedNameWithAnAmpersandIsOneName() {
        XCTAssertEqual(followTier("Apple to release new MacBook at October event", follows: ["at&t"]), .summary)
        XCTAssertEqual(followTier("AT&T announces layoffs", follows: ["at&t"]), .urgent)
    }

    func testAFollowedNameMatchesWholeWordsOnly() {
        XCTAssertEqual(followTier("Pineapple growers launch a new brand", follows: ["apple"]), .summary)
        XCTAssertEqual(followTier("Apple launches a new iPad", follows: ["apple"]), .urgent)
        XCTAssertEqual(followTier("Marlowe's agent announces a signing", follows: ["marlowe"]), .urgent)
        XCTAssertEqual(followTier("Porsches recalled over brakes", follows: ["porsche"]), .urgent, "a plural still counts")
        XCTAssertEqual(followTier("Kite Hollow.. announces 2027 tour dates", follows: ["kite hollow"]), .urgent)
    }

    /// The alert's reason names a follow only when that follow really matched (audit round 3, minor 1).
    @MainActor
    func testTheReasonLineUsesWholeWordFollows() {
        var r = UrgencyRules.defaults
        r.followed = ["apple"]
        let grapples = ArticleInfo(articleID: "a", feedID: "f", title: "Mathematician Grapples With AI", url: nil,
                                   contentText: nil, summary: nil, imageURL: nil, datePublished: nil,
                                   dateArrived: "2026-10-22 12:00:00", relevanceScore: nil, priority: "breaking",
                                   isRead: nil, isStarred: nil, isSaved: nil, isNotified: nil, feedTitle: "F",
                                   feedCategory: "ai", feedTopic: nil, otherSources: nil, sourceCount: 1)
        XCTAssertNotEqual(FeedEngine.reason(for: grapples, rules: r), "Apple")
    }

    func testAScopedFollowFiresOnlyUnderItsChip() {
        var r = UrgencyRules.defaults
        r.urgentPatterns = []; r.headlinePatterns = []; r.followed = ["sports: heat"]
        XCTAssertEqual(UrgencyClassifier.keywordTier(title: "Extreme heat warning signed into law", category: "world", topic: "us-news", rules: r), .summary)
        XCTAssertEqual(UrgencyClassifier.keywordTier(title: "Heat sign star guard", category: "sports", topic: "nba", rules: r), .urgent)
    }

    /// The reason line leads with the urgent pattern, shown without its scope (audit round 4, N-4).
    @MainActor
    func testTheReasonLineLeadsWithThePatternWithoutItsScope() {
        var r = UrgencyRules.defaults
        r.urgentPatterns = ["crypto: exchange hack"]; r.followed = ["crypto: bitcoin"]
        let story = ArticleInfo(articleID: "a", feedID: "f", title: "Bitcoin exchange hack drains $200m", url: nil,
                                contentText: nil, summary: nil, imageURL: nil, datePublished: nil,
                                dateArrived: "2026-10-22 12:00:00", relevanceScore: nil, priority: nil,
                                isRead: nil, isStarred: nil, isSaved: nil, isNotified: nil, feedTitle: "F",
                                feedCategory: "crypto", feedTopic: "crypto", otherSources: nil, sourceCount: 1)
        XCTAssertEqual(FeedEngine.reason(for: story, rules: r), "Exchange Hack")
    }

    /// Only a chip-level category (or the story's own topic) is a scope; any other "x: y" is a plain name
    /// ("Mission: Impossible"), round 5 minor 2.
    func testANameWithAColonIsNotAScope() {
        var r = UrgencyRules.defaults
        r.urgentPatterns = []; r.headlinePatterns = []; r.followed = ["mission: impossible"]
        XCTAssertEqual(UrgencyClassifier.keywordTier(title: "Mission: Impossible 9 announces its release date", category: "entertainment", topic: "movies", rules: r), .urgent)
        XCTAssertEqual(r.followedNames, ["mission: impossible"])
        var s = UrgencyRules.defaults
        s.followed = ["sports: heat"]
        XCTAssertEqual(s.followedNames, ["heat"])
    }

    func testFollowedNamesAreListedOnce() {
        var r = UrgencyRules.defaults
        r.followed = ["finance: apple", "tech: apple", "nvidia"]
        XCTAssertEqual(r.followedNames, ["apple", "nvidia"])
    }
}
