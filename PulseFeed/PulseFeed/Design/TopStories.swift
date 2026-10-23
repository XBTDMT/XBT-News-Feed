import Foundation

/// The Deck board's "Top stories · by coverage · 24h". Pure: the caller hands in the stories the
/// window already observes and the clock; nothing here touches the database.
///
/// Score = outlets carrying the story × a recency half-life. Coverage (`sourceCount`, the primary
/// plus its clustered copies) is what makes a story "top"; the decay stops a morning cluster from
/// sitting at #1 all day. Ties go to the newer story, then to input order (newest-first already).
enum TopStories {
    /// Stories older than this are not "top" whatever their coverage.
    static let window: TimeInterval = 24 * 3600
    /// Coverage halves every 12 hours, so a two-outlet story from this morning still leads a fresh
    /// single-outlet one, and a three-outlet story from yesterday evening does not.
    static let halfLife: TimeInterval = 12 * 3600

    /// `sourceCount` below one counts as one (a primary always carries itself); a negative age
    /// (clock skew) counts as zero so the future never earns a boost.
    static func score(sourceCount: Int, age: TimeInterval, halfLife: TimeInterval = halfLife) -> Double {
        let sources = Double(max(1, sourceCount))
        let lives = max(0, age) / halfLife
        return sources * pow(0.5, lives)
    }

    /// The top `limit` stories inside `window`, best first. A story whose `dateArrived` does not
    /// parse cannot be placed in the window and is left out.
    static func rank(
        _ articles: [ArticleInfo], now: Date, limit: Int,
        window: TimeInterval = window, halfLife: TimeInterval = halfLife
    ) -> [ArticleInfo] {
        guard limit > 0 else { return [] }
        let scored = articles.enumerated().compactMap { index, article -> (index: Int, article: ArticleInfo, score: Double, arrived: Date)? in
            guard let arrived = article.arrivalDate else { return nil }
            let age = now.timeIntervalSince(arrived)
            guard age <= window else { return nil }
            return (index, article, score(sourceCount: article.sourceCount, age: age, halfLife: halfLife), arrived)
        }
        let ordered = scored.sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            if a.arrived != b.arrived { return a.arrived > b.arrived }
            return a.index < b.index
        }
        return ordered.prefix(limit).map(\.article)
    }
}
