import Foundation
import GRDB

struct CatalogSyncResult: Equatable, Sendable {
    var inserted: Int
    var topicsAssigned: Int
}

/// The catalog reaching the database (G-1): run at launch when `catalog_version` is behind the file.
extension AppDatabase {
    static let catalogVersionKey = "catalog_version"

    /// Inserts catalog sources the database does not have (switched off unless `enableNew`), and gives
    /// an existing row its topic when the row has none and sits in that topic's category. Never changes
    /// an existing row's category or enabled state.
    /// `previousVersion` is the catalog version this database last synced (`catalog_version`). The first
    /// sync after version 2 also marks the rows that version's sync inserted before `catalogAdded`
    /// existed: filed under a topic, off, never read, and not a seed. It runs once.
    @discardableResult
    func syncCatalog(_ catalog: Catalog, enableNew: Bool, previousVersion: Int = 0) async throws -> CatalogSyncResult {
        let seeds = catalog.sources.filter { ($0.since ?? 1) == 1 }.map(\.url)
        return try await dbPool.write { db in
            var result = CatalogSyncResult(inserted: 0, topicsAssigned: 0)
            if previousVersion == 2 {
                let placeholders = seeds.map { _ in "?" }.joined(separator: ",")
                try db.execute(
                    sql: """
                        UPDATE feed SET catalogAdded = 1
                         WHERE topic IS NOT NULL AND isEnabled = 0 AND catalogAdded = 0
                           AND url NOT IN (\(placeholders))
                           AND NOT EXISTS (SELECT 1 FROM article WHERE article.feedID = feed.id)
                        """,
                    arguments: StatementArguments(seeds))
            }
            for source in catalog.sources {
                guard let topic = catalog.topic(source.topic) else { continue }
                if let row = try Feed.fetchOne(db, sql: "SELECT * FROM feed WHERE url = ?", arguments: [source.url]) {
                    guard row.topic == nil, row.category == topic.category else { continue }
                    try db.execute(sql: "UPDATE feed SET topic = ?, updatedAt = datetime('now') WHERE id = ?",
                                   arguments: [topic.id, row.id])
                    result.topicsAssigned += 1
                } else {
                    try db.execute(
                        sql: """
                            INSERT INTO feed (id, title, url, category, topic, type, pollInterval, isEnabled, catalogAdded)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                            """,
                        arguments: [Feed.makeID(url: source.url), source.title, source.url, topic.category,
                                    topic.id, source.type, source.pollInterval, enableNew, !enableNew])
                    result.inserted += 1
                }
            }
            return result
        }
    }

    /// Enables or disables every feed filed under the topic (the topic-level twin of `setCategoryEnabled`).
    /// Turning a topic on is choosing it: its catalog additions then come and go with their category.
    /// `holdBack`: catalog URLs left off while unchosen (`Catalog.heldBack`): arXiv, never-offered feeds.
    func setTopicEnabled(_ topic: String, _ enabled: Bool, holdBack: Set<String> = Catalog.heldBackURLs) async throws {
        try await dbPool.write { db in
            guard enabled else {
                try db.execute(sql: "UPDATE feed SET isEnabled = 0, updatedAt = datetime('now') WHERE topic = ?", arguments: [topic])
                return
            }
            let held = Array(holdBack)
            let placeholders = held.isEmpty ? "''" : held.map { _ in "?" }.joined(separator: ",")
            try db.execute(
                sql: """
                    UPDATE feed SET isEnabled = 1, catalogAdded = 0, updatedAt = datetime('now')
                     WHERE topic = ? AND NOT (catalogAdded = 1 AND url IN (\(placeholders)))
                    """,
                arguments: StatementArguments([topic] + held))
        }
    }
}

extension AppDatabase {
    /// Applies what typed interests turned into: topics switch on their feeds, names join the stored
    /// follow list (`urgency_rules`), searches become feeds. Settings › Sources and the welcome flow both
    /// come through here.
    func applyInterests(_ matches: [InterestMatch], catalog: Catalog, region: String, defaults: UserDefaults = .standard) async throws {
        var follows: [String] = []
        for m in matches {
            switch m {
            case .topic(let id):
                if catalog.topic(id) != nil { try await setTopicEnabled(id, true) }
            case .follow(let name, let topicID):
                // A catalog follow alerts only under its own chip ("sports: heat" never fires on "extreme
                // heat" in World); a name the catalog does not know applies everywhere.
                // Every chip whose topics list the name ("apple" is Tech and Finance), not only the first.
                if let topicID, let topic = catalog.topic(topicID) {
                    var chips = [topic.category]
                    for t in catalog.topics where t.follows.contains(name) && !chips.contains(t.category) { chips.append(t.category) }
                    follows += chips.map { "\($0): \(name)" }
                } else {
                    follows.append(name)
                }
            case .newSearch(let phrase, let category):
                _ = try await addNewsSearch(phrase: phrase, category: category, region: region)
            }
        }
        if !follows.isEmpty {
            let rules = UrgencyRules.stored(defaults).addingFollows(follows)
            defaults.set(rules.asText, forKey: UrgencyRules.defaultsKey)
        }
    }
}
