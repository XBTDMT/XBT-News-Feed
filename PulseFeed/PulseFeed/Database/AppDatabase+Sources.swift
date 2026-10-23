import Foundation
import GRDB

/// What Settings › Sources › Add source did.
enum AddSourceOutcome: Sendable {
    /// A new row, enabled.
    case added(Feed)
    /// The URL was already a source (feed.url is UNIQUE); it has been switched on and is returned as it is.
    case alreadyPresent(Feed)
}

/// Settings › Sources: adding and removing a source. Reads and writes only; no schema change.
extension AppDatabase {
    /// The source with exactly this URL, if any.
    func feed(withURL url: String) async throws -> Feed? {
        try await dbPool.read { db in
            try Feed.fetchOne(db, sql: "SELECT * FROM feed WHERE url = ?", arguments: [url])
        }
    }

    /// Inserts through `addFeed` (type "rss" covers RSS, Atom and JSON Feed — RSSFetcher parses all
    /// three) and makes sure the row is enabled, so its category counts as on at once. An existing
    /// URL is not duplicated: it is switched back on and reported.
    func addSource(title: String, url: String, category: String) async throws -> AddSourceOutcome {
        let existing = try await feed(withURL: url)
        try await addFeed(title: title, url: url, category: category)
        try await dbPool.write { db in
            try db.execute(
                sql: "UPDATE feed SET isEnabled = 1, catalogAdded = 0, updatedAt = datetime('now') WHERE url = ?",
                arguments: [url])
        }
        guard let row = try await feed(withURL: url) else {
            throw DatabaseError(message: "addFeed did not insert \(url)")
        }
        return existing == nil ? .added(row) : .alreadyPresent(row)
    }

    /// How many stories a source holds — the inline Remove confirmation says what goes with it.
    func articleCount(feedID: String) async throws -> Int {
        try await dbPool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM article WHERE feedID = ?", arguments: [feedID]) ?? 0
        }
    }
}

extension AppDatabase {
    /// Settings › Sources › Import OPML. A file from this app's own export carries each source's on/off
    /// state and is restored as written. From another reader's file: a new URL is added and switched on,
    /// a catalog source that is off and unchosen is switched on (importing it is choosing it), and a source
    /// the person switched off themselves stays off. Returns how many were added or switched on; a
    /// failure is logged and not counted. An own export from before the attribute (`ownExport`, by its
    /// title) leaves every existing source as it is.
    func importFeeds(_ feeds: [OPMLService.OPMLFeed], ownExport: Bool = false) async throws -> Int {
        var changed = 0
        for f in feeds {
            do {
                if let row = try await feed(withURL: f.url) {
                    let on: Bool
                    if let enabled = f.enabled { on = enabled } else if ownExport { continue } else { on = row.isEnabled || row.catalogAdded }
                    guard on != row.isEnabled else { continue }
                    try await updateFeedEnabled(feedID: row.id, isEnabled: on)
                    if on { changed += 1 }
                } else {
                    try await addFeed(title: f.title, url: f.url, category: f.category)
                    if f.enabled == false, let row = try await feed(withURL: f.url) {
                        try await updateFeedEnabled(feedID: row.id, isEnabled: false)
                    } else {
                        changed += 1
                    }
                }
            } catch {
                print("PulseFeed: [OPML] could not import \(f.url): \(error)")
            }
        }
        return changed
    }
}
