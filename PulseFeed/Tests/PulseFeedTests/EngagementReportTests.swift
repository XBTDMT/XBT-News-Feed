import XCTest
@testable import PulseFeed

/// The learning week: what was shown, opened, starred, saved or dismissed, counted locally, and the
/// pre-registered rules that turn those counts into proposals (nothing changes until accepted).
final class EngagementReportTests: XCTestCase {
    private func rows(_ event: EngagementEvent, count: Int, feed: String = "f1", category: String = "tech", topics: String? = nil, idPrefix: String = "a") -> [EngagementRow] {
        (0..<count).map { i in
            EngagementRow(at: "2026-09-08 10:00:00", event: event.rawValue, articleID: "\(idPrefix)\(i)", feedID: feed, feedTitle: feed.uppercased(), category: category, topics: topics, value: nil)
        }
    }

    func testStudyProgressCountsDaysAndUnlocksAfterAWeek() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let day3 = EngagementStudy(startedAt: start).progress(now: start.addingTimeInterval(2 * 86400 + 60))
        XCTAssertEqual(day3.day, 3); XCTAssertFalse(day3.ready)
        let done = EngagementStudy(startedAt: start).progress(now: start.addingTimeInterval(7 * 86400))
        XCTAssertEqual(done.day, 7); XCTAssertTrue(done.ready)
        XCTAssertEqual(EngagementStudy(startedAt: start).endsAt, start.addingTimeInterval(7 * 86400))
    }

    func testAnImpressionIsRecordedOncePerRun() {
        var seen = ImpressionDedupe()
        XCTAssertTrue(seen.firstTime("a1"))
        XCTAssertFalse(seen.firstTime("a1"))
        XCTAssertTrue(seen.firstTime("a2"))
    }

    func testProposesDisablingASourceNobodyOpens() {
        let events = rows(.shown, count: 60, feed: "skift", idPrefix: "s")
            + rows(.shown, count: 60, feed: "guardian", idPrefix: "g") + rows(.opened, count: 20, feed: "guardian", idPrefix: "g")
        let report = EngagementReport.build(events: events, enabledCategories: ["tech"], categoriesOff: [])
        XCTAssertEqual(report.proposals.map(\.id), ["disable-source:skift"])
        XCTAssertTrue(report.proposals[0].evidence.contains("0 of 60"))
        XCTAssertEqual(report.sources.first(where: { $0.feedID == "guardian" })?.opens, 20)
    }

    func testProposesEnablingACategoryYouKeepOpeningByTopic() {
        let events = rows(.shown, count: 10, feed: "bbc", category: "world", idPrefix: "w")
            + rows(.opened, count: 6, feed: "bbc", category: "world", topics: "politics,election", idPrefix: "w")
        let report = EngagementReport.build(events: events, enabledCategories: ["world"], categoriesOff: ["politics", "science"])
        XCTAssertEqual(report.proposals.map(\.id), ["enable-category:politics"])
        XCTAssertTrue(report.proposals[0].evidence.contains("6"))
    }

    func testNotEnoughDataProposesNothing() {
        let events = rows(.shown, count: 10, feed: "skift") + rows(.dismissed, count: 2, feed: "skift")
        let report = EngagementReport.build(events: events, enabledCategories: ["tech"], categoriesOff: ["politics"])
        XCTAssertTrue(report.proposals.isEmpty)
        XCTAssertEqual(report.totals.shown, 10); XCTAssertEqual(report.totals.dismissed, 2)
    }

    func testDismissalsAloneCanRetireASource() {
        let events = rows(.shown, count: 12, feed: "tpg") + rows(.dismissed, count: 5, feed: "tpg")
        let report = EngagementReport.build(events: events, enabledCategories: ["travel"], categoriesOff: [])
        XCTAssertEqual(report.proposals.map(\.id), ["disable-source:tpg"])
    }
}
