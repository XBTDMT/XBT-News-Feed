import Foundation

/// Power state as the engine sees it. `critical` = on battery AND (below 20% OR Low Power Mode).
enum PowerTier: Sendable, Equatable, CustomStringConvertible {
    case ac, battery, critical

    var description: String {
        switch self {
        case .ac: return "ac"
        case .battery: return "battery"
        case .critical: return "critical"
        }
    }
}

/// Pure scheduling math. Kept free of Foundation timers so it can be unit tested.
enum PollScheduling {
    /// On AC the engine follows the soonest due feed, clamped to this window.
    static let acFloor: TimeInterval = 60
    static let acCeiling: TimeInterval = 3600
    /// Used on AC when no polling feed exists (nothing is due, ever).
    static let acDefault: TimeInterval = 300
    /// Fixed cadences off AC.
    static let batteryInterval: TimeInterval = 300
    static let criticalInterval: TimeInterval = 1800
    /// Failing feeds back off: base * 2^min(errors, maxBackoffExponent), capped at maxEffectiveInterval.
    static let maxBackoffExponent = 5
    static let maxEffectiveInterval = 6 * 3600

    static func effectiveInterval(base: Int, consecutiveErrors: Int) -> Int {
        let exponent = max(0, min(consecutiveErrors, maxBackoffExponent))
        let backedOff = base << exponent
        return min(backedOff, maxEffectiveInterval)
    }

    static func nextTickDelay(tier: PowerTier, soonestDueIn: TimeInterval?) -> TimeInterval {
        switch tier {
        case .ac:
            guard let soonestDueIn else { return acDefault }
            return min(max(soonestDueIn, acFloor), acCeiling)
        case .battery:
            return batteryInterval
        case .critical:
            return criticalInterval
        }
    }

    /// How much slack the system may take when firing the tick. Wider off AC so it can coalesce work.
    static func tolerance(tier: PowerTier, delay: TimeInterval) -> TimeInterval {
        switch tier {
        case .ac: return max(10, delay * 0.2)
        case .battery: return 60
        case .critical: return 300
        }
    }
}
