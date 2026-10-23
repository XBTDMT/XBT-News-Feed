import XCTest
@testable import PulseFeed

/// FeedKit's RFC 822 parser cannot decode British Summer Time and a few other named zones, so a
/// feed like DJ Mag's fails every summer. Named zones become numeric offsets before parsing.
final class FeedDateNormalizationTests: XCTestCase {
    func testNamedZonesBecomeNumericOffsets() {
        let xml = "<pubDate>Mon, 07 Sep 2026 13:49:57 BST</pubDate><pubDate>Mon, 07 Sep 2026 14:49:57 CEST</pubDate>"
        let fixed = FeedDateNormalization.numericTimezones(in: xml)
        XCTAssertEqual(fixed, "<pubDate>Mon, 07 Sep 2026 13:49:57 +0100</pubDate><pubDate>Mon, 07 Sep 2026 14:49:57 +0200</pubDate>")
    }
    func testKnownZonesAndOffsetsAreLeftAlone() {
        let xml = "<pubDate>Mon, 07 Sep 2026 13:49:57 GMT</pubDate><pubDate>Mon, 07 Sep 2026 13:49:57 +0000</pubDate><updated>2026-09-07T13:49:57Z</updated>"
        XCTAssertEqual(FeedDateNormalization.numericTimezones(in: xml), xml)
    }
    func testOnlyDateFieldsAreTouched() {
        let xml = "<title>Best of BST festival</title><pubDate>Mon, 07 Sep 2026 13:49:57 BST</pubDate>"
        XCTAssertEqual(FeedDateNormalization.numericTimezones(in: xml), "<title>Best of BST festival</title><pubDate>Mon, 07 Sep 2026 13:49:57 +0100</pubDate>")
    }
}
