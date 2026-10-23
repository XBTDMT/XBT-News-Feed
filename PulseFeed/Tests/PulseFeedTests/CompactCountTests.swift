import XCTest
@testable import PulseFeed

/// Counts in tiles and pills must fit: "984", "8.8k", "16k", "1.2M".
final class CompactCountTests: XCTestCase {
    func testUnderAThousandIsPlain() {
        XCTAssertEqual(CompactCount.format(0), "0")
        XCTAssertEqual(CompactCount.format(984), "984")
    }
    func testThousandsGetOneDecimalBelowTenThousand() {
        XCTAssertEqual(CompactCount.format(1_007), "1k")
        XCTAssertEqual(CompactCount.format(8_843), "8.8k")
        XCTAssertEqual(CompactCount.format(1_641), "1.6k")
    }
    func testTenThousandAndUpDropTheDecimal() {
        XCTAssertEqual(CompactCount.format(16_386), "16k")
        XCTAssertEqual(CompactCount.format(999_499), "999k")
    }
    func testMillions() {
        XCTAssertEqual(CompactCount.format(1_200_000), "1.2M")
    }
}
