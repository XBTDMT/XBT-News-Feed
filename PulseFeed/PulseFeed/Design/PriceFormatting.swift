import Foundation

/// The one price/change formatter (popover strip, sidebar, tiles, menu bar capsule).
enum PriceFormatting {
    private static let grouped: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.groupingSeparator = ","
        f.usesGroupingSeparator = true
        return f
    }()

    /// DXY and the computed USD index are indexes (no "$", two decimals); a currency pair is a rate (no "$",
    /// four decimals); ≥ 1000 groups without decimals; ≥ 1 keeps two decimals; sub-dollar keeps four.
    static func price(_ value: Double, symbol: String) -> String {
        let s = symbol.uppercased()
        if s == "DXY" || s == "USD IDX" { return String(format: "%.2f", value) }
        if s == "EUR/USD" { return String(format: "%.4f", value) }
        if value >= 1000 { return "$" + (grouped.string(from: NSNumber(value: value)) ?? "\(Int(value))") }
        if value >= 1 { return String(format: "$%.2f", value) }
        return String(format: "$%.4f", value)
    }

    /// "+1.8%" / "-1.4%"; nil when the change is unknown.
    static func change(_ pct: Double?) -> String? {
        guard let pct else { return nil }
        let rounded = (pct * 10).rounded() / 10
        if rounded == 0 { return "0.0%" }   // never "-0.0%"
        return String(format: "%+.1f%%", rounded)
    }
}
