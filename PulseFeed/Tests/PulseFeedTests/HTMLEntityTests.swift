import XCTest
@testable import PulseFeed

/// Some feeds double-encode headlines ("AT&#038;T", "&#8216;The Hangman&#8217;"); titles are decoded at
/// ingestion and existing rows are repaired once at launch.
final class HTMLEntityTests: XCTestCase {
    func testNumericEntitiesDecode() {
        XCTAssertEqual("Morning Report &#124; Eddie".htmlEntitiesDecoded, "Morning Report | Eddie")
        XCTAssertEqual("&#8216;The Hangman&#8217;".htmlEntitiesDecoded, "\u{2018}The Hangman\u{2019}")
        XCTAssertEqual("AT&#038;T".htmlEntitiesDecoded, "AT&T")
    }
    func testNamedEntitiesDecode() {
        XCTAssertEqual("Rock &amp; Roll".htmlEntitiesDecoded, "Rock & Roll")
        XCTAssertEqual("&quot;quoted&quot;".htmlEntitiesDecoded, "\"quoted\"")
    }
    func testPlainTextIsUntouched() {
        XCTAssertEqual("No entities here, 5 > 3".htmlEntitiesDecoded, "No entities here, 5 > 3")
    }
}
