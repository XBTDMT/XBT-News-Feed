import XCTest
@testable import PulseFeed

/// `make showcase` draws the app's surfaces from a fictional fixture. It may only ever run as
/// build/Showcase.app (its own bundle id, so its own defaults domain and no clash with the running
/// app's single-instance guard), and like every tool run it opens a throwaway database.
final class ShowcaseGateTests: XCTestCase {
    func testOnlyTheShowcaseBundleRenders() {
        XCTAssertTrue(ShowcaseGate.allowed(bundleID: "com.pulsefeed.showcase"))
        XCTAssertFalse(ShowcaseGate.allowed(bundleID: "com.pulsefeed.app"))
        XCTAssertFalse(ShowcaseGate.allowed(bundleID: nil))
    }

    func testAShowcaseRunOpensAThrowawayDatabase() {
        let path = AppDatabase.launchPath(environment: [ShowcaseGate.environmentKey: "build/showcase"])
        XCTAssertNotEqual(path, AppDatabase.defaultPath)
        XCTAssertTrue(path.hasPrefix(FileManager.default.temporaryDirectory.path))
    }

    func testTheOutputFolderComesFromTheHook() {
        XCTAssertNil(ShowcaseGate.outputDirectory(environment: [:]))
        XCTAssertNil(ShowcaseGate.outputDirectory(environment: [ShowcaseGate.environmentKey: ""]))
        XCTAssertEqual(ShowcaseGate.outputDirectory(environment: [ShowcaseGate.environmentKey: "/tmp/shots"])?.path, "/tmp/shots")
    }
}
