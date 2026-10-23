import XCTest
@testable import PulseFeed

final class BuildFlavorTests: XCTestCase {
    func testFlavorMatchesCompileFlag() {
        XCTAssertTrue(BuildFlavor.isPublic)
    }
}
