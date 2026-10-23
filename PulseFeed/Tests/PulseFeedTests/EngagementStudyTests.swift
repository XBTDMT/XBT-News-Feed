import XCTest
@testable import PulseFeed

/// The learning week ships switched off (spec D11); an install whose week already started keeps it.
final class EngagementStudyTests: XCTestCase {
    private var suite: String!
    private var d: UserDefaults!

    override func setUp() {
        suite = "EngagementStudyTests-\(UUID().uuidString)"
        d = UserDefaults(suiteName: suite)
    }

    override func tearDown() { d.removePersistentDomain(forName: suite) }

    func testAnInstallInUseKeepsItsStudyOn() {
        d.set(Date(timeIntervalSince1970: 1_788_739_200), forKey: EngagementStudy.startedKey)   // 2026-09-07
        XCTAssertTrue(EngagementStudy.isEnabled(d))
    }

    func testANewInstallIsOff() {
        XCTAssertFalse(EngagementStudy.isEnabled(d))
    }

    func testCheckingDoesNotStartTheClock() {
        _ = EngagementStudy.isEnabled(d)
        XCTAssertNil(d.object(forKey: EngagementStudy.startedKey))
    }

    func testTurningOnStartsTheClock() {
        let now = Date(timeIntervalSince1970: 1_792_670_400)
        EngagementStudy.setEnabled(true, d, now: now)
        XCTAssertTrue(EngagementStudy.isEnabled(d))
        XCTAssertEqual(d.object(forKey: EngagementStudy.startedKey) as? Date, now)
    }

    func testTurningOffKeepsTheClockButStopsIt() {
        let started = Date(timeIntervalSince1970: 1_788_739_200)
        d.set(started, forKey: EngagementStudy.startedKey)
        EngagementStudy.setEnabled(false, d, now: Date())
        XCTAssertFalse(EngagementStudy.isEnabled(d))
        EngagementStudy.setEnabled(true, d, now: Date())
        XCTAssertEqual(d.object(forKey: EngagementStudy.startedKey) as? Date, started, "turning back on keeps the week it had")
    }
}
