import SwiftUI
import AppKit

/// Colours, radius and type per design. Injected with `.environment(\.designTokens, …)` by the router
/// and read with `@Environment(\.designTokens)` by every shared component.
struct DesignTokens: @unchecked Sendable {
    let accent: Color
    let canvas: Color
    let card: Color
    let cardBorder: Color
    let secondaryText: Color
    let breaking: Color
    let important: Color
    let ok: Color
    let radius: CGFloat
    /// Registered font family (Manrope for Stream); nil = system font.
    let fontFamily: String?

    /// The AppKit font `font(size)` draws with (regular weight), for measuring text before layout.
    func nsFont(_ size: CGFloat) -> NSFont {
        if let fontFamily, Fonts.isRegistered(fontFamily),
           let f = NSFontManager.shared.font(withFamily: fontFamily, traits: [], weight: 5, size: size) {
            return f
        }
        return .systemFont(ofSize: size)
    }

    func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if let fontFamily, Fonts.isRegistered(fontFamily) {
            return .custom(fontFamily, size: size).weight(weight)
        }
        return .system(size: size, weight: weight)
    }

    static let nativePro = DesignTokens(
        accent: Color(hex: "#0A84FF"), canvas: .clear,
        card: Color(nsColor: .controlBackgroundColor), cardBorder: Color(nsColor: .separatorColor),
        secondaryText: .secondary,
        breaking: Color(hex: "#FF3B30"), important: Color(hex: "#E8B931"), ok: Color(hex: "#34C759"),
        radius: 10, fontFamily: nil)

    static let deck = DesignTokens(
        accent: Color(hex: "#0A84FF"), canvas: Color(light: "#F2F2F7", dark: "#1C1C1E"),
        card: Color(nsColor: .controlBackgroundColor), cardBorder: Color(nsColor: .separatorColor),
        secondaryText: .secondary,
        breaking: Color(hex: "#FF3B30"), important: Color(hex: "#E8B931"), ok: Color(hex: "#34C759"),
        radius: 12, fontFamily: nil)

    static let stream = DesignTokens(
        accent: Color(hex: "#F2634F"), canvas: Color(light: "#F1F2F4", dark: "#17181C"),
        card: Color(light: "#FFFFFF", dark: "#22242A"), cardBorder: Color(light: "#E3E5E9", dark: "#2C2F36"),
        secondaryText: Color(light: "#6B7079", dark: "#9AA0A8"),
        breaking: Color(hex: "#E5484D"), important: Color(hex: "#E8B931"), ok: Color(hex: "#2FB870"),
        radius: 12, fontFamily: "Manrope")
}

extension EnvironmentValues {
    @Entry var designTokens: DesignTokens = .nativePro
}

extension Color {
    /// "#RRGGBB" or "RRGGBB".
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(
            red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255)
    }

    /// A dynamic colour that follows the system appearance.
    init(light: String, dark: String) {
        let l = NSColor(Color(hex: light))
        let d = NSColor(Color(hex: dark))
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? d : l
        })
    }
}

extension AppDesign {
    var tokens: DesignTokens {
        switch self {
        case .nativePro: return .nativePro
        case .deck: return .deck
        case .stream: return .stream
        }
    }
}
