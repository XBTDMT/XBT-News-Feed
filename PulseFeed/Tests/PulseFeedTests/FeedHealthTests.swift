import XCTest
@testable import PulseFeed

/// Feed health separates "cannot look" (fetch errors) from "nothing there"
/// (fetching fine but no article in two weeks), which HTTP status cannot tell apart.
final class FeedHealthTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)  // 2027-01-15 08:00:00 UTC

    private func feed(errors: Int = 0, lastArticleAt: String?, createdAt: String? = nil) -> Feed {
        Feed(
            id: "f", title: "F", url: "https://f", homePageURL: nil, category: "tech", type: "rss",
            pollInterval: 300, isEnabled: true, etag: nil, lastModified: nil, contentHash: nil,
            faviconURL: nil, faviconData: nil, lastFetchedAt: nil, lastFetchError: nil,
            consecutiveErrors: errors, conditionalGetResetAt: nil, lastArticleAt: lastArticleAt,
            createdAt: createdAt, updatedAt: nil)
    }

    func testConsecutiveErrorsMeanFailing() {
        XCTAssertEqual(feed(errors: 3, lastArticleAt: now.addingTimeInterval(-3600).sqliteString).health(now: now), .failing(errors: 3))
    }

    func testRecentArticleMeansOK() {
        XCTAssertEqual(feed(lastArticleAt: now.addingTimeInterval(-86400).sqliteString).health(now: now), .ok)
    }

    func testTwoWeeksWithoutArticlesMeansStale() {
        XCTAssertEqual(feed(lastArticleAt: now.addingTimeInterval(-20 * 86400).sqliteString).health(now: now), .stale(daysSinceArticle: 20))
    }

    func testNeverHadAnArticleFallsBackToFeedAge() {
        XCTAssertEqual(feed(lastArticleAt: nil, createdAt: now.addingTimeInterval(-30 * 86400).sqliteString).health(now: now), .stale(daysSinceArticle: 30))
        XCTAssertEqual(feed(lastArticleAt: nil, createdAt: now.addingTimeInterval(-2 * 86400).sqliteString).health(now: now), .ok)
        XCTAssertEqual(feed(lastArticleAt: nil, createdAt: nil).health(now: now), .ok)
    }
}
