import Foundation

/// "984", "8.8k", "16k", "1.2M" — counts that must fit a tile, a bar label or a pill.
enum CompactCount {
    static func format(_ n: Int) -> String {
        let v = Double(n)
        func trimmed(_ x: Double, _ suffix: String) -> String {
            let s = String(format: "%.1f", x)
            return (s.hasSuffix(".0") ? String(s.dropLast(2)) : s) + suffix
        }
        switch n {
        case ..<1_000: return "\(n)"
        case ..<10_000: return trimmed(v / 1_000, "k")
        case ..<1_000_000: return "\(Int((v / 1_000).rounded(.down)))k"
        default: return trimmed(v / 1_000_000, "M")
        }
    }
}
