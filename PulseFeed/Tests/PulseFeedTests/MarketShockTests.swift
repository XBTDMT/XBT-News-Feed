import XCTest
@testable import PulseFeed

/// Price-move alerts are decided from numbers, only for the chosen instruments, once per move (the owner,
/// 2026-10-22: on for every install, switchable). A move alerts once and re-arms only after it falls back.
final class MarketShockTests: XCTestCase {
    private let rules = UrgencyRules.defaults

    private func step(_ id: String, _ change: Double?, chosen: [String]? = nil, enabled: Bool = true,
                      urgent: Bool = true, latched: Set<String> = []) -> (alert: Bool, latched: Set<String>) {
        MarketShock.step(instrument: id, change24h: change, chosen: chosen ?? [id], rules: rules,
                         enabled: enabled, allowsUrgent: urgent, latched: latched)
    }

    func testEquityUsesTheSPYThreshold() {
        XCTAssertTrue(step("spy", 2.5).alert)
        XCTAssertFalse(step("spy", 2.4).alert)
        XCTAssertTrue(step("qqq", -3.0).alert)
        XCTAssertTrue(step("mag7", 2.6).alert)
    }

    func testCryptoUsesTheBTCThreshold() {
        XCTAssertTrue(step("ethereum", -7.0).alert)
        XCTAssertFalse(step("bitcoin", 6.9).alert)
    }

    func testGoldAndDollarNeverShock() {
        for id in ["gold", "oil", "dxy", "eurusd"] { XCTAssertFalse(step(id, 12).alert, id) }
        XCTAssertFalse(step("spy", nil).alert)
    }

    func testOnlyChosenInstruments() {
        XCTAssertFalse(step("spy", 5, chosen: ["bitcoin"]).alert)
    }

    /// Friday's −3 % close still reads −3 % on Saturday, Sunday and Monday before the open: one alert.
    func testTheSameMoveAlertsOnceAcrossDays() {
        let first = step("spy", -3.0)
        XCTAssertTrue(first.alert)
        let saturday = step("spy", -3.0, latched: first.latched)
        XCTAssertFalse(saturday.alert)
        XCTAssertFalse(step("spy", -3.1, latched: saturday.latched).alert)
    }

    func testRearmsOnlyAfterTheMoveFallsBack() {
        let first = step("spy", -3.0)
        let still = step("spy", -1.5, latched: first.latched)   // above half the threshold: still latched
        XCTAssertFalse(step("spy", -3.0, latched: still.latched).alert)
        let calm = step("spy", -1.0, latched: first.latched)    // under half: re-armed
        XCTAssertTrue(step("spy", -3.0, latched: calm.latched).alert)
    }

    func testOppositeDirectionIsItsOwnMove() {
        let down = step("spy", -3.0)
        XCTAssertTrue(step("spy", 3.0, latched: down.latched).alert)
    }

    func testSwitchedOffOrUrgentNotAllowed() {
        XCTAssertFalse(step("spy", 5, enabled: false).alert)
        XCTAssertFalse(step("spy", 5, urgent: false).alert)
    }

    /// The latch is stored, so a relaunch the same day (or any day) does not alert the same move again.
    func testLatchSurvivesARelaunch() {
        let suite = "MarketShockTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        XCTAssertEqual(MarketShock.loadLatched(d), [])
        let first = step("spy", -3.0)
        MarketShock.saveLatched(first.latched, d)
        XCTAssertFalse(step("spy", -3.0, latched: MarketShock.loadLatched(d)).alert)
    }

    func testOnByDefault() {
        let suite = "MarketShockTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        XCTAssertTrue(MarketShock.isEnabled(d))
        d.set(false, forKey: MarketShock.enabledKey)
        XCTAssertFalse(MarketShock.isEnabled(d))
    }

    /// Coins, and stocks from tokenized copies (they trade around the clock), carry a 24 h change, not the day's.
    func testBannerText() {
        XCTAssertEqual(MarketShock.title(label: "SPY", change: -2.61, rolling24h: false), "SPY -2.6% today")
        XCTAssertEqual(MarketShock.title(label: "BTC", change: 7.44, rolling24h: true), "BTC +7.4% in 24 h")
        XCTAssertFalse(MarketShock.isRolling24h("spy", quotes: .yahoo))
        XCTAssertFalse(MarketShock.isRolling24h("spy", quotes: .finnhub))
        XCTAssertTrue(MarketShock.isRolling24h("spy", quotes: .keyless))
        XCTAssertTrue(MarketShock.isRolling24h("bitcoin", quotes: .yahoo))
    }
}
