import XCTest
@testable import PulseFeed

/// Settings › General › Appearance: System / Light / Dark. The renders are light, so Light is the default.
final class AppAppearanceTests: XCTestCase {
    func testDefaultIsLight() {
        XCTAssertEqual(AppAppearance.resolve(nil), .light)
        XCTAssertEqual(AppAppearance.resolve(""), .light)
        XCTAssertEqual(AppAppearance.resolve("sepia"), .light)
    }
    func testStoredValuesResolve() {
        XCTAssertEqual(AppAppearance.resolve("dark"), .dark)
        XCTAssertEqual(AppAppearance.resolve("system"), .system)
        XCTAssertEqual(AppAppearance.resolve("Light"), .light)
    }
}
