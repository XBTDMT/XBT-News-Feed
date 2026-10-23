import Foundation
import GRDB

/// Read-only queries the three designs and the three ideas need. No schema change.
extension AppDatabase {
    private static let unreadPrimaryWhere = """
        FROM article
        JOIN feed ON feed.id = article.feedID
        LEFT JOIN articleStatus ON articleStatus.articleID = article.articleID
        WHERE feed.isEnabled = 1 AND article.clusterID IS NULL
          AND (articleStatus.isRead = 0 OR articleStatus.isRead IS NULL)
        """

    /// Idea ①: unread primaries that arrived after `since` (nil = all unread primaries) and that no
    /// recap has covered yet — the menu bar count is "what nobody has told you about", so a
    /// delivered recap resets it instead of letting it sit at 99+ all day.
    static func newSinceObservation(since: Date?) -> ValueObservation<ValueReducers.Fetch<Int>> {
        ValueObservation.tracking { db -> Int in try newSinceCount(db, since: since) }
    }

    static func newSinceCount(_ db: Database, since: Date?) throws -> Int {
        let untold = " AND (articleStatus.isNotified = 0 OR articleStatus.isNotified IS NULL)"
        if let since {
            return try Int.fetchOne(
                db, sql: "SELECT COUNT(*) " + unreadPrimaryWhere + untold + " AND article.dateArrived > ?",
                arguments: [since.sqliteString]) ?? 0
        }
        return try Int.fetchOne(db, sql: "SELECT COUNT(*) " + unreadPrimaryWhere + untold) ?? 0
    }

    /// Unread primaries per feed category (chips, Deck's Unread tile, sidebar counts).
    static func unreadCountsByCategoryObservation() -> ValueObservation<ValueReducers.Fetch<[String: Int]>> {
        ValueObservation.tracking { db -> [String: Int] in
            let rows = try Row.fetchAll(
                db, sql: "SELECT feed.category AS category, COUNT(*) AS n " + unreadPrimaryWhere + " GROUP BY feed.category")
            var out: [String: Int] = [:]
            for row in rows { out[row["category"]] = row["n"] }
            return out
        }
    }

