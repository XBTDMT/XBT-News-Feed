import XCTest
@testable import PulseFeed

/// The Deck board's "Top stories · by coverage · 24h": a pure ranking of the stories the window
/// already observes. Score = sources × a recency half-life, inside a 24-hour window, ties to the
/// newer story. No SQL, no clock of its own.
final class TopStoriesTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func story(_ id: String, sources: Int, hoursAgo: Double, arrived: String? = nil) -> ArticleInfo {
        ArticleInfo(
            articleID: id, feedID: "f", title: id, url: nil, contentText: nil, summary: nil, imageURL: nil,
            datePublished: nil, dateArrived: arrived ?? now.addingTimeInterval(-hoursAgo * 3600).sqliteString,
            relevanceScore: nil, priority: nil, isRead: false, isStarred: nil, isSaved: nil, isNotified: nil,
            feedTitle: "Feed", feedCategory: "tech", otherSources: nil, sourceCount: sources)
    }

    private func ids(_ rows: [ArticleInfo]) -> [String] { rows.map(\.articleID) }

    // MARK: - Score

    func testScoreIsSourcesAtZeroAgeAndHalvesEveryHalfLife() {
        XCTAssertEqual(TopStories.score(sourceCount: 1, age: 0, halfLife: 3600), 1, accuracy: 1e-9)
        XCTAssertEqual(TopStories.score(sourceCount: 4, age: 0, halfLife: 3600), 4, accuracy: 1e-9)
        XCTAssertEqual(TopStories.score(sourceCount: 2, age: 3600, halfLife: 3600), 1, accuracy: 1e-9)
        XCTAssertEqual(TopStories.score(sourceCount: 4, age: 7200, halfLife: 3600), 1, accuracy: 1e-9)
    }

    func testScoreTreatsMissingCoverageAndFutureArrivalsAsOne() {
        // A primary always counts itself; a clock skew never boosts a story.
        XCTAssertEqual(TopStories.score(sourceCount: 0, age: 0, halfLife: 3600), 1, accuracy: 1e-9)
        XCTAssertEqual(TopStories.score(sourceCount: 1, age: -600, halfLife: 3600), 1, accuracy: 1e-9)
    }

    // MARK: - Rank

    func testCoverageOutranksRecencyInsideTheWindow() {
        let rows = [story("fresh-single", sources: 1, hoursAgo: 0), story("covered", sources: 4, hoursAgo: 3)]
        XCTAssertEqual(ids(TopStories.rank(rows, now: now, limit: 5)), ["covered", "fresh-single"])
    }

    func testRecencyDecidesBetweenEqualCoverage() {
        let rows = [story("older", sources: 2, hoursAgo: 5), story("newer", sources: 2, hoursAgo: 1)]
        XCTAssertEqual(ids(TopStories.rank(rows, now: now, limit: 5)), ["newer", "older"])
    }

    func testCoverageDecaysWithTheHalfLife() {
        // Half-life 12 h: a two-source story is worth one fresh single at exactly 12 h, less after.
        let beats = [story("single", sources: 1, hoursAgo: 0), story("pair", sources: 2, hoursAgo: 11)]
        XCTAssertEqual(ids(TopStories.rank(beats, now: now, limit: 5)), ["pair", "single"])
        let loses = [story("single", sources: 1, hoursAgo: 0), story("pair", sources: 2, hoursAgo: 13)]
        XCTAssertEqual(ids(TopStories.rank(loses, now: now, limit: 5)), ["single", "pair"])
    }

    func testStoriesOutsideTheWindowAreDroppedWhateverTheirCoverage() {
        let rows = [story("old-big", sources: 9, hoursAgo: 25), story("fresh", sources: 1, hoursAgo: 1)]
        XCTAssertEqual(ids(TopStories.rank(rows, now: now, limit: 5)), ["fresh"])
        XCTAssertEqual(ids(TopStories.rank(rows, now: now, limit: 5, window: 48 * 3600)), ["old-big", "fresh"])
    }

    func testUnparseableArrivalIsDropped() {
        let rows = [story("bad", sources: 5, hoursAgo: 0, arrived: "not a date"), story("ok", sources: 1, hoursAgo: 1)]
        XCTAssertEqual(ids(TopStories.rank(rows, now: now, limit: 5)), ["ok"])
    }

    func testLimitCapsTheResult() {
        let rows = (0..<8).map { story("s\($0)", sources: 1, hoursAgo: Double($0)) }
        XCTAssertEqual(TopStories.rank(rows, now: now, limit: 3).count, 3)
        XCTAssertEqual(ids(TopStories.rank(rows, now: now, limit: 3)), ["s0", "s1", "s2"])
        XCTAssertTrue(TopStories.rank(rows, now: now, limit: 0).isEmpty)
    }

    func testSingleSourceStoriesFillWhenClustersAreScarce() {
        let rows = [
            story("a", sources: 1, hoursAgo: 2), story("cluster", sources: 3, hoursAgo: 6),
            story("b", sources: 1, hoursAgo: 1), story("c", sources: 1, hoursAgo: 3),
        ]
        XCTAssertEqual(ids(TopStories.rank(rows, now: now, limit: 5)), ["cluster", "b", "a", "c"])
    }

    func testEmptyInputGivesEmptyOutput() {
        XCTAssertTrue(TopStories.rank([], now: now, limit: 5).isEmpty)
    }
}
