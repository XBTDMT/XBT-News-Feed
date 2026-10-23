import Foundation

struct JSONFetchResult: Sendable {
    let articles: [Article]
    let priceUpdates: [PriceUpdate]
    let adaptivePollInterval: Int?     // nil = don't change feed pollInterval
    let shouldUpsert: Bool             // true = update existing articles (ESPN scores)
    var requests: Int = 1              // HTTP requests made (instrumentation)
    var bytes: Int = 0                 // bytes downloaded (instrumentation)

    init(
        articles: [Article] = [], priceUpdates: [PriceUpdate] = [],
        adaptivePollInterval: Int? = nil, shouldUpsert: Bool = false,
        requests: Int = 1, bytes: Int = 0
    ) {
        self.articles = articles
        self.priceUpdates = priceUpdates
        self.adaptivePollInterval = adaptivePollInterval
        self.shouldUpsert = shouldUpsert
        self.requests = requests
        self.bytes = bytes
    }
}

struct JSONFetcher: Sendable {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// `knownUniqueIDs`: uniqueIDs already stored for this feed, so item-per-request APIs
    /// (Hacker News) only fetch what is new.
    func fetch(feed: Feed, knownUniqueIDs: Set<String> = []) async throws -> JSONFetchResult {
        if feed.url.hasPrefix(BallDontLie.gamesPrefix) { return try await fetchBallDontLie(feed: feed) }
        switch feed.id {
        case "feed-hackernews":                 return try await fetchHackerNews(feed: feed, knownUniqueIDs: knownUniqueIDs)
        case "feed-f1-schedule":                return try await fetchF1Schedule(feed: feed)
        case "feed-f1-results":                 return try await fetchF1Results(feed: feed)
        default:
            print("PulseFeed: [JSON] Unknown feed ID: \(feed.id)")
            return JSONFetchResult(requests: 0)
        }
    }

    // MARK: - Hacker News

    /// The top-N story IDs that are not already stored, in rank order.
    static func hnIDsToFetch(topIDs: [Int], knownUniqueIDs: Set<String>, limit: Int = 30) -> [Int] {
        topIDs.prefix(limit).filter { !knownUniqueIDs.contains(String($0)) }
    }

    private func fetchHackerNews(feed: Feed, knownUniqueIDs: Set<String>) async throws -> JSONFetchResult {
        let topStoriesURL = URL(string: "https://hacker-news.firebaseio.com/v0/topstories.json")!
        let (data, _) = try await session.data(from: topStoriesURL)
        let storyIDs = try JSONDecoder().decode([Int].self, from: data)

        // Only fetch stories we have not stored yet (was: all 30 every poll)
        let idsToFetch = Self.hnIDsToFetch(topIDs: storyIDs, knownUniqueIDs: knownUniqueIDs, limit: 30)
        let now = Date().sqliteString
        let session = self.session

        var articles: [Article] = []
        var bytes = data.count
        await withTaskGroup(of: (Article?, Int).self) { group in
            for id in idsToFetch {
                group.addTask {
                    guard let itemURL = URL(
                        string: "https://hacker-news.firebaseio.com/v0/item/\(id).json")
                    else { return (nil, 0) }
                    guard let (itemData, _) = try? await session.data(from: itemURL) else { return (nil, 0) }
                    guard let story = try? JSONDecoder().decode(HNStory.self, from: itemData),
                        let score = story.score, score >= 50,
                        let title = story.title
                    else { return (nil, itemData.count) }

                    let uniqueID = String(story.id)
                    let storyURL =
                        story.url ?? "https://news.ycombinator.com/item?id=\(story.id)"
                    let article = Article(
                        articleID: Article.makeID(feedID: feed.id, uniqueID: uniqueID),
                        feedID: feed.id, uniqueID: uniqueID,
                        title: title,
                        url: storyURL,
                        contentText: "Score: \(score) | \(story.descendants ?? 0) comments",
                        author: story.by,
                        datePublished: story.time.map {
                            Date(timeIntervalSince1970: TimeInterval($0)).sqliteString
                        },
                        dateArrived: now,
                        priority: score >= 200 ? "important" : "fyi")
                    return (article, itemData.count)
                }
            }
            for await (article, count) in group {
                bytes += count
                if let article { articles.append(article) }
            }
        }

        return JSONFetchResult(articles: articles, requests: 1 + idsToFetch.count, bytes: bytes)
    }


