import Foundation
import FeedKit

/// One source's result from `make check-catalog`.
struct CatalogCheck: Codable, Sendable, Equatable {
    var url: String
    var ok: Bool
    var itemCount: Int
    var error: String?
    /// Offline-shaped (`FetchErrorKind.transient`): says nothing about the source.
    var transient: Bool
}

/// `make check-catalog`: fetches every feed source in the catalog with the app's browser-shaped
/// User-Agent and parses it with the same FeedKit path Settings › Add source uses, so a source that
/// passes here is one the app can read.
enum CatalogChecker {
    /// Feed sources only: JSON APIs and sockets are not feeds and never count toward a topic's three.
    static func checkable(_ sources: [CatalogSource]) -> [CatalogSource] {
        sources.filter { $0.type == "rss" }
    }

    static func check(_ sources: [CatalogSource], session: URLSession = FeedDiscovery.session, width: Int = 8) async -> [CatalogCheck] {
        let todo = checkable(sources)
        return await withTaskGroup(of: (Int, CatalogCheck).self) { group in
            var results = [CatalogCheck?](repeating: nil, count: todo.count)
            var next = 0
            func add() {
                guard next < todo.count else { return }
                let i = next, source = todo[i]
                next += 1
                group.addTask { (i, await checkOne(source, session: session)) }
            }
            for _ in 0..<min(width, todo.count) { add() }
            for await (i, r) in group {
                results[i] = r
                add()
            }
            return results.compactMap { $0 }
        }
    }

    private static func checkOne(_ source: CatalogSource, session: URLSession) async -> CatalogCheck {
        guard let url = URL(string: source.url) else {
            return CatalogCheck(url: source.url, ok: false, itemCount: 0, error: "not a URL", transient: false)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(FeedDiscovery.userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                return CatalogCheck(url: source.url, ok: false, itemCount: 0, error: "HTTP \(status)", transient: false)
            }
            guard let feed = RSSFetcher.parseFeed(data) else {
                return CatalogCheck(url: source.url, ok: false, itemCount: 0, error: "did not parse", transient: false)
            }
            let (count, newest) = summary(feed)
            if count == 0 { return CatalogCheck(url: source.url, ok: false, itemCount: 0, error: "no items", transient: false) }
            if isStale(newest: newest, now: Date()) {
                let when = newest.map { "since \($0.sqliteString.prefix(10))" } ?? "no dated item"
                return CatalogCheck(url: source.url, ok: false, itemCount: count, error: "stale: \(when)", transient: false)
            }
            return CatalogCheck(url: source.url, ok: true, itemCount: count, error: nil, transient: false)
        } catch {
            return CatalogCheck(url: source.url, ok: false, itemCount: 0, error: error.localizedDescription,
                                transient: FetchErrorKind.classify(error) == .transient)
        }
    }

    static let staleAfterDays: Double = 60

    /// A feed whose newest dated story is older than 60 days (or that has no dated story) is not a working source.
    static func isStale(newest: Date?, now: Date) -> Bool {
        guard let newest else { return true }
        return now.timeIntervalSince(newest) > staleAfterDays * 86_400
    }

    private static func summary(_ feed: FeedKit.Feed) -> (count: Int, newest: Date?) {
        switch feed {
        case .rss(let rss):
            let items = rss.channel?.items ?? []
            return (items.count, items.compactMap(\.pubDate).max())
        case .atom(let atom):
            let entries = atom.entries ?? []
            return (entries.count, entries.compactMap { $0.published ?? $0.updated }.max())
        case .json(let json):
            let items = json.items ?? []
            return (items.count, items.compactMap(\.datePublished).max())
        }
    }

    /// Stamps `checkedAt` and `itemCount` on every passing source and clears the stamp of a source that
    /// failed for real, so a dead source stops counting toward its topic's three; lists real failures and
    /// offline ones apart. An offline source keeps its previous stamp.
    static func applying(_ checks: [CatalogCheck], to catalog: Catalog, now: Date) -> (catalog: Catalog, failed: [CatalogCheck], offline: [CatalogCheck]) {
        var c = catalog
        let byURL = Dictionary(checks.map { ($0.url, $0) }, uniquingKeysWith: { a, _ in a })
        for i in c.sources.indices {
            guard let check = byURL[c.sources[i].url] else { continue }
            if check.ok {
                c.sources[i].checkedAt = now.sqliteString
                c.sources[i].itemCount = check.itemCount
            } else if !check.transient {
                c.sources[i].checkedAt = nil
            }
        }
        return (c, checks.filter { !$0.ok && !$0.transient }, checks.filter { !$0.ok && $0.transient })
    }

    /// The one way the catalog file is written, so every rewrite produces the same layout.
    static func encode(_ catalog: Catalog) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try e.encode(catalog) + Data("\n".utf8)
    }
}
