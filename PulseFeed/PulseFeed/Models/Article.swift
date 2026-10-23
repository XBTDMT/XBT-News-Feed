import GRDB
import Foundation
import CryptoKit

struct Article: Codable, FetchableRecord, PersistableRecord, Sendable {
    var articleID: String
    var feedID: String
    var uniqueID: String

    var title: String?
    var url: String?
    var externalURL: String?
    var contentHTML: String?
    var contentText: String?
    var summary: String?
    var imageURL: String?
    var thumbnailPath: String?

    var author: String?
    var datePublished: String?
    var dateArrived: String

    // AI enrichment
    var relevanceScore: Double?
    var priority: String?
    var topics: String?

    var searchRowID: Int64?

    /// nil = primary (or standalone) article. Otherwise the articleID of the primary article
    /// this one duplicates from another feed. Secondaries are hidden from lists and counted
    /// as extra sources on the primary.
    var clusterID: String?

    static let databaseTableName = "article"

    /// Published before `cutoff` (a feed's back catalogue). Undated stories are never old news.
    func isOldNews(before cutoff: Date) -> Bool {
        guard let published = datePublished?.sqliteDate else { return false }
        return published < cutoff
    }

    /// Generate deterministic article ID: SHA256(feedID + ":" + uniqueID)
    static func makeID(feedID: String, uniqueID: String) -> String {
        let input = "\(feedID):\(uniqueID)"
        let hash = SHA256.hash(data: Data(input.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

// NNW pattern: hash only articleID for Set performance
extension Article: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(articleID) }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.articleID == rhs.articleID }
}