    // MARK: - F1 Schedule

    private func fetchF1Schedule(feed: Feed) async throws -> JSONFetchResult {
        let url = URL(string: "https://api.jolpi.ca/ergast/f1/current.json")!
        let (data, _) = try await session.data(from: url)
        let response = try JSONDecoder().decode(F1Response.self, from: data)

        let now = Date().sqliteString
        guard let races = response.MRData.RaceTable?.Races else {
            return JSONFetchResult()
        }

        let articles = races.map { race -> Article in
            let timeStr = race.time.map { " \($0)" } ?? ""
            return Article(
                articleID: Article.makeID(feedID: feed.id, uniqueID: "R\(race.round)"),
                feedID: feed.id, uniqueID: "R\(race.round)",
                title: "R\(race.round): \(race.raceName)",
                url: "https://www.formula1.com",
                contentText: "\(race.Circuit.circuitName) | \(race.date)\(timeStr)",
                dateArrived: now,
                priority: "fyi")
        }

        return JSONFetchResult(articles: articles, shouldUpsert: true)
    }

    // MARK: - F1 Results

    private func fetchF1Results(feed: Feed) async throws -> JSONFetchResult {
        let url = URL(
            string: "https://api.jolpi.ca/ergast/f1/current/last/results.json")!
        let (data, _) = try await session.data(from: url)
        let response = try JSONDecoder().decode(F1Response.self, from: data)

        let now = Date().sqliteString
        guard let race = response.MRData.RaceTable?.Races.first else {
            return JSONFetchResult()
        }

        var contentLines: [String] = []
        for result in race.Results ?? [] {
            let driver = "\(result.Driver.givenName) \(result.Driver.familyName)"
            let time = result.Time?.time ?? result.status ?? ""
            contentLines.append("P\(result.position). \(driver) (\(result.Constructor.name)) \(time)")
        }

        let article = Article(
            articleID: Article.makeID(
                feedID: feed.id, uniqueID: "R\(race.round)-results"),
            feedID: feed.id, uniqueID: "R\(race.round)-results",
            title: "\(race.raceName) — Results",
            url: "https://www.formula1.com",
            contentText: contentLines.joined(separator: "\n"),
            summary: contentLines.prefix(3).joined(separator: " | "),
            dateArrived: now,
            priority: "important")

        return JSONFetchResult(articles: [article], shouldUpsert: true)
    }

}

// MARK: - Hacker News Models

private struct HNStory: Codable {
    let id: Int
    let type: String?
    let by: String?
    let time: Int?
    let title: String?
    let url: String?
    let score: Int?
    let descendants: Int?
}

// MARK: - F1 Models (Jolpica/Ergast)

private struct F1Response: Codable {
    let MRData: F1MRData
}

private struct F1MRData: Codable {
    let RaceTable: F1RaceTable?
}

private struct F1RaceTable: Codable {
    let Races: [F1Race]
}

private struct F1Race: Codable {
    let round: String
    let raceName: String
    let Circuit: F1Circuit
    let date: String
    let time: String?
    let Results: [F1Result]?
}

private struct F1Circuit: Codable {
    let circuitName: String
}

private struct F1Result: Codable {
    let position: String
    let Driver: F1Driver
    let Constructor: F1Constructor
    let Time: F1Time?
    let status: String?
}

private struct F1Driver: Codable {
    let givenName: String
    let familyName: String
}

private struct F1Constructor: Codable {
    let name: String
}

private struct F1Time: Codable {
    let time: String?
}
