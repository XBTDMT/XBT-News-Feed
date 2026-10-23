import Foundation

/// One-time greetings. The "Notifications are working" banner used to fire on every launch.
enum FirstRun {
    static let welcomeKey = "welcome_notification_sent"

    static func shouldSendWelcome(_ defaults: UserDefaults = .standard) -> Bool {
        !defaults.bool(forKey: welcomeKey)
    }

    static func recordWelcomeSent(_ defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: welcomeKey)
    }
}
