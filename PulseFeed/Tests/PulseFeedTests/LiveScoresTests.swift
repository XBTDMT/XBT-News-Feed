import XCTest
@testable import PulseFeed

final class LiveScoresTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-23T02:30:00Z")!

    /// The example game from balldontlie's docs (GET /v1/games), with the state the test needs.
    private func games(state: String, period: Int = 4, time: String = "Final", home: Int = 115, visitor: Int = 105) -> Data {
        Data("""
        {"data":[{"id":15907925,"date":"2025-01-05","season":2024,"status":"Final","status_state":"\(state)",
          "period":\(period),"time":"\(time)","postseason":false,"postponed":false,
          "home_team_score":\(home),"visitor_team_score":\(visitor),"datetime":"2025-01-05T23:00:00.000Z",
          "home_team":{"id":6,"conference":"East","division":"Central","city":"Cleveland","name":"Cavaliers","full_name":"Cleveland Cavaliers","abbreviation":"CLE"},
          "visitor_team":{"id":4,"conference":"East","division":"Southeast","city":"Charlotte","name":"Hornets","full_name":"Charlotte Hornets","abbreviation":"CHA"}}],
         "meta":{"next_cursor":25,"per_page":25}}
        """.utf8)
    }

    func testFinalGameFromTheDocsExample() throws {
        let r = try BallDontLie.parseGames(games(state: "final"), feedID: "f", followed: [], now: now)
        let a = try XCTUnwrap(r.articles.first)
        XCTAssertEqual(a.title, "CHA 105 - 115 CLE (Final)")
        XCTAssertEqual(a.uniqueID, "bdl-15907925")
        XCTAssertEqual(a.articleID, Article.makeID(feedID: "f", uniqueID: "bdl-15907925"))
        XCTAssertFalse(r.followedLive)
        XCTAssertEqual(a.priority, "normal")
    }

    func testInProgressFollowedGameAsksForMinutePolling() throws {
        let r = try BallDontLie.parseGames(games(state: "in_progress", period: 2, time: "5:31", home: 50, visitor: 54),
                                           feedID: "f", followed: ["CLE"], now: now)
        let a = try XCTUnwrap(r.articles.first)
        XCTAssertTrue(r.followedLive)
        XCTAssertEqual(a.title, "CHA 54 - 50 CLE")
        XCTAssertEqual(a.summary, "Q2 5:31")
        XCTAssertEqual(a.priority, "important")
    }

    func testUnfollowedLiveGameDoesNotSpeedUpPolling() throws {
        let r = try BallDontLie.parseGames(games(state: "in_progress", period: 1, time: "9:00"), feedID: "f", followed: ["LAL"], now: now)
        XCTAssertFalse(r.followedLive)
    }

    func testScheduledGame() throws {
        let r = try BallDontLie.parseGames(games(state: "scheduled", period: 0, time: ""), feedID: "f", followed: [], now: now)
        XCTAssertEqual(r.articles.first?.title, "CHA @ CLE — Scheduled")
    }

    func testGamesURLUsesTheEasternDate() {
        let url = BallDontLie.gamesURL(now: now).absoluteString
        XCTAssertTrue(url.hasPrefix("https://api.balldontlie.io/v1/games?"), url)
        XCTAssertTrue(url.contains("dates%5B%5D=2026-10-22"), url)
        XCTAssertTrue(url.contains("per_page=100"), url)
    }

    func testAbbreviationsFromFollows() {
        XCTAssertEqual(NBATeams.abbreviations(followed: ["sports: lakers", "boston celtics", "heat", "arsenal", "lakers"]),
                       ["LAL", "BOS", "MIA"])
        XCTAssertEqual(NBATeams.all.count, 30)
        XCTAssertEqual(Set(NBATeams.all.map(\.abbreviation)).count, 30)
    }

}
