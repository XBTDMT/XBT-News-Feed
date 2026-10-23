import GRDB

struct ArticleStatus: Codable, FetchableRecord, PersistableRecord, Sendable {
    var articleID: String
    var isRead: Bool
    var isStarred: Bool
    var isSaved: Bool
    var isNotified: Bool
    var dateRead: String?
    var dateStarred: String?

    static let databaseTableName = "articleStatus"
}
