import XCTest
@testable import PulseFeed

/// Smoke tests for PulseFeed.
///
/// Targets `Article.makeID(feedID:uniqueID:)` — the deterministic SHA256 used to
/// key every fetched article (called from RSSFetcher and JSONFetcher across the
/// dedup pipeline). It is pure (CryptoKit + Foundation only, no DB / no UI), so
/// it is the smallest unit that proves the test surface compiles AND verifies a
/// real invariant the app relies on.
final class SmokeTests: XCTestCase {

    /// Same inputs must always produce the same ID (dedup correctness depends on this).
    func testMakeIDIsDeterministic() {
        let a = Article.makeID(feedID: "feed-1", uniqueID: "item-42")
        let b = Article.makeID(feedID: "feed-1", uniqueID: "item-42")
        XCTAssertEqual(a, b, "makeID must be stable for identical inputs")
    }

    /// Output is a lowercase hex SHA256 digest: exactly 64 hex characters.
    func testMakeIDIsLowercaseHexSHA256() {
        let id = Article.makeID(feedID: "feed-1", uniqueID: "item-42")
        XCTAssertEqual(id.count, 64, "SHA256 hex digest is 64 chars")
        XCTAssertTrue(
            id.allSatisfy { $0.isHexDigit && ($0.isNumber || $0.isLowercase) },
            "digest must be lowercase hex"
        )
    }

    /// Different inputs must produce different IDs — and the feedID/uniqueID split
    /// must matter, so two articles that merely share a colon-concatenation aren't
    /// collapsed ("a:b" vs "a" + ":b" are joined the same way, so guard the boundary).
    func testMakeIDDistinguishesInputs() {
        let base = Article.makeID(feedID: "feed-1", uniqueID: "item-42")
        XCTAssertNotEqual(base, Article.makeID(feedID: "feed-2", uniqueID: "item-42"))
        XCTAssertNotEqual(base, Article.makeID(feedID: "feed-1", uniqueID: "item-43"))
        // Known-answer: SHA256("feed-1:item-42"), captured with `printf 'feed-1:item-42' | shasum -a 256`.
        // If this ever changes, every stored articleID is orphaned on upgrade.
        XCTAssertEqual(
            base,
            "d3ba69b79160f435025c7e7ffacfda21ce081d65e38590bdcf4c258c16a85be8"
        )
    }
}
