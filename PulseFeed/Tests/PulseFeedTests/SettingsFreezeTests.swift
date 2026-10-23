import XCTest
@testable import PulseFeed

/// An install that already has stories gets today's alert rules, AI profile and markets written into
/// its own settings, so the built-in defaults can change without changing what that install does.
/// A fresh install gets nothing written, and nothing already stored is ever overwritten.
final class SettingsFreezeTests: XCTestCase {
    private var suite: String!
    private var d: UserDefaults!

    override func setUp() {
        suite = "SettingsFreezeTests-\(UUID().uuidString)"
        d = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        d.removePersistentDomain(forName: suite)
    }

    func testExistingInstallGetsTodaysSettingsWritten() {
        SettingsFreeze.materialize(d, isExistingInstall: true)
        XCTAssertEqual(d.string(forKey: "urgency_rules"), UrgencyRules.defaults.asText)
        XCTAssertEqual(d.string(forKey: "ai_profile_text"), AIProfile.builtIn.asText)
        XCTAssertEqual(d.stringArray(forKey: "market_instruments"), ["bitcoin", "mag7", "spy", "gold", "dxy"])
    }

    func testStoredValuesAreNeverOverwritten() {
        d.set("# Urgent\nfoo", forKey: "urgency_rules")
        d.set(["spy"], forKey: "market_instruments")
        SettingsFreeze.materialize(d, isExistingInstall: true)
        XCTAssertEqual(d.string(forKey: "urgency_rules"), "# Urgent\nfoo")
        XCTAssertEqual(d.stringArray(forKey: "market_instruments"), ["spy"])
        XCTAssertEqual(d.string(forKey: "ai_profile_text"), AIProfile.builtIn.asText)
    }

    func testFreshInstallWritesNothing() {
        SettingsFreeze.materialize(d, isExistingInstall: false)
        XCTAssertNil(d.string(forKey: "urgency_rules"))
        XCTAssertNil(d.string(forKey: "ai_profile_text"))
        XCTAssertNil(d.stringArray(forKey: "market_instruments"))
    }

    /// The freeze is decided once, at the first launch of a build that has it: an install that is fresh
    /// then never pins the built-ins it later runs on (audit 2026-10-22, finding 2).
    func testAFreshInstallIsNeverFrozenLater() {
        SettingsFreeze.materialize(d, isExistingInstall: false)
        SettingsFreeze.materialize(d, isExistingInstall: true)
        XCTAssertNil(d.string(forKey: "urgency_rules"))
        XCTAssertNil(d.stringArray(forKey: "market_instruments"))
    }

    func testAnExistingInstallIsFrozenOnceOnly() {
        SettingsFreeze.materialize(d, isExistingInstall: true)
        d.removeObject(forKey: "ai_profile_text")
        SettingsFreeze.materialize(d, isExistingInstall: true)
        XCTAssertNil(d.string(forKey: "ai_profile_text"), "a second launch writes nothing")
    }

}
