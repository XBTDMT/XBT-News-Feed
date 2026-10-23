import XCTest
@testable import PulseFeed

/// A feed's id must be the same on every launch: String.hashValue is seeded per process.
final class FeedIDTests: XCTestCase {
    func testIDIsStableAndDerivedFromTheURL() {
        let a = Feed.makeID(url: "https://www.theverge.com/rss/index.xml")
        XCTAssertEqual(a, Feed.makeID(url: "https://www.theverge.com/rss/index.xml"))
        XCTAssertTrue(a.hasPrefix("feed-"))
        XCTAssertEqual(a.count, "feed-".count + 16)
        XCTAssertNotEqual(a, Feed.makeID(url: "https://www.theverge.com/rss/index.xml/"))
    }
}
