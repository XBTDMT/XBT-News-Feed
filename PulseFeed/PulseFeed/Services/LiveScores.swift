import Foundation

/// Live NBA scores from balldontlie with the person's own free key (G-2, D13). Same titles as the ESPN
/// scoreboard so every surface reads them alike; a followed team's live game asks for minute polling.
enum BallDontLie {
    static let gamesPrefix = "https://api.balldontlie.io/"

    private static let eastern: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "America/New_York")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Today's games by the league's own (US Eastern) date.
    static func gamesURL(now: Date) -> URL {
        var c = URLComponents(string: "https://api.balldontlie.io/v1/games")!
        c.queryItems = [URLQueryItem(name: "dates[]", value: eastern.string(from: now)), URLQueryItem(name: "per_page", value: "100")]
        // URLComponents leaves "[" and "]" alone in a query; encode them so every server reads the same name.
        c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "[", with: "%5B").replacingOccurrences(of: "]", with: "%5D")
        return c.url!
    }

    private struct Response: Decodable { let data: [Game] }
    private struct Team: Decodable { let abbreviation: String }
    private struct Game: Decodable {
        let id: Int
        let status_state: String?
        let period: Int?
        let time: String?
        let home_team_score: Int?
        let visitor_team_score: Int?
        let home_team: Team
        let visitor_team: Team
    }

    static func parseGames(_ data: Data, feedID: String, followed: Set<String>, now: Date) throws -> (articles: [Article], followedLive: Bool) {
        let games = try JSONDecoder().decode(Response.self, from: data).data
        let arrived = now.sqliteString
        let day = eastern.string(from: now)
        var followedLive = false
        let articles = games.map { g -> Article in
            let away = g.visitor_team.abbreviation, home = g.home_team.abbreviation
            let isFollowed = followed.contains(away) || followed.contains(home)
            let state = g.status_state ?? "unknown"
            if isFollowed && state == "in_progress" { followedLive = true }
            let title: String
            let summary: String
            switch state {
            case "scheduled":
                title = "\(away) @ \(home) — Scheduled"
                summary = "Scheduled"
            case "in_progress":
                title = "\(away) \(g.visitor_team_score ?? 0) - \(g.home_team_score ?? 0) \(home)"
                summary = ["Q\(g.period ?? 0)", g.time ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
            default:
                title = "\(away) \(g.visitor_team_score ?? 0) - \(g.home_team_score ?? 0) \(home) (Final)"
                summary = state == "final" ? "Final" : state.capitalized
            }
            let uniqueID = "bdl-\(g.id)"
            return Article(
                articleID: Article.makeID(feedID: feedID, uniqueID: uniqueID),
                feedID: feedID, uniqueID: uniqueID,
                title: title,
                url: "https://www.nba.com/games?date=\(day)",
                summary: summary,
                dateArrived: arrived,
                priority: isFollowed ? "important" : "normal")
        }
        return (articles, followedLive)
    }
}

extension JSONFetcher {
    /// Nothing (and no request) unless this install's live scores are balldontlie and a key exists.
    func fetchBallDontLie(feed: Feed, keys: ProviderKeyStore = .standard, now: Date = Date()) async throws -> JSONFetchResult {
        guard DataProviders.stored(.standard).effective(keys: keys).liveScores == .balldontlie,
              let key = keys.get(.balldontlie) else { return JSONFetchResult(requests: 0) }
        var request = URLRequest(url: BallDontLie.gamesURL(now: now))
        request.setValue(key, forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let followed = Set(NBATeams.abbreviations(followed: UrgencyRules.stored().followed))
        let r = try BallDontLie.parseGames(data, feedID: feed.id, followed: followed, now: now)
        return JSONFetchResult(articles: r.articles, adaptivePollInterval: r.followedLive ? 60 : 900,
                               shouldUpsert: true, bytes: data.count)
    }
}
