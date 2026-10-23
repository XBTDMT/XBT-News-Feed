import GRDB
import Foundation

/// Denormalized view model for UI: article + status + feed info + cluster sources.
/// `contentText` is a 400-character preview; fetch the full `Article` when the body is needed.
struct ArticleInfo: Codable, FetchableRecord, Hashable, Identifiable, Sendable {
    var articleID: String
    var feedID: String
    var title: String?
    var url: String?
    var contentText: String?
    var summary: String?
    var imageURL: String?
    var datePublished: String?
    var dateArrived: String
    var relevanceScore: Double?
    var priority: String?
    var isRead: Bool?
    var isStarred: Bool?
    var isSaved: Bool?
    var isNotified: Bool?
    var feedTitle: String
    var feedCategory: String
    /// The feed's catalog topic (v10), for topic-scoped alert patterns.
    var feedTopic: String?
    /// Titles of the other feeds carrying this same story, comma separated. nil when none.
    var otherSources: String?
    /// 1 + number of other sources.
    var sourceCount: Int

    var id: String { articleID }

    func hash(into hasher: inout Hasher) { hasher.combine(articleID) }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.articleID == rhs.articleID }
}

// MARK: - Shared SELECT + ValueObservation factory

extension ArticleInfo {
    /// The one projection every ArticleInfo query uses. Only list-sized columns: the body is cut
    /// to 400 characters so the list observation stops re-reading full articles on every write.
    static let selectSQL = """
        SELECT article.articleID, article.feedID, article.title, article.url,
               substr(article.contentText, 1, 400) AS contentText, article.summary, article.imageURL,
               article.datePublished, article.dateArrived,
               article.relevanceScore, article.priority,
               articleStatus.isRead, articleStatus.isStarred,
               articleStatus.isSaved, articleStatus.isNotified,
               feed.title AS feedTitle, feed.category AS feedCategory, feed.topic AS feedTopic,
               (SELECT group_concat(f2.title, ', ') FROM article a2
                  JOIN feed f2 ON f2.id = a2.feedID
                 WHERE a2.clusterID = article.articleID) AS otherSources,
               1 + (SELECT COUNT(*) FROM article a3 WHERE a3.clusterID = article.articleID) AS sourceCount
        FROM article
        JOIN feed ON feed.id = article.feedID
        LEFT JOIN articleStatus ON articleStatus.articleID = article.articleID
        """

    /// Creates a ValueObservation that tracks articles with optional category filter.
    /// Use `"starred"` as category to show only starred articles (includes read).
    /// All other views default to unread-only, with fallback to recent 10 if none unread.
    /// Cluster secondaries are never listed; they surface as "Also in ..." on their primary.
    static func observation(
        category: String? = nil
    ) -> ValueObservation<ValueReducers.Fetch<[ArticleInfo]>> {
        ValueObservation.tracking { db -> [ArticleInfo] in
            var sql = selectSQL + " WHERE feed.isEnabled = 1 AND article.clusterID IS NULL"
            var arguments = StatementArguments()

            if category == "starred" {
                sql += " AND articleStatus.isStarred = 1"
            } else if category == "saved" {
                sql += " AND articleStatus.isSaved = 1"
            } else if let category {
                sql += " AND feed.category = ? AND (articleStatus.isRead = 0 OR articleStatus.isRead IS NULL)"
                arguments += [category]
            } else {
                sql += " AND (articleStatus.isRead = 0 OR articleStatus.isRead IS NULL)"
            }

            sql += " ORDER BY article.dateArrived DESC LIMIT \(PulseFeedConstants.maxArticlesPerQuery)"

            let results = try ArticleInfo.fetchAll(db, sql: sql, arguments: arguments)

            // Fallback: if a category filter returns empty, show most recent 10 (any read state)
            if results.isEmpty, let category, category != "starred", category != "saved" {
                let fallbackSQL = selectSQL + """
                     WHERE feed.isEnabled = 1 AND article.clusterID IS NULL AND feed.category = ?
                    ORDER BY article.dateArrived DESC LIMIT 10
                    """
                return try ArticleInfo.fetchAll(db, sql: fallbackSQL, arguments: [category])
            }

            return results
        }
    }
}
