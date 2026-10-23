import XCTest
@testable import PulseFeed

/// A tool run of the app binary (the catalog check, the icon export) must never open the live
/// database: opening it applies migrations, and on 2026-10-22 a `make check-catalog` run did exactly
/// that to the live store. Tool runs get a throwaway database; a normal launch gets the real one.
final class LaunchPathTests: XCTestCase {
    func testNormalLaunchUsesTheLiveDatabase() {
        XCTAssertEqual(AppDatabase.launchPath(environment: [:]), AppDatabase.defaultPath)
        XCTAssertEqual(AppDatabase.launchPath(environment: ["PULSEFEED_DESIGN": "deck"]), AppDatabase.defaultPath)
    }

    func testToolRunsUseAThrowawayDatabase() {
        for key in ["PULSEFEED_CHECK_CATALOG", "PULSEFEED_DEBUG_EXPORT_ICON", "PULSEFEED_DEBUG_INTERESTS"] {
            let path = AppDatabase.launchPath(environment: [key: "x"])
            XCTAssertNotEqual(path, AppDatabase.defaultPath, key)
            XCTAssertTrue(path.hasPrefix(FileManager.default.temporaryDirectory.path), key)
        }
    }

    func testAnEmptyHookValueIsANormalLaunch() {
        XCTAssertEqual(AppDatabase.launchPath(environment: ["PULSEFEED_CHECK_CATALOG": ""]), AppDatabase.defaultPath)
    }

    func testWelcomeDebugRunUsesAToolDatabase() {
        let path = AppDatabase.launchPath(environment: ["PULSEFEED_DEBUG_WELCOME": "1"])
        XCTAssertNotEqual(path, AppDatabase.defaultPath)
    }
}
