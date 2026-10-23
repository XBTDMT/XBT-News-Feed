import XCTest
@testable import PulseFeed

/// Most feeds carry their picture in media:content / media:thumbnail or as the first <img> in the
/// body, not in an enclosure. The fetcher takes the first that exists.
final class ImageExtractionTests: XCTestCase {
    func testFirstImageInHTMLBody() {
        let html = "<p>Text</p><figure><img src=\"https://cdn.example.com/a.jpg\" alt=\"\"></figure><img src=\"https://cdn.example.com/b.jpg\">"
        XCTAssertEqual(ImageExtraction.firstImageURL(inHTML: html), "https://cdn.example.com/a.jpg")
    }
    func testIgnoresTrackingPixelsAndDataURIs() {
        let html = "<img src=\"https://t.example.com/pixel.gif\" width=\"1\" height=\"1\"><img src=\"data:image/png;base64,AAAA\"><img src=\"https://cdn.example.com/real.png\">"
        XCTAssertEqual(ImageExtraction.firstImageURL(inHTML: html), "https://cdn.example.com/real.png")
    }
    func testNoImageIsNil() {
        XCTAssertNil(ImageExtraction.firstImageURL(inHTML: "<p>plain</p>"))
        XCTAssertNil(ImageExtraction.firstImageURL(inHTML: ""))
    }
    func testPicksTheFirstNonEmptyCandidate() {
        XCTAssertEqual(ImageExtraction.pick([nil, "", "https://x/1.jpg", "https://x/2.jpg"]), "https://x/1.jpg")
        XCTAssertNil(ImageExtraction.pick([nil, ""]))
    }

    // Pages without a feed image usually still carry a social card; the backfill reads it on AC.
    func testSocialImagePrefersOpenGraph() {
        let html = "<html><head><meta property=\"og:title\" content=\"x\"><meta property=\"og:image\" content=\"https://cdn.example.com/og.jpg\"><meta name=\"twitter:image\" content=\"https://cdn.example.com/tw.jpg\"></head><body></body></html>"
        XCTAssertEqual(ImageExtraction.socialImageURL(inHTML: html, base: nil), "https://cdn.example.com/og.jpg")
    }
    func testSocialImageFallsBackToTwitterCard() {
        let html = "<head><meta name=\"twitter:image\" content=\"https://cdn.example.com/tw.jpg\"></head>"
        XCTAssertEqual(ImageExtraction.socialImageURL(inHTML: html, base: nil), "https://cdn.example.com/tw.jpg")
    }
    func testSocialImageResolvesRelativeAgainstThePage() {
        let html = "<head><meta property=\"og:image\" content=\"/img/a.jpg\"></head>"
        XCTAssertEqual(ImageExtraction.socialImageURL(inHTML: html, base: URL(string: "https://news.example.com/story/1")), "https://news.example.com/img/a.jpg")
        XCTAssertNil(ImageExtraction.socialImageURL(inHTML: html, base: nil))
        XCTAssertNil(ImageExtraction.socialImageURL(inHTML: "<head><title>t</title></head>", base: nil))
    }
}