    /// Idea ③: the menu bar shows a red dot while any unread primary is BREAKING.
    static func breakingUnreadCountObservation() -> ValueObservation<ValueReducers.Fetch<Int>> {
        ValueObservation.tracking { db -> Int in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) " + unreadPrimaryWhere + " AND article.priority = 'breaking'") ?? 0
        }
    }

    /// Categories that have at least one enabled feed. A category is switched off by disabling its
    /// feeds (`setCategoryEnabled`), so polling, lists and counts all follow `feed.isEnabled`.
    static func enabledCategoriesObservation() -> ValueObservation<ValueReducers.Fetch<Set<String>>> {
        ValueObservation.tracking { db -> Set<String> in
            Set(try String.fetchAll(db, sql: "SELECT DISTINCT category FROM feed WHERE isEnabled = 1"))
        }
    }

    /// Settings › Sources › Categories: off disables every feed in the category; on enables the ones the
    /// install had or chose, never a catalog addition nobody chose (`catalogAdded`, v11). A category made
    /// only of unchosen catalog additions (Food, Life) is chosen whole by ticking it.
    /// `holdBack`: catalog URLs left off while unchosen (`Catalog.heldBack`): arXiv, never-offered feeds.
    func setCategoryEnabled(_ category: String, _ enabled: Bool, holdBack: Set<String> = Catalog.heldBackURLs) async throws {
        try await dbPool.write { db in
            guard enabled else {
                try db.execute(sql: "UPDATE feed SET isEnabled = 0, updatedAt = datetime('now') WHERE category = ?", arguments: [category])
                return
            }
            // Chosen catalog sources only: one hand-added source or typed search must not stop a tick from
            // choosing the category's catalog sources.
            let chosen = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM feed WHERE category = ? AND catalogAdded = 0
                   AND topic IS NOT NULL AND topic NOT LIKE 'search:%'
                """, arguments: [category]) ?? 0
            if chosen == 0 {
                // Chosen whole, except what is held back while unchosen.
                let held = Array(holdBack)
                let placeholders = held.isEmpty ? "''" : held.map { _ in "?" }.joined(separator: ",")
                try db.execute(
                    sql: """
                        UPDATE feed SET isEnabled = 1, catalogAdded = 0, updatedAt = datetime('now')
                         WHERE category = ? AND NOT (catalogAdded = 1 AND url IN (\(placeholders)))
                        """,
                    arguments: StatementArguments([category] + held))
            } else {
                try db.execute(sql: "UPDATE feed SET isEnabled = 1, updatedAt = datetime('now') WHERE category = ? AND catalogAdded = 0", arguments: [category])
            }
        }
    }

    /// Unread, un-notified primaries from enabled feeds that arrived after `since`, newest first.
    func fetchUnnotifiedSince(_ since: Date, limit: Int) async throws -> [ArticleInfo] {
        try await dbPool.read { db in
            let sql = ArticleInfo.selectSQL + """
                 WHERE feed.isEnabled = 1 AND article.clusterID IS NULL
                   AND article.dateArrived > ?
                   AND (articleStatus.isRead = 0 OR articleStatus.isRead IS NULL)
                   AND (articleStatus.isNotified = 0 OR articleStatus.isNotified IS NULL)
                ORDER BY article.dateArrived DESC
                LIMIT ?
                """
            return try ArticleInfo.fetchAll(db, sql: sql, arguments: [since.sqliteString, limit])
        }
    }

    /// Recent primaries with a link but no picture — the social-image backfill's work list.
    func fetchImageless(since: Date, excluding tried: Set<String>, limit: Int) async throws -> [ArticleInfo] {
        try await dbPool.read { db in
            let sql = ArticleInfo.selectSQL + """
                 WHERE feed.isEnabled = 1 AND article.clusterID IS NULL
                   AND article.url IS NOT NULL AND article.url != ''
                   AND (article.imageURL IS NULL OR article.imageURL = '')
                   AND article.dateArrived > ?
                ORDER BY article.dateArrived DESC
                LIMIT ?
                """
            let rows = try ArticleInfo.fetchAll(db, sql: sql, arguments: [since.sqliteString, limit + tried.count])
            return Array(rows.filter { !tried.contains($0.articleID) }.prefix(limit))
        }
    }

    /// Marks the given primaries read together with every story clustered under them (the same
    /// story from other outlets), so a recap that covered them clears the whole count.
    func markReadIncludingCluster(ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        try await dbPool.write { db in
            let marks = databaseQuestionMarks(count: ids.count)
            try db.execute(
                sql: """
                    UPDATE articleStatus SET isRead = 1, dateRead = datetime('now')
                    WHERE (isRead = 0 OR isRead IS NULL) AND articleID IN (
                        SELECT articleID FROM article WHERE articleID IN (\(marks)) OR clusterID IN (\(marks))
                    )
                    """, arguments: StatementArguments(ids + ids))
        }
    }

    func updateImageURL(articleID: String, url: String) async throws {
        try await dbPool.write { db in
            try db.execute(sql: "UPDATE article SET imageURL = ? WHERE articleID = ?", arguments: [url, articleID])
        }
    }

    /// Settings › General › Unread window: unread stories older than `days` become read, so the
    /// counts mean "recent" and the badge never says 99+ forever. Starred and saved are left alone.
    func markReadOlderThan(days: Int) async throws -> Int {
        try await dbPool.write { db in
            try db.execute(
                sql: """
                    UPDATE articleStatus SET isRead = 1, dateRead = datetime('now')
                    WHERE isRead = 0 AND (isStarred = 0 OR isStarred IS NULL) AND (isSaved = 0 OR isSaved IS NULL)
                      AND articleID IN (SELECT articleID FROM article WHERE dateArrived < datetime('now', ?))
                    """,
                arguments: ["-\(days) days"])
            return db.changesCount
        }
    }

    /// Idea ②: the primary plus every secondary clustered under it, oldest first after the primary.
    func fetchClusterMembers(primaryID: String) async throws -> [ClusterMember] {
        try await dbPool.read { db in
            try ClusterMember.fetchAll(
                db,
                sql: """
                    SELECT article.articleID, feed.title AS feedTitle, article.title, article.url, article.dateArrived
                    FROM article
                    JOIN feed ON feed.id = article.feedID
                    WHERE article.articleID = ? OR article.clusterID = ?
                    ORDER BY CASE WHEN article.articleID = ? THEN 0 ELSE 1 END, article.dateArrived ASC
                    """,
                arguments: [primaryID, primaryID, primaryID])
        }
    }

    /// Clearing the brief is a "caught up" gesture, so it reaches every unread story from an
    /// enabled feed however it stands relative to the brief: stories older than the brief's own
    /// 24-hour window, the ones it wrote about, and the ones that landed behind it (the brief is
    /// cached for up to six hours, so there is always a tail of arrivals it never saw). Feeds that
    /// are switched off are left alone — their stories were never shown, so turning that category
    /// on later should still surface them. Starred and saved keep their flags; read is not unsave.
    /// ⚠ The count queries `LEFT JOIN articleStatus` and treat a **missing** row as unread, so an
    /// UPDATE alone would leave such a story counted and the badge would not reach zero. The
    /// missing rows are written first, already read, for exactly that reason.
    @discardableResult
    func markAllUnreadReadInEnabledFeeds() async throws -> Int {
        try await dbPool.write { db in
            let enabled = """
                SELECT article.articleID FROM article
                JOIN feed ON feed.id = article.feedID
                WHERE feed.isEnabled = 1
                """
            try db.execute(
                sql: """
                    INSERT OR IGNORE INTO articleStatus
                        (articleID, isRead, isStarred, isSaved, isNotified, dateRead)
                    SELECT articleID, 1, 0, 0, 0, datetime('now') FROM (\(enabled))
                    WHERE articleID NOT IN (SELECT articleID FROM articleStatus)
                    """)
            let created = db.changesCount
            try db.execute(
                sql: """
                    UPDATE articleStatus SET isRead = 1, dateRead = datetime('now')
                    WHERE isRead = 0 AND articleID IN (\(enabled))
                    """)
            return created + db.changesCount
        }
    }

    /// "Mark these read" on the since-you-last-looked divider: one write for the whole batch.
    func markRead(ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        try await dbPool.write { db in
            for id in ids {
                try db.execute(
                    sql: "UPDATE articleStatus SET isRead = 1, dateRead = datetime('now') WHERE articleID = ?",
                    arguments: [id])
            }
        }
    }
}

// MARK: - Repairs

extension AppDatabase {
    /// Decodes HTML entities left in stored titles by double-encoding feeds (80 rows on 2026-09-06).
    /// The `article_search_au` trigger keeps the FTS index in step. Returns the count.
    func repairHTMLEntityTitles() async throws -> Int {
        let rows: [(id: String, title: String)] = try await dbPool.read { db in
            try Row.fetchAll(db, sql: "SELECT articleID, title FROM article WHERE title LIKE '%&%;%'")
                .compactMap { row in
                    guard let title: String = row["title"] else { return nil }
                    return (row["articleID"], title)
                }
        }
        let fixes = rows.compactMap { row -> (String, String)? in
            let decoded = row.title.htmlEntitiesDecoded
            return decoded != row.title ? (row.id, decoded) : nil
        }
        guard !fixes.isEmpty else { return 0 }
        try await dbPool.write { db in
            for (id, title) in fixes {
                try db.execute(sql: "UPDATE article SET title = ? WHERE articleID = ?", arguments: [title, id])
            }
        }
        return fixes.count
    }
}


extension AppDatabase {
    /// True once any story has ever been stored: an install in use, as opposed to a fresh one.
    /// Synchronous so the launch sequence can decide before the engine starts.
    func hasHistory() throws -> Bool {
        try dbPool.read { db in
            try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM article)") ?? false
        }
    }
}
