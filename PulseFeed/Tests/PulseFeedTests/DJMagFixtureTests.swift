import XCTest
import FeedKit
@testable import PulseFeed

/// DJ Mag's real markup (two items, bodies trimmed) fails FeedKit as published and parses once the
/// named zone is rewritten — the fetcher's retry path.
final class DJMagFixtureTests: XCTestCase {
    static let fixture = """
<?xml version="1.0" encoding="utf-8"?>
<rss xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:foaf="http://xmlns.com/foaf/0.1/" xmlns:og="http://ogp.me/ns#" xmlns:rdfs="http://www.w3.org/2000/01/rdf-schema#" xmlns:schema="http://schema.org/" xmlns:sioc="http://rdfs.org/sioc/ns#" xmlns:sioct="http://rdfs.org/sioc/types#" xmlns:skos="http://www.w3.org/2004/02/skos/core#" xmlns:xsd="http://www.w3.org/2001/XMLSchema#" version="2.0" xml:base="https://djmag.com/">
  <channel>
    <title>DJ Mag</title>
    <link>https://djmag.com/</link>
    <description/>
    <language>en</language>
    <pubDate>Mon, 07 Sep 2026 13:49:57 +0100</pubDate>

    <item>
  <title>Two people reported dead at Burning Man 2026</title>
  <link>https://djmag.com/news/two-people-reported-dead-burning-man-2026</link>
  <description>…</description>
  <pubDate>Mon, 07 Sep 2026 13:49:57 BST</pubDate>
                            <dc:creator>James Keith</dc:creator>
                            <guid isPermaLink="false">/news/two-people-reported-dead-burning-man-2026</guid>
                            </item>
<item>
  <title>Anyma issues statement after Istanbul show cancelled over “satanic” imagery claims</title>
  <link>https://djmag.com/news/anyma-issues-statement-after-istanbul-show-cancelled-over-satanic-imagery-claims</link>
  <description>…</description>
  <pubDate>Mon, 07 Sep 2026 12:46:56 BST</pubDate>
                            <dc:creator>James Keith</dc:creator>
                            <guid isPermaLink="false">/news/anyma-issues-statement-after-istanbul-show-cancelled-over-satanic-imagery-claims</guid>
                            </item>

  </channel>
</rss>

"""

    func testAsPublishedItFailsToParse() {
        XCTAssertThrowsError(try FeedKit.Feed(data: Data(Self.fixture.utf8)))
    }

    func testNormalisedItParsesWithDatedItems() throws {
        let fixed = FeedDateNormalization.numericTimezones(in: Self.fixture)
        XCTAssertFalse(fixed.contains(" BST<"))
        let feed = try FeedKit.Feed(data: Data(fixed.utf8))
        guard case .rss(let rss) = feed else { return XCTFail("not RSS") }
        let items = rss.channel?.items ?? []
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.allSatisfy { $0.pubDate != nil })
    }

    /// Settings › Add source and `make check-catalog` read it through the same retry chain as polling.
    func testAddSourceParserReadsItToo() {
        XCTAssertNotNil(FeedDiscovery.parse(Data(Self.fixture.utf8), url: URL(string: "https://djmag.com/feed")!))
    }
}
