import Foundation

/// Where stock, metal and currency prices come from. Yahoo is private-build only (its terms, G-2).
enum QuoteSource: String, CaseIterable, Sendable {
    case yahoo, finnhub, keyless

    static var available: [QuoteSource] { BuildFlavor.isPublic ? [.finnhub, .keyless] : [.yahoo, .finnhub, .keyless] }

    var name: String {
        switch self {
        case .yahoo: return "Yahoo Finance"
        case .finnhub: return "Finnhub"
        case .keyless: return "CoinGecko and the ECB (no key)"
        }
    }
}

/// Where live NBA scores come from. ESPN is private-build only.
enum LiveScoreSource: String, CaseIterable, Sendable {
    case espn, balldontlie

    static var available: [LiveScoreSource] { BuildFlavor.isPublic ? [.balldontlie] : [.espn, .balldontlie] }

    var name: String {
        switch self {
        case .espn: return "ESPN"
        case .balldontlie: return "balldontlie"
        }
    }
}

/// Where live crypto prices stream from while on power. Binance is private-build only.
enum CryptoStreamSource: String, CaseIterable, Sendable {
    case binance, gemini

    static var available: [CryptoStreamSource] { BuildFlavor.isPublic ? [.gemini] : [.binance, .gemini] }

    var name: String {
        switch self {
        case .binance: return "Binance"
        case .gemini: return "Gemini"
        }
    }
}

/// One provider per job (spec D12, G-2). The private build defaults to today's providers, so an install
/// that never chose keeps Yahoo, ESPN and Binance; the public build defaults to the keyless ones, and a
/// person's own free key upgrades a job (`effective`).
struct DataProviders: Equatable, Sendable {
    var quotes: QuoteSource
    var liveScores: LiveScoreSource
    var cryptoStream: CryptoStreamSource

    static let quotesKey = "provider_quotes"
    static let liveScoresKey = "provider_live_scores"
    static let cryptoStreamKey = "provider_crypto_stream"

    static var defaults: DataProviders {
        BuildFlavor.isPublic
            ? DataProviders(quotes: .keyless, liveScores: .balldontlie, cryptoStream: .gemini)
            : DataProviders(quotes: .yahoo, liveScores: .espn, cryptoStream: .binance)
    }

    /// The catalog `provider` tags this build can run (`Catalog.forBuild`).
    static var availableProviderTags: Set<String> { Set(LiveScoreSource.available.map(\.rawValue)) }

    static func stored(_ d: UserDefaults) -> DataProviders {
        let base = defaults
        func pick<T: RawRepresentable & CaseIterable>(_ key: String, _ available: [T], _ fallback: T) -> T where T.RawValue == String {
            guard let raw = d.string(forKey: key), let v = T(rawValue: raw), available.contains(where: { $0.rawValue == v.rawValue }) else { return fallback }
            return v
        }
        return DataProviders(
            quotes: pick(quotesKey, QuoteSource.available, base.quotes),
            liveScores: pick(liveScoresKey, LiveScoreSource.available, base.liveScores),
            cryptoStream: pick(cryptoStreamKey, CryptoStreamSource.available, base.cryptoStream))
    }

    func store(_ d: UserDefaults) {
        d.set(quotes.rawValue, forKey: Self.quotesKey)
        d.set(liveScores.rawValue, forKey: Self.liveScoresKey)
        d.set(cryptoStream.rawValue, forKey: Self.cryptoStreamKey)
    }

    /// What actually runs: a job that needs a key falls back without one. In the public build a Finnhub key
    /// switches quotes to Finnhub by itself (there is no picker there).
    func effective(keys: ProviderKeyStore) -> DataProviders {
        var p = self
        let hasFinnhub = keys.get(.finnhub) != nil
        if BuildFlavor.isPublic {
            p.quotes = hasFinnhub ? .finnhub : .keyless
        } else if p.quotes == .finnhub, !hasFinnhub {
            p.quotes = .yahoo
        }
        if p.liveScores == .balldontlie, keys.get(.balldontlie) == nil, LiveScoreSource.available.contains(.espn) {
            p.liveScores = .espn
        }
        return p
    }

    /// The credit lines the chosen prices owe (CoinGecko and the ECB ask for one; the rest name the source).
    static func credits(_ p: DataProviders, instruments: [String]) -> [String] {
        var out: [String] = []
        func add(_ s: String) { if !out.contains(s) { out.append(s) } }
        let coins: Set<String> = ["bitcoin", "ethereum", "solana", "ripple"]
        let crypto = instruments.contains { coins.contains($0) }
        let others = instruments.filter { !coins.contains($0) }
        if crypto {
            add(coinGeckoCredit)
            add(p.cryptoStream == .gemini ? geminiCredit : "Live prices: Binance")
        }
        let fx = others.contains("dxy") || others.contains("eurusd")
        switch p.quotes {
        case .keyless:
            if others.contains(where: { ["spy", "qqq", "mag7", "gold"].contains($0) }) { add(coinGeckoCredit) }
            if fx { add(ecbCredit) }
        case .finnhub:
            if others.contains(where: { $0 != "eurusd" }) { add("Quotes: Finnhub") }
            if others.contains("eurusd") { add(ecbCredit) }
        case .yahoo:
            if !others.isEmpty { add("Yahoo Finance") }
        }
        return out
    }

    static let coinGeckoCredit = "Powered by CoinGecko"
    static let geminiCredit = "Data provided by Gemini"
    static let ecbCredit = "Source: ECB"
    /// Where the CoinGecko credit links (its attribution guide asks for a link to coingecko.com).
    static let coinGeckoURL = URL(string: "https://www.coingecko.com")!

    /// The line every markets display carries beside its prices (CoinGecko's terms: near the data, at 10pt
    /// or more): the credits from `credits` that a licence asks for, shortest form, joined with " · ".
    /// Yahoo, Binance and Finnhub owe none; nil when no shown price needs one.
    static func stripCredit(_ effective: DataProviders, instruments: [String]) -> String? {
        let short = [coinGeckoCredit: coinGeckoCredit, geminiCredit: "Gemini", ecbCredit: ecbCredit]
        let parts = credits(effective, instruments: instruments).compactMap { short[$0] }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
