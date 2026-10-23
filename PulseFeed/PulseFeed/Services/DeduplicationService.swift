import Foundation
import GRDB

/// Lightweight projection of a stored article, loaded once per tick for dedup.
/// Deliberately excludes contentHTML and the full contentText.
struct DedupCandidate: Codable, FetchableRecord, Sendable {
    var articleID: String
    var feedID: String
    var uniqueID: String = ""
    var url: String?
    var title: String?
    var contentPrefix: String?
    var clusterID: String?
    var dateArrived: String
}

enum DedupDecision: Equatable, Sendable {
    /// Genuinely new story.
    case insert
    /// Same URL, or a near-identical title/content from the SAME feed: a true duplicate.
    case drop
    /// The same story from ANOTHER feed: keep it, pointed at the primary article.
    case cluster(primaryID: String)
}

struct DedupApplyResult: Sendable {
    let toInsert: [Article]
    let dropped: Int
    let clustered: Int
}

/// Cluster-or-drop deduplication. Built once per tick from `DedupCandidate`s, shared by every
/// feed refresh in the tick. Immutable and Sendable; content tokens are memoised lazily behind a lock
/// so layer 3 only tokenises the few entries whose titles were near misses.
struct DedupIndex: Sendable {
    private struct Entry: Sendable {
        let articleID: String
        let feedID: String
        let primaryID: String
        let titleTokens: Set<String>
        let contentPrefix: String
    }

    private final class TokenCache: @unchecked Sendable {
        private let lock = NSLock()
        private var cache: [Int: Set<String>] = [:]
        func tokens(at index: Int, from text: String) -> Set<String> {
            lock.lock(); defer { lock.unlock() }
            if let hit = cache[index] { return hit }
            let tokens = DedupIndex.tokenize(text)
            cache[index] = tokens
            return tokens
        }
    }

    static let sameFeedTitleThreshold = 0.6
    /// 0.4 (was 0.5): measured 2026-09-06 on 4,388 stories, the 0.4–0.5 band was almost all real
    /// duplicates once stopwords were dropped from the tokens.
    static let crossFeedTitleThreshold = 0.4
    static let contentCheckTitleFloor = 0.35
    static let contentThreshold = 0.5

    private let urls: Set<String>
    private let entries: [Entry]
    private let contentTokens = TokenCache()

    init(candidates: [DedupCandidate]) {
        urls = Set(candidates.compactMap(\.url).filter { !$0.isEmpty }.map(Self.normalizeURL))
        entries = candidates.compactMap { c in
            guard let title = c.title else { return nil }
            let tokens = Self.tokenize(title)
            guard !tokens.isEmpty else { return nil }
            return Entry(
                articleID: c.articleID, feedID: c.feedID,
                primaryID: c.clusterID ?? c.articleID,
                titleTokens: tokens,
                contentPrefix: String((c.contentPrefix ?? "").prefix(500)))
        }
    }

    private init(urls: Set<String>, entries: [Entry]) {
        self.urls = urls
        self.entries = entries
    }

    var count: Int { entries.count }

    // MARK: - Decisions

    func decide(_ article: Article) -> DedupDecision {
        Self.decide(article, urls: urls, entries: entries, contentTokens: contentTokens)
    }

    /// Applies `decide` to a batch: drops true duplicates, stamps `clusterID` on cross-feed copies.
    func apply(_ articles: [Article]) -> DedupApplyResult {
        var toInsert: [Article] = []
        var dropped = 0
        var clustered = 0
        for var article in articles {
            switch decide(article) {
            case .drop:
                dropped += 1
            case .cluster(let primaryID):
                article.clusterID = primaryID
                clustered += 1
                toInsert.append(article)
            case .insert:
                toInsert.append(article)
            }
        }
        return DedupApplyResult(toInsert: toInsert, dropped: dropped, clustered: clustered)
    }

