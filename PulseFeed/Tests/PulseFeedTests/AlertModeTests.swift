import XCTest
@testable import PulseFeed

final class AlertModeTests: XCTestCase {
    private var suite: String!
    private var d: UserDefaults!

    override func setUp() {
        suite = "AlertModeTests-\(UUID().uuidString)"
        d = UserDefaults(suiteName: suite)
    }

    override func tearDown() { d.removePersistentDomain(forName: suite) }

    func testAbsentMeansTodaysBehaviour() {
        XCTAssertEqual(AlertMode.stored(d), .breakingAndRecap)
        XCTAssertTrue(AlertMode.breakingAndRecap.allowsUrgent)
        XCTAssertTrue(AlertMode.breakingAndRecap.allowsRecap)
    }

    func testRecapOnlyHoldsUrgentForTheRecap() {
        d.set("recap", forKey: AlertMode.defaultsKey)
        XCTAssertEqual(AlertMode.stored(d), .recapOnly)
        XCTAssertFalse(AlertMode.recapOnly.allowsUrgent)
        XCTAssertTrue(AlertMode.recapOnly.allowsRecap)
    }

    func testQuietSendsNothing() {
        d.set("quiet", forKey: AlertMode.defaultsKey)
        XCTAssertEqual(AlertMode.stored(d), .quiet)
        XCTAssertFalse(AlertMode.quiet.allowsUrgent)
        XCTAssertFalse(AlertMode.quiet.allowsRecap)
    }

    func testUnknownValueFallsBack() {
        d.set("loud", forKey: AlertMode.defaultsKey)
        XCTAssertEqual(AlertMode.stored(d), .breakingAndRecap)
    }

    func testLabels() {
        XCTAssertEqual(AlertMode.allCases.map(\.label), ["Breaking + recap", "Recap only", "Quiet"])
    }

    /// Quiet's promise is "no banners": a price alert someone set waits too.
    func testQuietHoldsPriceAlertsToo() {
        XCTAssertTrue(AlertMode.breakingAndRecap.allowsPriceAlerts)
        XCTAssertTrue(AlertMode.recapOnly.allowsPriceAlerts)
        XCTAssertFalse(AlertMode.quiet.allowsPriceAlerts)
    }
}
