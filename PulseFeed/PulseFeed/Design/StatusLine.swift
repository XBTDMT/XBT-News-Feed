import Foundation

/// Idea ③: "AC · polled 2m ago · next in 3m · 18 requests, 0.6 MB", from values the engine already
/// computes. Missing parts are omitted, never rendered as placeholders.
enum StatusLine {
    static func tierWord(_ tier: PowerTier) -> String {
        switch tier {
        case .ac: return "AC"
        case .battery: return "Battery"
        case .critical: return "Low battery"
        }
    }

    /// "45s", "2m", "1h", "3d" (never negative).
    static func relative(_ seconds: TimeInterval) -> String {
        let s = max(0, seconds)
        if s < 60 { return "\(Int(s))s" }
        if s < 3600 { return "\(Int(s / 60))m" }
        if s < 86400 { return "\(Int(s / 3600))h" }
        return "\(Int(s / 86400))d"
    }

    /// One decimal below 10 MB, whole megabytes above.
    static func megabytes(_ bytes: Int) -> String {
        let mb = Double(bytes) / 1_000_000
        return mb < 10 ? String(format: "%.1f MB", mb) : "\(Int(mb.rounded())) MB"
    }

    static func format(
        tier: PowerTier, now: Date, lastTickAt: Date?, nextTickAt: Date?, requests: Int?, bytes: Int?
    ) -> String {
        var parts = [tierWord(tier)]
        if let lastTickAt {
            parts.append("polled \(relative(now.timeIntervalSince(lastTickAt))) ago")
        }
        if let nextTickAt {
            let delta = nextTickAt.timeIntervalSince(now)
            parts.append(delta <= 0 ? "polling now" : "next in \(relative(delta))")
        }
        if let requests {
            var s = "\(requests) requests"
            if let bytes { s += ", " + megabytes(bytes) }
            parts.append(s)
        }
        return parts.joined(separator: " · ")
    }
}
