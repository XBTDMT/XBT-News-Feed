import Foundation

/// Writes the built-in alert rules, AI profile and market instruments into an existing install's own
/// settings, once, before the engine starts. Those three read their stored value when there is one and
/// the built-in default otherwise, so an install that had never edited them was running on the
/// defaults; freezing them lets the defaults change for a new user without changing an install that is
/// already in use. A fresh install gets nothing written (its welcome flow chooses), and a stored value
/// is never overwritten. Decided once, at the first launch of a build that has it (`doneKey`): a fresh
/// install never pins the built-ins later.
enum SettingsFreeze {
    static let marketInstrumentsKey = "market_instruments"
    static let todaysInstruments = ["bitcoin", "mag7", "spy", "gold", "dxy"]

    static let doneKey = "settings_freeze_done"

    static func materialize(_ d: UserDefaults, isExistingInstall: Bool) {
        guard !d.bool(forKey: doneKey) else { return }
        d.set(true, forKey: doneKey)
        guard isExistingInstall else { return }
        if d.string(forKey: UrgencyRules.defaultsKey) == nil {
            d.set(UrgencyRules.defaults.asText, forKey: UrgencyRules.defaultsKey)
        }
        if d.string(forKey: AIProfile.defaultsKey) == nil {
            d.set(AIProfile.builtIn.asText, forKey: AIProfile.defaultsKey)
        }
        if d.stringArray(forKey: marketInstrumentsKey) == nil {
            d.set(todaysInstruments, forKey: marketInstrumentsKey)
        }
    }
}
