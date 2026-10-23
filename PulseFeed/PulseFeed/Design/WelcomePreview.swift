import Foundation

/// A headline in the welcome flow's preview pane.
struct PreviewHeadline: Equatable, Sendable {
    let title: String
    let source: String
    let topicLabel: String
    let date: Date?
}

/// The live preview (spec §6, from the Topics step on): real headlines from what the person picked, fetched
/// as they choose, from at most two sources a topic for the first six topics, cached for ten minutes. A
/// fetch that fails gives nothing, never an error, so the flow never waits on the network.
actor WelcomePreview {
    private let session: URLSession
    private var cache: [String: (at: Date, items: [PreviewHeadline])] = [:]
    static let cacheLife: TimeInterval = 600

    init(session: URLSession = FeedEngine.feedSession) {
        self.session = session
    }

    static func sourcesToSample(_ draft: WelcomeDraft, catalog: Catalog, region: String) -> [(CatalogSource, CatalogTopic)] {
        draft.sources(catalog: catalog, region: region).prefix(6).flatMap { group in
            group.sources.filter { $0.type == "rss" && draft.isOn($0) }.prefix(2).map { ($0, group.topic) }
        }
    }

    /// Newest first (undated last), one per title, at most `limit`.
    static func merge(_ items: [PreviewHeadline], limit: Int) -> [PreviewHeadline] {
        var seen = Set<String>()
        let sorted = items.sorted { a, b in
            switch (a.date, b.date) {
            case let (x?, y?): return x > y
            case (_?, nil): return true
            default: return false
            }
        }
        return Array(sorted.filter { seen.insert($0.title.lowercased()).inserted }.prefix(limit))
    }

    func headlines(for draft: WelcomeDraft, catalog: Catalog, region: String, limit: Int = 8) async -> [PreviewHeadline] {
        let sample = Self.sourcesToSample(draft, catalog: catalog, region: region)
        var all: [PreviewHeadline] = []
        await withTaskGroup(of: (String, [PreviewHeadline]?).self) { group in
            for (source, topic) in sample {
                if let hit = cache[source.url], Date().timeIntervalSince(hit.at) < Self.cacheLife {
                    all += hit.items
                    continue
                }
                let session = self.session
                group.addTask { (source.url, await Self.fetch(source, topic: topic, session: session)) }
            }
            for await (url, items) in group {
                guard let items else { continue }
                cache[url] = (Date(), items)
                all += items
            }
        }
        return Self.merge(all, limit: limit)
    }

    private static func fetch(_ source: CatalogSource, topic: CatalogTopic, session: URLSession) async -> [PreviewHeadline]? {
        guard let url = URL(string: source.url),
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let parsed = RSSFetcher.parseFeed(data) else { return nil }
        return RSSFetcher(session: session).normalize(parsed, feedID: "preview").prefix(5).compactMap { article in
            guard let title = article.title, !title.isEmpty else { return nil }
            return PreviewHeadline(title: title, source: source.title, topicLabel: topic.label, date: article.datePublished?.sqliteDate)
        }
    }
}
