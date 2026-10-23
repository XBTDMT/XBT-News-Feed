import Foundation

/// The bundled catalog (`Resources/Catalog/catalog.json`, decision G-1): every topic the app can
/// offer, each one level under a chip-level `NewsCategory`, and every checked source, each under one
/// topic. Chips, counts and toggles keep reading `feed.category`; topics are for curation (the
/// welcome flow, Settings › Sources, typed interests, topic-scoped alert patterns).
struct Catalog: Codable, Sendable, Equatable {
    var version: Int
    var topics: [CatalogTopic]
    var sources: [CatalogSource]

    static let regions: Set<String> = ["global", "us", "uk", "eu", "asia"]
    /// Provider tags a source may carry (`LiveScoreSource` raw values).
    static let providers: Set<String> = Set(LiveScoreSource.allCases.map(\.rawValue))

    static func load(from url: URL) throws -> Catalog {
        try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
    }

    /// `Contents/Resources/Catalog/catalog.json` in the app bundle (copied by `make bundle`), without the
    /// sources whose provider this build cannot run (ESPN's API in the public build).
    static var bundled: Catalog? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("Catalog/catalog.json") else { return nil }
        return (try? load(from: url))?.forBuild(providers: DataProviders.availableProviderTags)
    }

    /// Sources a category or topic tick never switches on while nobody has chosen them: the ones that start
    /// off (arXiv's 100–200 papers a day) and the ones the welcome flow never offers (not checked or failing).
    static func heldBack(in catalog: Catalog) -> Set<String> {
        Set(catalog.sources.filter { ($0.startsOff ?? false) || !$0.isOffered }.map(\.url))
    }

    /// `heldBack` for the bundled catalog (empty when there is no bundle, as in tests).
    static let heldBackURLs: Set<String> = bundled.map(heldBack(in:)) ?? []

    /// The catalog a build offers: a source tagged with a provider stays only when the build runs it.
    func forBuild(providers: Set<String>) -> Catalog {
        var c = self
        c.sources = sources.filter { $0.provider.map(providers.contains) ?? true }
        return c
    }

    func topic(_ id: String) -> CatalogTopic? { topics.first { $0.id == id } }

    func sources(topic id: String) -> [CatalogSource] { sources.filter { $0.topic == id } }

    /// Everything that would make the file wrong, one line each; empty when it is sound.
    func problems() -> [String] {
        var out: [String] = []
        let categories = Set(NewsCategory.pickerIDs)
        var seenTopics = Set<String>()
        for t in topics {
            if !seenTopics.insert(t.id).inserted { out.append("duplicate topic id: \(t.id)") }
            if !categories.contains(t.category) { out.append("topic \(t.label.lowercased()): unknown category \(t.category)") }
            for r in t.regions where !Self.regions.contains(r) { out.append("topic \(t.label.lowercased()): unknown region \(r)") }
        }
        var seenURLs = Set<String>()
        for s in sources {
            if !seenURLs.insert(s.url).inserted { out.append("duplicate source url: \(s.url)") }
            if !seenTopics.contains(s.topic) { out.append("source \(s.title): unknown topic \(s.topic)") }
            if !Self.regions.contains(s.region) { out.append("source \(s.title): unknown region \(s.region)") }
            if let p = s.provider, !Self.providers.contains(p) { out.append("source \(s.title): unknown provider \(p)") }
        }
        return out
    }
}

/// How the welcome flow's Topics step lays the topics out; not stored on feeds.
enum CatalogGroup: String, Codable, CaseIterable, Sendable {
    case news, money, techScience, sports, culture, life
}

struct CatalogTopic: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var label: String
    /// A `NewsCategory` id: the chip this topic's stories show under.
    var category: String
    var group: CatalogGroup
    /// Other words a person might type for it ("football" for soccer).
    var aliases: [String]
    /// People, teams, companies or coins to suggest following, by the short name headlines use ("lakers").
    var follows: [String]
    var regions: [String]
    /// Other names a person types for a follow ("lakers" → "los angeles lakers", "la lakers").
    var followForms: [String: [String]]? = nil
    /// Follows that are everyday words ("heat", "eagles"): inside a longer phrase they are not even suggested
    /// unless named in full or with filler around them ("heat pump" offers nothing). Typed as a phrase, or as
    /// one part of an and-list, of their own they are applied, as any exact name is (G-5).
    var everydayFollows: [String]? = nil

    func forms(of follow: String) -> [String] { [follow] + (followForms?[follow] ?? []) }
}

struct CatalogSource: Codable, Sendable, Equatable {
    var url: String
    var title: String
    var topic: String
    var region: String
    /// "rss" (RSS, Atom, JSON Feed), "json_api" or "websocket", as on `feed.type`.
    var type: String
    var pollInterval: Int
    /// When `make check-catalog` last fetched and parsed it (SQLite datetime, UTC).
    var checkedAt: String?
    var itemCount: Int?
    /// The catalog version that added it: 1 = a source every install seeds, above 1 = a catalog addition
    /// (arrives switched off and is not switched on by a category tick until the person chooses its topic).
    var since: Int?
    /// A service that needs this build's support ("espn") or a key ("balldontlie"); nil for an ordinary feed.
    var provider: String? = nil
    /// Offered switched off even when its topic is picked (arXiv's 100–200 papers a day).
    var startsOff: Bool? = nil

    /// What the welcome flow may offer: a feed the checker fetched and parsed, or a JSON API.
    var isOffered: Bool { type == "json_api" || checkedAt != nil }
}
