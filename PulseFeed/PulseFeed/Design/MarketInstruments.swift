import Foundation

/// An instrument the markets strip can show (spec D10). The person picks up to five; the engine fetches
/// only those, from the provider each job uses (`DataProviders`).
struct MarketInstrument: Identifiable, Sendable, Equatable {
    enum Kind: Sendable { case crypto, equity, metal, energy, fx }

    let id: String          // engine key, the PriceUpdate symbol
    let label: String
    let kind: Kind

    static let all: [MarketInstrument] = [
        MarketInstrument(id: "bitcoin", label: "BTC", kind: .crypto),
        MarketInstrument(id: "ethereum", label: "ETH", kind: .crypto),
        MarketInstrument(id: "solana", label: "SOL", kind: .crypto),
        MarketInstrument(id: "ripple", label: "XRP", kind: .crypto),
        MarketInstrument(id: "spy", label: "SPY", kind: .equity),
        MarketInstrument(id: "qqq", label: "QQQ", kind: .equity),
        MarketInstrument(id: "mag7", label: "MAG7", kind: .equity),
        MarketInstrument(id: "gold", label: "Gold", kind: .metal),
        MarketInstrument(id: "oil", label: "Oil", kind: .energy),
        MarketInstrument(id: "dxy", label: "DXY", kind: .fx),
        MarketInstrument(id: "eurusd", label: "EUR/USD", kind: .fx),
    ]

    static let maxChosen = 5
    /// What the welcome flow offers when a Money topic is picked and nothing is chosen yet.
    static let suggested = ["bitcoin", "spy", "qqq", "gold", "dxy"]
    static let defaultsKey = SettingsFreeze.marketInstrumentsKey

    static func named(_ id: String) -> MarketInstrument? { all.first { $0.id == id } }

    static func cleaned(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return Array(ids.filter { named($0) != nil && seen.insert($0).inserted }.prefix(maxChosen))
    }

    /// The person's list; a new install has none until it chooses (an install in use had today's five
    /// written by SettingsFreeze).
    static func stored(_ d: UserDefaults) -> [String] { cleaned(d.stringArray(forKey: defaultsKey) ?? []) }

    static func store(_ ids: [String], _ d: UserDefaults) { d.set(cleaned(ids), forKey: defaultsKey) }

    /// The label says what the number is: a token ("SPYx"), a fund standing in ("GLD"), a computed index.
    static func label(_ id: String, quotes: QuoteSource) -> String {
        let base = named(id)?.label ?? id
        switch quotes {
        case .keyless:
            return ["spy": "SPYx", "qqq": "QQQx", "mag7": "MAG7x", "gold": "PAXG", "dxy": "USD idx"][id] ?? base
        case .finnhub:
            return ["gold": "GLD", "oil": "USO", "dxy": "UUP"][id] ?? base
        case .yahoo:
            return base
        }
    }

    /// Oil has no allowed keyless source (tokenized oil trades too thinly to trust).
    static func isAvailable(_ id: String, quotes: QuoteSource) -> Bool {
        !(id == "oil" && quotes == .keyless)
    }
}
