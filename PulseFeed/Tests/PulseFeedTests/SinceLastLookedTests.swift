import XCTest
@testable import PulseFeed

/// Idea ①: every list splits into "new since you last looked" and "seen"; the divider and the menu
/// bar count derive from the same pure partition.
final class SinceLastLookedTests: XCTestCase {
    struct Item { let name: String; let at: Date? }
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    func testSplitsNewFromSeenKeepingOrder() {
        let items = [Item(name: "a", at: t0 + 300), Item(name: "b", at: t0 + 60), Item(name: "c", at: t0 - 60)]
        let p = SinceLastLooked.partition(items, arrival: { $0.at }, lastLooked: t0)
        XCTAssertEqual(p.new.map(\.name), ["a", "b"])
        XCTAssertEqual(p.seen.map(\.name), ["c"])
        XCTAssertEqual(p.newCount, 2)
    }
    func testNeverLookedMeansEverythingIsNew() {
        let p = SinceLastLooked.partition([Item(name: "a", at: t0)], arrival: { $0.at }, lastLooked: nil)
        XCTAssertEqual(p.newCount, 1)
        XCTAssertTrue(p.seen.isEmpty)
    }
    func testArrivalEqualToLastLookedIsSeen() {
        let p = SinceLastLooked.partition([Item(name: "a", at: t0)], arrival: { $0.at }, lastLooked: t0)
        XCTAssertEqual(p.newCount, 0)
    }
    func testUnparseableArrivalCountsAsSeen() {
        let p = SinceLastLooked.partition([Item(name: "a", at: nil)], arrival: { $0.at }, lastLooked: t0)
        XCTAssertEqual(p.seen.count, 1)
    }
    func testDividerText() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let d = cal.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 13, minute: 45))!
        XCTAssertEqual(
            SinceLastLooked.dividerText(newCount: 4, lastLooked: d, timeZone: TimeZone(identifier: "UTC")!),
            "Since you last looked · 4 new · 13:45")
        XCTAssertEqual(SinceLastLooked.dividerText(newCount: 1, lastLooked: nil), "Since you last looked · 1 new")
    }
}
