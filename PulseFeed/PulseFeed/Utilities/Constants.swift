import Foundation

enum PulseFeedConstants {
    static let defaultFeedPollInterval = 300  // 5 minutes
    static let maxArticlesPerQuery = 200
    static let conditionalGetResetDays = 8

    /// Dedup compares new items against articles that arrived within this window.
    /// Retention must never drop below it, or old stories re-enter the feed as "new".
    static let dedupLookbackDays = 7
    /// A feed that fetches fine but has produced no article for this long reads as stale.
    static let staleFeedDays = 14

    /// AI tier: model calls per calendar day across both engines.
    static let aiDailyCap = 400
    /// Cloud/on-device enrichments per tick.
    static let maxEnrichmentsPerTick = 10
    /// Relevance bonus per additional outlet carrying the same story (capped at 3 extra).
    static let multiSourceBonusPerSource = 1.5

    /// Coin prices (CoinGecko markets call): every tier, including critical.
    static let cryptoInterval: TimeInterval = 120
    /// Stock, metal and currency quotes (whichever quote source): minimum spacing by power tier.
    static let yahooIntervalAC: TimeInterval = 300
    static let yahooIntervalBattery: TimeInterval = 1800
}
