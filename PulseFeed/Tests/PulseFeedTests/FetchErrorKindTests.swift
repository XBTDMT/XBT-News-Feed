import XCTest
@testable import PulseFeed

/// A Mac that is offline is not a broken feed: those fetch errors must not count against the source.
final class FetchErrorKindTests: XCTestCase {
    func testOfflineErrorsAreTransient() {
        XCTAssertEqual(FetchErrorKind.classify(URLError(.notConnectedToInternet)), .transient)
        XCTAssertEqual(FetchErrorKind.classify(URLError(.networkConnectionLost)), .transient)
        XCTAssertEqual(FetchErrorKind.classify(URLError(.dnsLookupFailed)), .transient)
        XCTAssertEqual(FetchErrorKind.classify(URLError(.timedOut)), .transient)
    }
    func testServerAndParseErrorsCountAgainstTheFeed() {
        XCTAssertEqual(FetchErrorKind.classify(URLError(.badServerResponse)), .feed)
        XCTAssertEqual(FetchErrorKind.classify(URLError(.fileDoesNotExist)), .feed)
        XCTAssertEqual(FetchErrorKind.classify(NSError(domain: "FeedKit", code: 1)), .feed)
    }
}
