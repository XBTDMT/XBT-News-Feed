import XCTest
@testable import PulseFeed

/// AIBudget is the pure bookkeeping behind AIGate: a daily call cap that rolls
/// over by calendar day, and an exponential cooldown after failures.
final class AIBudgetTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testAdmitCountsCallsAndDeniesAtCap() {
        var budget = AIBudget()
        XCTAssertTrue(budget.admit(now: t0, today: "2026-09-05", dailyCap: 2))
        XCTAssertTrue(budget.admit(now: t0, today: "2026-09-05", dailyCap: 2))
        XCTAssertFalse(budget.admit(now: t0, today: "2026-09-05", dailyCap: 2))
        XCTAssertEqual(budget.callsUsed, 2)
    }

    func testNewDayResetsTheCounter() {
        var budget = AIBudget()
        _ = budget.admit(now: t0, today: "2026-09-05", dailyCap: 1)
        XCTAssertFalse(budget.admit(now: t0, today: "2026-09-05", dailyCap: 1))
        XCTAssertTrue(budget.admit(now: t0, today: "2026-09-06", dailyCap: 1))
        XCTAssertEqual(budget.callsUsed, 1)
        XCTAssertEqual(budget.day, "2026-09-06")
    }

    func testFailureStartsThirtySecondCooldownThatDoublesAndCaps() {
        var budget = AIBudget()
        budget.recordFailure(now: t0)
        XCTAssertEqual(budget.cooldownUntil, t0.addingTimeInterval(30))
        budget.recordFailure(now: t0)
        XCTAssertEqual(budget.cooldownUntil, t0.addingTimeInterval(60))
        for _ in 0..<10 { budget.recordFailure(now: t0) }
        XCTAssertEqual(budget.cooldownUntil, t0.addingTimeInterval(1800))
    }

    func testAdmitIsDeniedDuringCooldownAndAllowedAfter() {
        var budget = AIBudget()
        budget.recordFailure(now: t0)
        XCTAssertFalse(budget.admit(now: t0.addingTimeInterval(10), today: "2026-09-05", dailyCap: 100))
        XCTAssertTrue(budget.admit(now: t0.addingTimeInterval(31), today: "2026-09-05", dailyCap: 100))
    }

    func testSuccessClearsCooldownAndFailureStreak() {
        var budget = AIBudget()
        budget.recordFailure(now: t0)
        budget.recordFailure(now: t0)
        budget.recordSuccess()
        XCTAssertNil(budget.cooldownUntil)
        XCTAssertEqual(budget.consecutiveFailures, 0)
        budget.recordFailure(now: t0)
        XCTAssertEqual(budget.cooldownUntil, t0.addingTimeInterval(30), "streak restarts from the base cooldown")
    }

    func testAIEnabledDefaultsToTrueWhenNeverWritten() {
        let suite = "PulseFeedTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(AIGate.isEnabled(in: defaults))
        defaults.set(false, forKey: "ai_enabled")
        XCTAssertFalse(AIGate.isEnabled(in: defaults))
    }
}

/// Which engines a call may use. Typed interests are on-device only: nothing typed leaves the Mac
/// (spec §5.2; audit 2026-10-22, finding 3).
final class EngineOrderTests: XCTestCase {
    func testOnDeviceOnlyNeverIncludesClaude() {
        XCTAssertEqual(AIGate.engineOrder(preferOnDevice: true, onDeviceOnly: true, onDeviceAvailable: true, claudeAvailable: true), ["on-device"])
        XCTAssertEqual(AIGate.engineOrder(preferOnDevice: true, onDeviceOnly: true, onDeviceAvailable: false, claudeAvailable: true), [])
    }

    func testOtherCallsKeepTheirOrder() {
        XCTAssertEqual(AIGate.engineOrder(preferOnDevice: true, onDeviceOnly: false, onDeviceAvailable: true, claudeAvailable: true), ["on-device", "claude"])
        XCTAssertEqual(AIGate.engineOrder(preferOnDevice: false, onDeviceOnly: false, onDeviceAvailable: true, claudeAvailable: true), ["claude", "on-device"])
    }
}
