import XCTest
@testable import PulseFeed

/// Idea ③: the popover footer reads tier, last poll, next poll and the tick's cost from values the
/// engine already computes. Missing parts are omitted, never rendered as placeholders.
final class StatusLineTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testFullLine() {
        let s = StatusLine.format(tier: .ac, now: now, lastTickAt: now - 120, nextTickAt: now + 180, requests: 18, bytes: 620_000)
        XCTAssertEqual(s, "AC · polled 2m ago · next in 3m · 18 requests, 0.6 MB")
    }
    func testMissingPartsAreOmitted() {
        XCTAssertEqual(StatusLine.format(tier: .battery, now: now, lastTickAt: nil, nextTickAt: nil, requests: nil, bytes: nil), "Battery")
        XCTAssertEqual(
            StatusLine.format(tier: .critical, now: now, lastTickAt: now - 30, nextTickAt: nil, requests: 3, bytes: nil),
            "Low battery · polled 30s ago · 3 requests")
    }
    func testOverdueNextTickReadsPollingNow() {
        XCTAssertEqual(StatusLine.format(tier: .ac, now: now, lastTickAt: nil, nextTickAt: now - 5, requests: nil, bytes: nil), "AC · polling now")
    }
    func testMegabytes() {
        XCTAssertEqual(StatusLine.megabytes(620_000), "0.6 MB")
        XCTAssertEqual(StatusLine.megabytes(12_400_000), "12 MB")
        XCTAssertEqual(StatusLine.megabytes(900), "0.0 MB")
    }
    func testRelative() {
        XCTAssertEqual(StatusLine.relative(45), "45s")
        XCTAssertEqual(StatusLine.relative(3_700), "1h")
        XCTAssertEqual(StatusLine.relative(90_000), "1d")
    }
}
