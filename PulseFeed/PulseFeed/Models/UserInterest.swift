import GRDB

struct UserInterest: Codable, FetchableRecord, PersistableRecord, Sendable, Identifiable {
    var id: String
    var keyword: String
    var weight: Double
    var category: String?
    var createdAt: String?

    static let databaseTableName = "userInterest"
}
