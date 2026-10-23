import Foundation

/// When the engine fetches prices: coins every `cryptoInterval` on every tier (critical keeps one cheap
/// CoinGecko call so BTC still moves), everything else on the quote intervals and never on critical.
/// Nothing is fetched for a list with nothing in it.
enum MarketsSchedule {
    private static let coins: Set<String> = Set(CryptoQuotes.coinGeckoIDs)

    private static func quotesInterval(_ tier: PowerTier) -> TimeInterval? {
        switch tier {
        case .ac: return PulseFeedConstants.yahooIntervalAC
        case .battery: return PulseFeedConstants.yahooIntervalBattery
        case .critical: return nil
        }
    }

    static func due(tier: PowerTier, now: Date, lastCrypto: Date, lastQuotes: Date, instruments: [String]) -> (crypto: Bool, quotes: Bool) {
        let wantsCrypto = instruments.contains { coins.contains($0) }
        let wantsQuotes = instruments.contains { !coins.contains($0) }
        let crypto = wantsCrypto && now.timeIntervalSince(lastCrypto) >= PulseFeedConstants.cryptoInterval
        let quotes = wantsQuotes && quotesInterval(tier).map { now.timeIntervalSince(lastQuotes) >= $0 } == true
        return (crypto, quotes)
    }

    /// Seconds until the next price fetch is due (0 = now), nil when none will be; the tick scheduler wakes
    /// for it as it does for the soonest feed.
    static func secondsUntilDue(tier: PowerTier, now: Date, lastCrypto: Date, lastQuotes: Date, instruments: [String]) -> TimeInterval? {
        var out: [TimeInterval] = []
        if instruments.contains(where: { coins.contains($0) }) {
            out.append(max(0, PulseFeedConstants.cryptoInterval - now.timeIntervalSince(lastCrypto)))
        }
        if instruments.contains(where: { !coins.contains($0) }), let interval = quotesInterval(tier) {
            out.append(max(0, interval - now.timeIntervalSince(lastQuotes)))
        }
        return out.min()
    }
}
