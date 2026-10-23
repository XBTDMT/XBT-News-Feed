import GRDB
import CryptoKit
import Foundation

struct Feed: Codable, FetchableRecord, PersistableRecord, Sendable, Identifiable {
    var id: String
    var title: String
    var url: String
    var homePageURL: String?
    var category: String
    /// The catalog topic under `category` (v10); nil for a source the catalog does not file.
    var topic: String?
    /// A catalog addition nobody has chosen yet (v11): a category tick leaves it off.
    var catalogAdded: Bool = false
    var type: String
    var pollInterval: Int
    var isEnabled: Bool

    // Conditional GET state
    var etag: String?
    var lastModified: String?
    var contentHash: String?

    // Favicon
    var faviconURL: String?
    var faviconData: Data?

    // Fetch state
    var lastFetchedAt: String?
    var lastFetchError: String?
    var consecutiveErrors: Int
    var conditionalGetResetAt: String?
    /// When this feed last produced a newly inserted article (SQLite datetime, UTC).
    var lastArticleAt: String?

    var createdAt: String?
    var updatedAt: String?

    static let databaseTableName = "feed"

    /// "feed-" + the first 16 hex digits of SHA-256(url): stable across launches, unlike
    /// `String.hashValue`, which is seeded per process.
    static func makeID(url: String) -> String {
        let digest = SHA256.hash(data: Data(url.utf8))
        return "feed-" + digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}

/// "Cannot look" (fetch errors) vs "nothing there" (fetching fine, no article for weeks) vs fine.
enum FeedHealth: Equatable, Sendable {
    case ok
    case stale(daysSinceArticle: Int)
    case failing(errors: Int)
}

extension Feed {
    func health(now: Date = Date(), staleAfterDays: Int = PulseFeedConstants.staleFeedDays) -> FeedHealth {
        if consecutiveErrors > 0 { return .failing(errors: consecutiveErrors) }
        guard let reference = lastArticleAt ?? createdAt, let date = reference.sqliteDate else {
            return .ok
        }
        let days = Int(now.timeIntervalSince(date) / 86400)
        return days >= staleAfterDays ? .stale(daysSinceArticle: days) : .ok
    }
}
