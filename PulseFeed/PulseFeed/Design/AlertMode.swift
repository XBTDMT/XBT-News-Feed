import Foundation

/// How much the app may interrupt (the welcome flow's Alerts step, Settings › Notifications). An install
/// that never chose keeps today's behaviour: urgent alerts plus the recap.
enum AlertMode: String, CaseIterable, Sendable {
    case breakingAndRecap = "breaking"
    /// Urgent stories are not alerted on their own; they lead the next recap instead.
    case recapOnly = "recap"
    /// No banners at all; the menu bar count and the popover still show what is new.
    case quiet

    static let defaultsKey = "alert_mode"

    static func stored(_ d: UserDefaults) -> AlertMode {
        d.string(forKey: defaultsKey).flatMap(AlertMode.init(rawValue:)) ?? .breakingAndRecap
    }

    var allowsUrgent: Bool { self == .breakingAndRecap }
    var allowsRecap: Bool { self != .quiet }
    /// A price alert the person set waits while Quiet (it stays armed and fires once Quiet is off).
    var allowsPriceAlerts: Bool { self != .quiet }

    var label: String {
        switch self {
        case .breakingAndRecap: return "Breaking + recap"
        case .recapOnly: return "Recap only"
        case .quiet: return "Quiet"
        }
    }
}
