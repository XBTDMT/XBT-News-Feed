import Foundation
import GRDB

/// The learning week's table (migration v9): one row per event, joined to feed and category on read.
extension AppDatabase {
    func logEngagement(_ rows: [(event: EngagementEvent, articleID: String, value: Double?)]) async throws {
        guard !rows.isEmpty else { return }
        try await dbPool.write { db in
            for r in rows {
                try db.execute(sql: "INSERT INTO engagement (event, articleID, value) VALUES (?, ?, ?)",
                               arguments: [r.event.rawValue, r.articleID, r.value])
            }
        }
    }

    func fetchEngagement(since: Date) async throws -> [EngagementRow] {
        try await dbPool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT e.at, e.event, e.articleID, a.feedID, f.title AS feedTitle, f.category, a.topics, e.value
                FROM engagement e
                JOIN article a ON a.articleID = e.articleID
                JOIN feed f ON f.id = a.feedID
                WHERE e.at > ?
                ORDER BY e.id
                """, arguments: [since.sqliteString])
            return rows.map {
                EngagementRow(at: $0["at"], event: $0["event"], articleID: $0["articleID"], feedID: $0["feedID"],
                              feedTitle: $0["feedTitle"], category: $0["category"], topics: $0["topics"], value: $0["value"])
            }
        }
    }

    /// "Not interested": the story is read (it leaves the unread lists) and the week remembers why.
    /// "Not interested": read now; recorded for the learning week only while it runs (`log`).
    func dismiss(articleID: String, log: Bool) async throws {
        try await dbPool.write { db in
            try db.execute(sql: "UPDATE articleStatus SET isRead = 1, dateRead = datetime('now') WHERE articleID = ?", arguments: [articleID])
            if log {
                try db.execute(sql: "INSERT INTO engagement (event, articleID) VALUES ('dismissed', ?)", arguments: [articleID])
            }
        }
    }

    func engagementCount() async throws -> Int {
        try await dbPool.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM engagement") ?? 0 }
    }
}
