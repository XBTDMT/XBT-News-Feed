import Foundation
import GRDB

/// A typed interest the catalog has no topic for becomes a news search: a Google News RSS search
/// (personal feed-reader use, per the terms check summarised in THIRD_PARTY_NOTICES.md) stored as an ordinary feed whose
/// topic is "search:<slug>", so polling, lists and counts need nothing new.
enum NewsSearch {
    private static let editions: [String: (hl: String, gl: String)] = [
        "uk": ("en-GB", "GB"), "eu": ("en-GB", "GB"), "asia": ("en-SG", "SG"), "us": ("en-US", "US"),
    ]

    static func url(query: String, region: String) -> URL? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#")
        guard let q = query.trimmingCharacters(in: .whitespaces).addingPercentEncoding(withAllowedCharacters: allowed),
              !q.isEmpty else { return nil }
        let e = editions[region] ?? ("en-US", "US")
        return URL(string: "https://news.google.com/rss/search?q=\(q)&hl=\(e.hl)&gl=\(e.gl)&ceid=\(e.gl):en")
    }

    /// "search:" + the phrase's letters and digits, lowercased, joined by single dashes. A phrase with
    /// characters the slug drops ("c++", "c#", an emoji) also gets a stable hash, so two such phrases
    /// never share a search.
    static func topicID(for phrase: String) -> String {
        let normalized = phrase.lowercased().trimmingCharacters(in: .whitespaces)
        let words = normalized.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let plain = CharacterSet.alphanumerics.union(.whitespaces).union(CharacterSet(charactersIn: ".,!?'-"))
        let lossy = words.isEmpty || normalized.unicodeScalars.contains { !plain.contains($0) }
        let slug = words.joined(separator: "-")
        guard lossy else { return "search:" + slug }
        return "search:" + (slug.isEmpty ? "" : slug + "-") + fnv1a(normalized)
    }

    /// 32-bit FNV-1a as 8 hex digits: stable across launches, unlike `hashValue`.
    private static func fnv1a(_ s: String) -> String {
        var h: UInt32 = 0x811c9dc5
        for b in s.utf8 { h = (h ^ UInt32(b)) &* 0x0100_0193 }
        return String(format: "%08x", h)
    }
}

extension AppDatabase {
    /// Adds (or returns the existing) news-search feed for the phrase, switched on. A category that is
    /// not a `NewsCategory` id becomes "general".
    func addNewsSearch(phrase: String, category: String, region: String) async throws -> Feed {
        let topic = NewsSearch.topicID(for: phrase)
        if var existing = try await dbPool.read({ db in
            try Feed.fetchOne(db, sql: "SELECT * FROM feed WHERE topic = ?", arguments: [topic])
        }) {
            if !existing.isEnabled {
                let id = existing.id
                try await dbPool.write { db in
                    try db.execute(sql: "UPDATE feed SET isEnabled = 1, updatedAt = datetime('now') WHERE id = ?", arguments: [id])
                }
                existing.isEnabled = true
            }
            return existing
        }
        guard let url = NewsSearch.url(query: phrase, region: region) else {
            throw DatabaseError(message: "no search URL for \(phrase)")
        }
        let chip = NewsCategory.pickerIDs.contains(category) ? category : NewsCategory.general.id
        let title = phrase.trimmingCharacters(in: .whitespaces)
        try await dbPool.write { db in
            try db.execute(
                sql: """
                    INSERT OR IGNORE INTO feed (id, title, url, category, topic, type, pollInterval, isEnabled)
                    VALUES (?, ?, ?, ?, ?, 'rss', 900, 1)
                    """,
                arguments: [Feed.makeID(url: url.absoluteString), title, url.absoluteString, chip, topic])
        }
        guard let row = try await feed(withURL: url.absoluteString) else {
            throw DatabaseError(message: "addNewsSearch did not insert \(phrase)")
        }
        return row
    }
}
