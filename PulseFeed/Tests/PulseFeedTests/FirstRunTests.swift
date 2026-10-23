import XCTest
@testable import PulseFeed

/// The "Notifications are working" banner is a first-run greeting, not a launch ritual.
final class FirstRunTests: XCTestCase {
    func testWelcomeNotificationGoesOnceOnly() {
        let d = UserDefaults(suiteName: "FirstRunTests-\(UUID().uuidString)")!
        XCTAssertTrue(FirstRun.shouldSendWelcome(d))
        FirstRun.recordWelcomeSent(d)
        XCTAssertFalse(FirstRun.shouldSendWelcome(d))
    }
}
