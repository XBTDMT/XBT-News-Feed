import XCTest
@testable import PulseFeed

/// `make check-catalog`'s pure half: a passing check stamps its source, a failure is listed, an
/// offline-shaped failure neither stamps nor counts, and sources that are not feeds are left alone.
final class CatalogCheckTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_670_400) // 2026-10-22 12:00 UTC

    private func catalog() -> Catalog {
        let t = CatalogTopic(id: "tech", label: "Tech", category: "tech", group: .techScience, aliases: [], follows: [], regions: ["global"])
        func s(_ u: String, _ type: String = "rss") -> CatalogSource {
            CatalogSource(url: u, title: u, topic: "tech", region: "global", type: type, pollInterval: 900, checkedAt: "2026-01-01 00:00:00", itemCount: 9)
        }
        return Catalog(version: 1, topics: [t], sources: [s("https://a/feed"), s("https://b/feed"), s("https://c/feed"), s("https://api/x", "json_api")])
    }

    func testPassStampsDateAndCount() {
        let (c, failed, _) = CatalogChecker.applying([CatalogCheck(url: "https://a/feed", ok: true, itemCount: 30, error: nil, transient: false)], to: catalog(), now: now)
        XCTAssertEqual(c.sources[0].checkedAt, "2026-10-22 12:00:00")
        XCTAssertEqual(c.sources[0].itemCount, 30)
        XCTAssertTrue(failed.isEmpty)
    }

    /// A source that dies loses its stamp, so the three-checked-sources test notices (audit 2026-10-22, finding 8).
    func testFailureIsListedAndClearsItsStamp() {
        let check = CatalogCheck(url: "https://b/feed", ok: false, itemCount: 0, error: "HTTP 404", transient: false)
        let (c, failed, offline) = CatalogChecker.applying([check], to: catalog(), now: now)
        XCTAssertEqual(failed, [check])
        XCTAssertTrue(offline.isEmpty)
        XCTAssertNil(c.sources[1].checkedAt)
    }

    func testAFeedWhoseNewestStoryIsOldIsStale() {
        let day: TimeInterval = 86_400
        XCTAssertTrue(CatalogChecker.isStale(newest: now.addingTimeInterval(-61 * day), now: now))
        XCTAssertFalse(CatalogChecker.isStale(newest: now.addingTimeInterval(-59 * day), now: now))
        XCTAssertTrue(CatalogChecker.isStale(newest: nil, now: now), "no dated item at all is not a working source")
    }

    func testTransientFailureIsNotAFailure() {
        let check = CatalogCheck(url: "https://c/feed", ok: false, itemCount: 0, error: "timed out", transient: true)
        let (c, failed, offline) = CatalogChecker.applying([check], to: catalog(), now: now)
        XCTAssertTrue(failed.isEmpty)
        XCTAssertEqual(offline, [check])
        XCTAssertEqual(c.sources[2], catalog().sources[2])
    }

    func testOnlyFeedsAreChecked() {
        XCTAssertEqual(CatalogChecker.checkable(catalog().sources).map(\.url), ["https://a/feed", "https://b/feed", "https://c/feed"])
    }
}
