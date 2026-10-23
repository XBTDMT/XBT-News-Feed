import XCTest
@testable import PulseFeed

/// Pure scheduling math: failing feeds back off exponentially, and the next tick
/// is driven by the soonest due feed on AC, a fixed 5 minutes on battery, and
/// 30 minutes when the battery is critical.
final class PollSchedulingTests: XCTestCase {

    // MARK: effectiveInterval

    func testHealthyFeedKeepsItsBaseInterval() {
        XCTAssertEqual(PollScheduling.effectiveInterval(base: 300, consecutiveErrors: 0), 300)
    }

    func testEachConsecutiveErrorDoublesTheInterval() {
        XCTAssertEqual(PollScheduling.effectiveInterval(base: 300, consecutiveErrors: 1), 600)
        XCTAssertEqual(PollScheduling.effectiveInterval(base: 300, consecutiveErrors: 3), 2400)
        XCTAssertEqual(PollScheduling.effectiveInterval(base: 300, consecutiveErrors: 5), 9600)
    }

    func testBackoffExponentIsCappedAtFive() {
        XCTAssertEqual(
            PollScheduling.effectiveInterval(base: 300, consecutiveErrors: 40),
            PollScheduling.effectiveInterval(base: 300, consecutiveErrors: 5))
    }

    func testBackedOffIntervalNeverExceedsSixHours() {
        XCTAssertEqual(PollScheduling.effectiveInterval(base: 3600, consecutiveErrors: 5), 6 * 3600)
    }

    // MARK: nextTickDelay

    func testACFollowsSoonestDueFeed() {
        XCTAssertEqual(PollScheduling.nextTickDelay(tier: .ac, soonestDueIn: 120), 120)
    }

    func testACHasSixtySecondFloorForOverdueFeeds() {
        XCTAssertEqual(PollScheduling.nextTickDelay(tier: .ac, soonestDueIn: 0), 60)
        XCTAssertEqual(PollScheduling.nextTickDelay(tier: .ac, soonestDueIn: -500), 60)
        XCTAssertEqual(PollScheduling.nextTickDelay(tier: .ac, soonestDueIn: 10), 60)
    }

    func testACHasOneHourCeilingAndFiveMinuteDefaultWhenNothingIsDue() {
        XCTAssertEqual(PollScheduling.nextTickDelay(tier: .ac, soonestDueIn: 99_999), 3600)
        XCTAssertEqual(PollScheduling.nextTickDelay(tier: .ac, soonestDueIn: nil), 300)
    }

    func testBatteryIsFixedFiveMinutesRegardlessOfDueFeeds() {
        XCTAssertEqual(PollScheduling.nextTickDelay(tier: .battery, soonestDueIn: 10), 300)
        XCTAssertEqual(PollScheduling.nextTickDelay(tier: .battery, soonestDueIn: nil), 300)
    }

    func testCriticalIsFixedThirtyMinutes() {
        XCTAssertEqual(PollScheduling.nextTickDelay(tier: .critical, soonestDueIn: 10), 1800)
    }
}
