import XCTest
@testable import PulseFeed

/// Settings › Sources › Add source: what a person types becomes a list of URLs to try, an HTML page
/// yields its advertised feeds, and a response is or is not a feed. All pure — the network lives in
/// `FeedDiscovery.resolve`, which is not exercised here.
final class FeedDiscoveryTests: XCTestCase {

    // MARK: - Normalisation

    func testBareDomainGetsHTTPS() {
        XCTAssertEqual(FeedDiscovery.normalize("example.com")?.absoluteString, "https://example.com")
        XCTAssertEqual(FeedDiscovery.normalize("www.example.com/news")?.absoluteString, "https://www.example.com/news")
    }

    func testTrimsWhitespaceAndKeepsAnExplicitScheme() {
        XCTAssertEqual(FeedDiscovery.normalize("  http://example.com/news \n")?.absoluteString, "http://example.com/news")
        XCTAssertEqual(FeedDiscovery.normalize("HTTPS://Example.com/feed")?.absoluteString, "HTTPS://Example.com/feed")
    }

    func testFeedSchemeBecomesHTTPS() {
        XCTAssertEqual(FeedDiscovery.normalize("feed://example.com/rss")?.absoluteString, "https://example.com/rss")
        XCTAssertEqual(FeedDiscovery.normalize("feed:https://example.com/rss")?.absoluteString, "https://example.com/rss")
    }

    func testNonsenseIsNotAURL() {
        XCTAssertNil(FeedDiscovery.normalize(""))
        XCTAssertNil(FeedDiscovery.normalize("   "))
        XCTAssertNil(FeedDiscovery.normalize("not a url"))
        XCTAssertNil(FeedDiscovery.normalize("mailto:someone@example.com"))
        XCTAssertNil(FeedDiscovery.normalize("https://"))
    }

    // MARK: - Candidate paths

    func testCandidatesForASiteRootAreTheRootThenTheCommonFeedPaths() {
        let got = FeedDiscovery.candidates(for: "example.com").map(\.absoluteString)
        XCTAssertEqual(got, [
            "https://example.com",
            "https://example.com/feed",
            "https://example.com/feed/",
            "https://example.com/rss",
            "https://example.com/rss.xml",
            "https://example.com/feed.xml",
            "https://example.com/atom.xml",
            "https://example.com/index.xml",
            "https://example.com/?feed=rss2",
        ])
    }

    func testCandidatesForASubdirectoryPageTryThatDirectoryBeforeTheRoot() {
        let got = FeedDiscovery.candidates(for: "https://example.com/blog/").map(\.absoluteString)
        XCTAssertEqual(got.first, "https://example.com/blog/")
        XCTAssertEqual(got[1], "https://example.com/blog/feed")
        XCTAssertTrue(got.contains("https://example.com/blog/?feed=rss2"))
        XCTAssertTrue(got.contains("https://example.com/feed"))
        XCTAssertTrue(got.contains("https://example.com/?feed=rss2"))
        XCTAssertLessThan(got.firstIndex(of: "https://example.com/blog/rss.xml")!, got.firstIndex(of: "https://example.com/rss.xml")!)
        XCTAssertEqual(got.count, Set(got).count, "no duplicates")
    }

    func testCandidatesForAPostPageUseItsDirectory() {
        let got = FeedDiscovery.candidates(for: "https://example.com/blog/2026/hello-world").map(\.absoluteString)
        XCTAssertEqual(got.first, "https://example.com/blog/2026/hello-world")
        XCTAssertEqual(got[1], "https://example.com/blog/2026/feed")
    }

    func testCandidatesKeepAPortAndDropAFragment() {
        let got = FeedDiscovery.candidates(for: "http://localhost:8080/#top").map(\.absoluteString)
        XCTAssertEqual(got.first, "http://localhost:8080/")
        XCTAssertEqual(got[1], "http://localhost:8080/feed")
    }

    func testInvalidInputHasNoCandidates() {
        XCTAssertEqual(FeedDiscovery.candidates(for: ""), [])
        XCTAssertEqual(FeedDiscovery.candidates(for: "not a url"), [])
    }

    // MARK: - <link rel="alternate">

