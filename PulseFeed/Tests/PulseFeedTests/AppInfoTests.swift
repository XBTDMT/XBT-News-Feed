import XCTest
@testable import PulseFeed

final class AppInfoTests: XCTestCase {
    func testDisplayNamePrefersDisplayKey() {
        let info: [String: Any] = ["CFBundleDisplayName": "A", "CFBundleName": "B"]
        XCTAssertEqual(AppInfo.displayName(info), "A")
    }

    func testFallsBackToBundleNameThenNewsFeed() {
        XCTAssertEqual(AppInfo.displayName(["CFBundleName": "B"]), "B")
        XCTAssertEqual(AppInfo.displayName(nil), "News Feed")
        XCTAssertEqual(AppInfo.displayName([:]), "News Feed")
    }

    func testInstallURL() {
        XCTAssertEqual(AppInfo.installURL(displayName: "News Feed").path, "/Applications/News Feed.app")
    }

    func testShortNamePrefersItsKey() {
        let info: [String: Any] = ["PFShortName": "S", "CFBundleDisplayName": "A"]
        XCTAssertEqual(AppInfo.shortName(info), "S")
    }

    func testShortNameFallsBackToDisplayName() {
        XCTAssertEqual(AppInfo.shortName(["CFBundleDisplayName": "A"]), "A")
        XCTAssertEqual(AppInfo.shortName(nil), "News Feed")
    }
}
