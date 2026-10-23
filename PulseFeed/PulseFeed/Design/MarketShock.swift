import Foundation

/// A big move in a chosen instrument gets its own alert (part of the notification model; never wired before
/// 2026-10-22). Decided from numbers, under the urgent budget, and only while the alert mode allows urgent
/// alerts. On for every install (the owner, 2026-10-22: "on is fine"), switchable in Settings › Notifications.
///
/// One alert per move: a direction that alerted stays latched (stored, so a relaunch or a new day does not
/// repeat it: Friday's −3 % still reads −3 % all weekend) and re-arms only once the move falls back under
/// half the threshold.
enum MarketShock {
    static let enabledKey = "market_shock_alerts"
    static let latchedKey = "market_shock_latched"

    static func isEnabled(_ d: UserDefaults) -> Bool { d.object(forKey: enabledKey) as? Bool ?? true }

    static func loadLatched(_ d: UserDefaults) -> Set<String> { Set(d.stringArray(forKey: latchedKey) ?? []) }
    static func saveLatched(_ latched: Set<String>, _ d: UserDefaults) { d.set(latched.sorted(), forKey: latchedKey) }

    private static func threshold(_ instrument: String, _ rules: UrgencyRules) -> Double? {
        switch MarketInstrument.named(instrument)?.kind {
        case .equity: return rules.spyThreshold
        case .crypto: return rules.btcThreshold
        default: return nil
        }
    }

    /// Whether this update alerts, and the latch afterwards.
    static func step(instrument: String, change24h: Double?, chosen: [String], rules: UrgencyRules,
                     enabled: Bool, allowsUrgent: Bool, latched: Set<String>) -> (alert: Bool, latched: Set<String>) {
        guard let change24h, let limit = threshold(instrument, rules) else { return (false, latched) }
        var latched = latched
        let up = "\(instrument):up", down = "\(instrument):down"
        // Re-arm a direction once the move is back under half the threshold (or has turned the other way).
        if !(change24h >= limit / 2) { latched.remove(up) }
        if !(change24h <= -limit / 2) { latched.remove(down) }
        let key = change24h >= 0 ? up : down
        guard enabled, allowsUrgent, chosen.contains(instrument), !latched.contains(key),
              UrgencyClassifier.isMarketShock(instrument: instrument, change24h: change24h, rules: rules) else { return (false, latched) }
        latched.insert(key)
        return (true, latched)
    }

    /// Coins trade around the clock, and so do the tokenized stocks the keyless source uses: their change is
    /// a rolling 24 h one, not the day's.
    static func isRolling24h(_ instrument: String, quotes: QuoteSource) -> Bool {
        MarketInstrument.named(instrument)?.kind == .crypto || quotes == .keyless
    }

    /// "SPY -2.6% today" / "BTC +7.4% in 24 h".
    static func title(label: String, change: Double, rolling24h: Bool) -> String {
        "\(label) \(PriceFormatting.change(change) ?? "") \(rolling24h ? "in 24 h" : "today")"
    }
}
