import AppKit
import Foundation

/// Settings › General › Appearance. Applies to every window and the popover at once (no relaunch).
/// Light is the default because the design sheets are light.
enum AppAppearance: String, CaseIterable, Sendable {
    case system, light, dark

    static let defaultsKey = "app_appearance"

    static func resolve(_ stored: String?) -> AppAppearance {
        guard let raw = stored?.trimmingCharacters(in: .whitespaces).lowercased(), !raw.isEmpty,
              let match = allCases.first(where: { $0.rawValue == raw }) else { return .light }
        return match
    }

    static var current: AppAppearance { resolve(UserDefaults.standard.string(forKey: defaultsKey)) }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    @MainActor
    static func apply(_ appearance: AppAppearance) {
        NSApp.appearance = appearance.nsAppearance
    }
}
