import XCTest
@testable import PulseFeed

/// Hacker News: only fetch story items we have not already stored.
final class HNSelectionTests: XCTestCase {

    func testKnownStoriesAreSkippedAndOrderIsPreserved() {
        let picked = JSONFetcher.hnIDsToFetch(topIDs: [10, 11, 12, 13], knownUniqueIDs: ["11", "13"], limit: 30)
        XCTAssertEqual(picked, [10, 12])
    }

    func testLimitAppliesToTheTopListBeforeFiltering() {
        let top = Array(1...40)
        XCTAssertEqual(JSONFetcher.hnIDsToFetch(topIDs: top, knownUniqueIDs: [], limit: 30), Array(1...30))
        XCTAssertEqual(JSONFetcher.hnIDsToFetch(topIDs: top, knownUniqueIDs: ["1"], limit: 30), Array(2...30))
    }

    func testNothingNewYieldsEmptyList() {
        XCTAssertEqual(JSONFetcher.hnIDsToFetch(topIDs: [1, 2], knownUniqueIDs: ["1", "2"], limit: 30), [])
    }
}
