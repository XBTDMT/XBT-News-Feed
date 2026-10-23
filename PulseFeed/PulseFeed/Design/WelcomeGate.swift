import Foundation

/// Who sees the "Make it yours" flow (spec §6): a fresh install does, until it finishes; an install that
/// already has stories is treated as having finished it and never sees it unprompted (an install in use, such as the owner's).
enum WelcomeGate {
    static let completedKey = "welcome_completed"

    struct LaunchPlan: Equatable, Sendable {
        var showWelcome: Bool
        /// Switch every source off and drop the seed interests before the engine starts (the flow chooses).
        var prepareFreshInstall: Bool
        /// A fresh install is asked in the flow's Alerts step instead.
        var askNotificationsAtLaunch: Bool
    }

    static func launchPlan(_ d: UserDefaults, hasHistory: Bool) -> LaunchPlan {
        if d.bool(forKey: completedKey) {
            return LaunchPlan(showWelcome: false, prepareFreshInstall: false, askNotificationsAtLaunch: true)
        }
        if hasHistory {
            markCompleted(d)
            return LaunchPlan(showWelcome: false, prepareFreshInstall: false, askNotificationsAtLaunch: true)
        }
        return LaunchPlan(showWelcome: true, prepareFreshInstall: true, askNotificationsAtLaunch: false)
    }

    static func markCompleted(_ d: UserDefaults) { d.set(true, forKey: completedKey) }
}
