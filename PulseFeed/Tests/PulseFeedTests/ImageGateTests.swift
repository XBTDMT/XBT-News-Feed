import XCTest
@testable import PulseFeed

/// Stream's safeguard from its sheet: hero + thumbnails on AC, hero only on battery, none on critical.
final class ImageGateTests: XCTestCase {
    func testPolicyByTier() {
        XCTAssertEqual(ImageGate.policy(for: .ac), .heroAndThumbnails)
        XCTAssertEqual(ImageGate.policy(for: .battery), .heroOnly)
        XCTAssertEqual(ImageGate.policy(for: .critical), .none)
    }
}