    func testFeedLinksAreReadInOrderWithRelativeHrefsResolved() {
        let html = """
            <!doctype html><html><head>
            <link rel="stylesheet" href="/site.css">
            <link rel="alternate" type="application/rss+xml" title="RSS" href="/feed">
            <link rel="alternate" type="application/atom+xml" href="https://feeds.example.net/atom.xml">
            <link rel="alternate" type="application/feed+json" href="feed.json">
            <link rel="alternate" type="text/html" hreflang="fr" href="/fr/">
            <link rel="alternate" type="application/rss+xml" href="/feed">
            </head><body></body></html>
            """
        let got = FeedDiscovery.feedLinks(inHTML: html, base: URL(string: "https://example.com/blog/post")!).map(\.absoluteString)
        XCTAssertEqual(got, [
            "https://example.com/feed",
            "https://feeds.example.net/atom.xml",
            "https://example.com/blog/feed.json",
        ])
    }

    func testFeedLinksAcceptMixedCaseAndMultiValuedRel() {
        let html = """
            <head>
            <LINK REL="Alternate" TYPE="Application/RSS+XML" HREF="/a.xml">
            <link rel="alternate feed" type="application/atom+xml" href="/b.xml">
            </head>
            """
        let got = FeedDiscovery.feedLinks(inHTML: html, base: URL(string: "https://example.com")!).map(\.absoluteString)
        XCTAssertEqual(got, ["https://example.com/a.xml", "https://example.com/b.xml"])
    }

    func testFeedLinksWithoutABaseDropRelativeHrefs() {
        let html = "<link rel=\"alternate\" type=\"application/rss+xml\" href=\"/feed\"><link rel=\"alternate\" type=\"application/rss+xml\" href=\"https://example.com/rss\">"
        XCTAssertEqual(FeedDiscovery.feedLinks(inHTML: html, base: nil).map(\.absoluteString), ["https://example.com/rss"])
        XCTAssertEqual(FeedDiscovery.feedLinks(inHTML: "<p>no links</p>", base: nil), [])
        XCTAssertEqual(FeedDiscovery.feedLinks(inHTML: "", base: nil), [])
    }

    // MARK: - looksLikeFeed

    private func data(_ s: String) -> Data { Data(s.utf8) }

    func testRSSLooksLikeAFeedEvenBehindDeclarationsAndAStylesheet() {
        XCTAssertTrue(FeedDiscovery.looksLikeFeed(data("<rss version=\"2.0\"><channel></channel></rss>")))
        XCTAssertTrue(FeedDiscovery.looksLikeFeed(data("\u{FEFF}<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<?xml-stylesheet type=\"text/xsl\" href=\"/rss.xsl\"?>\n<!-- generator -->\n<rss version=\"2.0\">")))
    }

    func testAtomAndRDFLookLikeFeeds() {
        XCTAssertTrue(FeedDiscovery.looksLikeFeed(data("<?xml version=\"1.0\"?>\n  <feed xmlns=\"http://www.w3.org/2005/Atom\">")))
        XCTAssertTrue(FeedDiscovery.looksLikeFeed(data("<?xml version=\"1.0\"?><rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\">")))
    }

    func testJSONFeedLooksLikeAFeedOnlyWithItems() {
        XCTAssertTrue(FeedDiscovery.looksLikeFeed(data("{\"version\":\"https://jsonfeed.org/version/1.1\",\"title\":\"t\",\"items\":[]}")))
        XCTAssertTrue(FeedDiscovery.looksLikeFeed(data("  \n{ \"items\" : [ {\"id\":\"1\"} ] }")))
        XCTAssertFalse(FeedDiscovery.looksLikeFeed(data("{\"title\":\"just json\"}")))
        XCTAssertFalse(FeedDiscovery.looksLikeFeed(data("[1,2,3]")))
    }

    func testHTMLAndJunkAreNotFeeds() {
        XCTAssertFalse(FeedDiscovery.looksLikeFeed(data("<!doctype html><html><head><title>x</title></head></html>")))
        XCTAssertFalse(FeedDiscovery.looksLikeFeed(data("<html><body><p>feed</p></body></html>")))
        XCTAssertFalse(FeedDiscovery.looksLikeFeed(data("Hello, world")))
        XCTAssertFalse(FeedDiscovery.looksLikeFeed(Data()))
        XCTAssertFalse(FeedDiscovery.looksLikeFeed(Data([0x89, 0x50, 0x4E, 0x47])))
    }

