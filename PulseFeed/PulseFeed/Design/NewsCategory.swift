import Foundation

/// The one registry of categories the app knows. Feeds carry a category id; every chip row, sidebar,
/// bar chart, badge and notification toggle reads this list instead of its own copy.
/// `defaultEnabled` is only the chips' placeholder before the first database observation lands; a fresh install
/// starts with every source off and the welcome flow chooses (`WelcomeGate`, `prepareFreshInstall`).
struct NewsCategory: Identifiable, Sendable, Equatable {
    let id: String
    let label: String
    /// Fits a 34 pt column ("Fin", "Ent").
    let short: String
    /// The digest card's 3–4 letter badge.
    let badge: String
    let colorHex: String
    /// SF Symbol for sidebars.
    let symbol: String
    let defaultEnabled: Bool

    static let all: [NewsCategory] = [
        NewsCategory(id: "crypto", label: "Crypto", short: "Crypto", badge: "BTC", colorHex: "#FF9F0A", symbol: "bitcoinsign.circle", defaultEnabled: true),
        NewsCategory(id: "tech", label: "Tech", short: "Tech", badge: "TECH", colorHex: "#0A84FF", symbol: "cpu", defaultEnabled: true),
        NewsCategory(id: "ai", label: "AI", short: "AI", badge: "AI", colorHex: "#AF52DE", symbol: "sparkles", defaultEnabled: true),
        NewsCategory(id: "sports", label: "Sports", short: "Sports", badge: "NBA", colorHex: "#34C759", symbol: "sportscourt", defaultEnabled: true),
        NewsCategory(id: "f1", label: "F1", short: "F1", badge: "F1", colorHex: "#FF3B30", symbol: "flag.checkered", defaultEnabled: true),
        NewsCategory(id: "finance", label: "Finance", short: "Fin", badge: "FIN", colorHex: "#5E5CE6", symbol: "chart.line.uptrend.xyaxis", defaultEnabled: true),
        NewsCategory(id: "world", label: "World", short: "World", badge: "WRLD", colorHex: "#64D2FF", symbol: "globe", defaultEnabled: true),
        NewsCategory(id: "travel", label: "Travel", short: "Travel", badge: "TRVL", colorHex: "#30B0C7", symbol: "airplane", defaultEnabled: true),
        NewsCategory(id: "music", label: "Music", short: "Music", badge: "MUSIC", colorHex: "#FF2D55", symbol: "music.note", defaultEnabled: true),
        NewsCategory(id: "motors", label: "Cars & Bikes", short: "Motors", badge: "CARS", colorHex: "#8E8E93", symbol: "car", defaultEnabled: true),
        NewsCategory(id: "politics", label: "Politics", short: "Pol", badge: "POL", colorHex: "#A2845E", symbol: "building.columns", defaultEnabled: false),
        NewsCategory(id: "science", label: "Science", short: "Sci", badge: "SCI", colorHex: "#00C7BE", symbol: "atom", defaultEnabled: false),
        NewsCategory(id: "health", label: "Health", short: "Health", badge: "HLTH", colorHex: "#FF6482", symbol: "heart", defaultEnabled: false),
        NewsCategory(id: "gaming", label: "Gaming", short: "Games", badge: "GAME", colorHex: "#BF5AF2", symbol: "gamecontroller", defaultEnabled: false),
        NewsCategory(id: "entertainment", label: "Entertainment", short: "Ent", badge: "ENT", colorHex: "#FFD60A", symbol: "film", defaultEnabled: false),
        NewsCategory(id: "food", label: "Food", short: "Food", badge: "FOOD", colorHex: "#FF9500", symbol: "fork.knife", defaultEnabled: false),
        NewsCategory(id: "life", label: "Life", short: "Life", badge: "LIFE", colorHex: "#C58B52", symbol: "house", defaultEnabled: false),
    ]

    static let general = NewsCategory(id: "general", label: "General", short: "News", badge: "NEWS", colorHex: "#8E8E93", symbol: "newspaper", defaultEnabled: true)

    static func named(_ id: String) -> NewsCategory {
        all.first { $0.id == id } ?? general
    }

    /// Registry order, keeping only the ids that are enabled (categories with no enabled feed hide).
    static func visible(enabledIDs: Set<String>) -> [NewsCategory] {
        all.filter { enabledIDs.contains($0.id) }
    }

    /// The `limit` categories with the most unread, kept in registry order (ties break by registry
    /// order too). Bar charts have room for about six.
    static func top(_ categories: [NewsCategory], counts: [String: Int], limit: Int) -> [NewsCategory] {
        guard categories.count > limit else { return categories }
        let ranked = categories.enumerated().sorted { a, b in
            let ca = counts[a.element.id] ?? 0, cb = counts[b.element.id] ?? 0
            return ca != cb ? ca > cb : a.offset < b.offset
        }
        let keep = Set(ranked.prefix(limit).map(\.element.id))
        return categories.filter { keep.contains($0.id) }
    }

    /// Everything the seed data uses, for pickers.
    static var pickerIDs: [String] { all.map(\.id) + [general.id] }
}
