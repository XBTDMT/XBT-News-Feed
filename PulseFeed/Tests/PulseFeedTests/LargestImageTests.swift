import XCTest
@testable import PulseFeed

/// Feeds often list several renditions of the same picture; the hero cards need the largest,
/// not the first (The Guardian's first media:content is a 140 px thumbnail).
final class LargestImageTests: XCTestCase {
    func testPicksTheWidestRendition() {
        let picked = ImageExtraction.largest([
            (url: "https://i/140.jpg", width: 140),
            (url: "https://i/1000.jpg", width: 1000),
            (url: "https://i/460.jpg", width: 460),
        ])
        XCTAssertEqual(picked, "https://i/1000.jpg")
    }
    func testUnsizedRenditionsKeepFeedOrder() {
        XCTAssertEqual(ImageExtraction.largest([(url: "https://i/a.jpg", width: Int?.none), (url: "https://i/b.jpg", width: Int?.none)]), "https://i/a.jpg")
        XCTAssertEqual(ImageExtraction.largest([(url: "https://i/a.jpg", width: Int?.none), (url: "https://i/b.jpg", width: 300)]), "https://i/b.jpg")
        XCTAssertNil(ImageExtraction.largest([]))
        XCTAssertNil(ImageExtraction.largest([(url: String?.none, width: 900)]))
    }
}