    func testHTMLIsRecognised() {
        XCTAssertTrue(FeedDiscovery.looksLikeHTML(data("<!DOCTYPE html><html lang=en>")))
        XCTAssertTrue(FeedDiscovery.looksLikeHTML(data("\n<html><head>")))
        XCTAssertTrue(FeedDiscovery.looksLikeHTML(data("<head><link rel=alternate></head>")))
        XCTAssertFalse(FeedDiscovery.looksLikeHTML(data("<rss version=\"2.0\">")))
        XCTAssertFalse(FeedDiscovery.looksLikeHTML(data("{\"items\":[]}")))
    }

    // MARK: - Parsing (FeedKit, no network)

    private let rss = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0"><channel><title> AT&amp;T News </title><link>https://example.com</link><description>d</description>
        <item><title>One</title><link>https://example.com/1</link><guid>1</guid></item>
        <item><title>Two</title><link>https://example.com/2</link><guid>2</guid></item>
        </channel></rss>
        """
    private let atom = """
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom"><title>Example Atom</title><id>urn:x</id><updated>2026-01-01T00:00:00Z</updated>
        <entry><title>A</title><id>urn:a</id><updated>2026-01-01T00:00:00Z</updated><link href="https://example.com/a"/></entry>
        </feed>
        """
    private let json = """
        {"version":"https://jsonfeed.org/version/1.1","title":"Example JSON","items":[{"id":"1","url":"https://example.com/1","title":"x"},{"id":"2"},{"id":"3"}]}
        """

    func testParseRSSGivesDecodedTitleAndItemCount() {
        let url = URL(string: "https://example.com/feed")!
        let feed = FeedDiscovery.parse(data(rss), url: url)
        XCTAssertEqual(feed, DiscoveredFeed(title: "AT&T News", url: url, itemCount: 2, format: .rss))
    }

    func testParseAtomAndJSON() {
        let a = FeedDiscovery.parse(data(atom), url: URL(string: "https://example.com/atom.xml")!)
        XCTAssertEqual(a?.title, "Example Atom")
        XCTAssertEqual(a?.itemCount, 1)
        XCTAssertEqual(a?.format, .atom)
        let j = FeedDiscovery.parse(data(json), url: URL(string: "https://example.com/feed.json")!)
        XCTAssertEqual(j?.title, "Example JSON")
        XCTAssertEqual(j?.itemCount, 3)
        XCTAssertEqual(j?.format, .json)
    }

    func testParseSurvivesAStylesheetInstructionAndFallsBackToTheHostForATitle() {
        let withPI = rss.replacingOccurrences(of: "<rss ", with: "<?xml-stylesheet type=\"text/xsl\" href=\"/x.xsl\"?>\n<rss ")
            .replacingOccurrences(of: "<title> AT&amp;T News </title>", with: "")
        let feed = FeedDiscovery.parse(data(withPI), url: URL(string: "https://news.example.com/feed")!)
        XCTAssertEqual(feed?.title, "news.example.com")
        XCTAssertEqual(feed?.itemCount, 2)
    }

    func testParseRefusesHTMLAndRDF() {
        XCTAssertNil(FeedDiscovery.parse(data("<!doctype html><html></html>"), url: URL(string: "https://example.com")!))
        XCTAssertNil(FeedDiscovery.parse(data("<?xml version=\"1.0\"?><rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\"></rdf:RDF>"), url: URL(string: "https://example.com/rdf")!))
    }

    // MARK: - Errors read well in the sheet

    func testErrorsHaveHumanDescriptions() {
        XCTAssertEqual(DiscoveryError.invalidInput.errorDescription, "Enter a web address or a site name, like theverge.com.")
        XCTAssertEqual(DiscoveryError.noFeedFound.errorDescription, "No feed found on that page. Try pasting the feed's own address.")
        XCTAssertEqual(DiscoveryError.notAFeed.errorDescription, "That address is not a feed or a web page.")
        XCTAssertEqual(DiscoveryError.unreachable("HTTP 404").errorDescription, "Could not reach that address (HTTP 404).")
        XCTAssertEqual(DiscoveryError.parseFailed(URL(string: "https://x.com/rss")!).errorDescription, "Found a feed at https://x.com/rss but it could not be parsed.")
    }
}
