import XCTest
@testable import PulseFeed

/// Idea ②: source monogram chips replace "Also in …". Shipped feeds use an override table; unknown
/// feeds get initials; collisions inside one list are resolved deterministically.
final class MonogramTests: XCTestCase {
    func testOverridesForShippedFeeds() {
        XCTAssertEqual(Monogram.make("BBC Sport F1"), "BBC")
        XCTAssertEqual(Monogram.make("Hacker News (50+ points)"), "HN")
        XCTAssertEqual(Monogram.make("Motorsport.com F1"), "MS")
        XCTAssertEqual(Monogram.make("The Race F1"), "TR")
        XCTAssertEqual(Monogram.make("ESPN"), "ESPN")
        XCTAssertEqual(Monogram.make("CoinDesk"), "CD")
    }
    func testInitialsForUnknownMultiWordTitles() {
        XCTAssertEqual(Monogram.make("Bloody Elbow"), "BE")
        XCTAssertEqual(Monogram.make("Rest of World"), "ROW")
    }
    func testSingleWordUsesFirstTwoLetters() {
        XCTAssertEqual(Monogram.make("Sherdog"), "SH")
    }
    func testStripsParentheticalsDotComAndLeadingThe() {
        XCTAssertEqual(Monogram.make("The Verge (tech)"), "VE")
        XCTAssertEqual(Monogram.make("example.com news"), "EN")
    }
    func testAssignResolvesCollisionsDeterministically() {
        let m = Monogram.assign(["Tech Report", "Tom Ryan"])   // both would be TR
        XCTAssertEqual(m["Tech Report"], "TR")
        XCTAssertEqual(m["Tom Ryan"], "RYA")                  // first three letters of its longest word
    }
}