    /// Clusters cross-feed copies WITHIN one batch (stories that arrive from several outlets in the
    /// same tick, none of them in the DB yet). Earliest arrival becomes the primary. Nothing is dropped;
    /// same-feed near-duplicates inside a batch are left alone. Articles already pointed at a DB primary
    /// pass through untouched and never become batch primaries.
    static func clusterAmong(_ articles: [Article]) -> [Article] {
        let ordered = articles.sorted {
            ($0.dateArrived, $0.articleID) < ($1.dateArrived, $1.articleID)
        }
        var primaries: [Entry] = []
        var urls = Set<String>()
        let cache = TokenCache()
        var out: [Article] = []
        out.reserveCapacity(ordered.count)

        for var article in ordered {
            if article.clusterID != nil {
                out.append(article)
                continue
            }
            let decision = decide(article, urls: [], entries: primaries, contentTokens: cache)
            if case .cluster(let primaryID) = decision {
                article.clusterID = primaryID
            } else if let title = article.title {
                let tokens = tokenize(title)
                if !tokens.isEmpty {
                    primaries.append(Entry(
                        articleID: article.articleID, feedID: article.feedID,
                        primaryID: article.articleID, titleTokens: tokens,
                        contentPrefix: String((article.contentText ?? "").prefix(500))))
                }
                if let url = article.url, !url.isEmpty { urls.insert(normalizeURL(url)) }
            }
            out.append(article)
        }
        return out
    }

    // MARK: - Core

    private static func decide(
        _ article: Article, urls: Set<String>, entries: [Entry], contentTokens: TokenCache
    ) -> DedupDecision {
        // Layer 1: normalised URL match. Same page = same article, whichever feed carried it.
        if let url = article.url, !url.isEmpty, urls.contains(normalizeURL(url)) {
            return .drop
        }
        guard let title = article.title else { return .insert }
        let newTokens = tokenize(title)
        guard !newTokens.isEmpty else { return .insert }

        // Layer 2: title Jaccard against every entry. Same-feed duplicates take precedence over
        // cross-feed matches, so a story we already have from this feed is dropped, not clustered.
        var crossFeedMatch: Entry?
        var nearMisses: [(index: Int, entry: Entry)] = []
        for (i, entry) in entries.enumerated() {
            let j = jaccard(newTokens, entry.titleTokens)
            if entry.feedID == article.feedID {
                if j > sameFeedTitleThreshold { return .drop }
            } else if j > crossFeedTitleThreshold {
                if crossFeedMatch == nil { crossFeedMatch = entry }
            }
            if j >= contentCheckTitleFloor { nearMisses.append((i, entry)) }
        }
        if let match = crossFeedMatch { return .cluster(primaryID: match.primaryID) }

        // Layer 3: content overlap, only for the near misses (title similarity 0.35...0.5).
        if !nearMisses.isEmpty {
            let newContent = tokenize(String((article.contentText ?? "").prefix(500)))
            if !newContent.isEmpty {
                for (i, entry) in nearMisses {
                    let existing = contentTokens.tokens(at: i, from: entry.contentPrefix)
                    guard !existing.isEmpty else { continue }
                    if jaccard(newContent, existing) > contentThreshold {
                        return entry.feedID == article.feedID ? .drop : .cluster(primaryID: entry.primaryID)
                    }
                }
            }
        }
        return .insert
    }

    // MARK: - Helpers

    /// Strip query and fragment, lowercase.
    static func normalizeURL(_ url: String) -> String {
        guard let urlObj = URL(string: url),
              var components = URLComponents(url: urlObj, resolvingAgainstBaseURL: false)
        else { return url.lowercased() }
        components.query = nil
        components.fragment = nil
        return (components.url?.absoluteString ?? url).lowercased()
    }

    /// Words that carry no story identity; keeping them inflated the union and hid real matches.
    static let stopwords: Set<String> = [
        "the", "a", "an", "of", "to", "in", "on", "for", "and", "or", "with", "as", "at", "by", "from", "is",
        "are", "be", "its", "it", "this", "that", "after", "over", "vs", "amid", "says", "say", "said", "new",
        "how", "why", "what", "who", "us", "into", "out", "up", "his", "her", "their", "has", "have", "was",
        "were", "will", "than", "but", "not", "about", "before", "during", "while", "off", "just",
    ]

    static func tokenize(_ text: String) -> Set<String> {
        Set(
            text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 && !stopwords.contains($0) }
        )
    }

    static func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        let union = a.union(b).count
        guard union > 0 else { return 0 }
        return Double(a.intersection(b).count) / Double(union)
    }
}
