import Foundation
import GRDB

/// The small tiles' numbers, live: Starred N · Saved N · Search 16,680, plus the enabled source
/// count and its health split for the footers ("44 sources · 41 ok · 2 stale · 1 failing").
/// One observation so a star toggled inside a tile updates the tile row.
struct DeckStats: Sendable, Equatable {
    var total = 0
    var starred = 0
    var saved = 0
    var feeds = 0
    var feedsOK = 0
    var feedsStale = 0
    var feedsFailing = 0

    static func observation() -> ValueObservation<ValueReducers.Fetch<DeckStats>> {
        ValueObservation.tracking { db -> DeckStats in
            let enabled = try Feed.fetchAll(db, sql: "SELECT * FROM feed WHERE isEnabled = 1")
            var stats = DeckStats(
                total: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM article") ?? 0,
                starred: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM articleStatus WHERE isStarred = 1") ?? 0,
                saved: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM articleStatus WHERE isSaved = 1") ?? 0,
                feeds: enabled.count)
            for feed in enabled {
                switch feed.health() {
                case .ok: stats.feedsOK += 1
                case .stale: stats.feedsStale += 1
                case .failing: stats.feedsFailing += 1
                }
            }
            return stats
        }
    }
}
