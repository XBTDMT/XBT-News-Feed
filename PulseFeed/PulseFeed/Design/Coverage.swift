import Foundation
import GRDB

/// One outlet inside a story cluster, for the Coverage popover: the primary first, then each
/// secondary with its own headline.
struct ClusterMember: Codable, FetchableRecord, Identifiable, Sendable {
    var articleID: String
    var feedTitle: String
    var title: String?
    var url: String?
    var dateArrived: String

    var id: String { articleID }
}
