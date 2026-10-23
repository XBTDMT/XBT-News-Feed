import Foundation

/// Which of the three built designs the app runs (Native Pro, Deck, Stream). Resolved ONCE at launch;
/// changing it needs a relaunch (Settings › General › Design › Relaunch to apply).
enum AppDesign: String, CaseIterable, Sendable {
    case nativePro, deck, stream

    static let defaultsKey = "app_design"
    /// Testing hook: `PULSEFEED_DESIGN=nativePro|deck|stream` overrides the stored choice.
    static let environmentKey = "PULSEFEED_DESIGN"
    static let fallback: AppDesign = .deck

    /// The environment hook wins, then the stored choice, then Deck. Matching is case-insensitive.
    static func resolve(defaultsValue: String?, environmentValue: String?) -> AppDesign {
        for candidate in [environmentValue, defaultsValue] {
            if let raw = candidate?.trimmingCharacters(in: .whitespaces).lowercased(), !raw.isEmpty,
               let match = allCases.first(where: { $0.rawValue.lowercased() == raw }) {
                return match
            }
        }
        return fallback
    }

    /// The running design. Views read this, never UserDefaults, so a mid-session change cannot
    /// half-apply.
    static let current: AppDesign = resolve(
        defaultsValue: UserDefaults.standard.string(forKey: defaultsKey),
        environmentValue: ProcessInfo.processInfo.environment[environmentKey])

    var displayName: String {
        switch self {
        case .nativePro: return "Native Pro"
        case .deck: return "Deck"
        case .stream: return "Stream"
        }
    }

    var tagline: String {
        switch self {
        case .nativePro:
            return "The familiar three surfaces with a markets strip and unread counts, all in system materials."
        case .deck:
            return "Glance-first tiles in the native skin; a tile expands in place, so any headline is one click."
        case .stream:
            return "Pictures only where they earn it: a hero card for breaking, cards for clusters, rows for the rest."
        }
    }

    /// SF Symbol drawn as a template image in the menu bar.
    var glyphSymbolName: String {
        switch self {
        case .nativePro: return "newspaper"
        case .deck: return "square.grid.2x2"
        case .stream: return "square.stack"
        }
    }
}
