import XCTest
@testable import PulseFeed

/// Native Pro's Inbox window (N2): the top bar shares its width between the markets strip and the
/// search field, and the footer tallies feed health. Both are pure arithmetic, tested here.
final class NativeProInboxLayoutTests: XCTestCase {
    // MARK: - Top bar split

    /// The price credit lines up with the search field's text: after the lights, the strip and a gap.
    func testCreditSitsAtTheSearchTextsX() {
        let bar: CGFloat = 1144
        XCTAssertEqual(NativeProInboxLayout.creditLeading(barWidth: bar, hasStrip: true),
                       NativeProInboxLayout.lightsInset + NativeProInboxLayout.stripWidth(barWidth: bar)
                           + NativeProInboxLayout.topBarGap + 10)
        XCTAssertEqual(NativeProInboxLayout.creditLeading(barWidth: bar, hasStrip: false), NativeProInboxLayout.lightsInset + 10)
        XCTAssertLessThan(NativeProInboxLayout.creditBottomInset, NativeProInboxLayout.topBarHeight / 4)
    }

    /// At the sheet's 1440 the strip is its full 640 and the search takes what is left.
    func testWideBarGivesTheStripItsFullWidth() {
        XCTAssertEqual(NativeProInboxLayout.stripWidth(barWidth: 1440), 640)
        XCTAssertEqual(NativeProInboxLayout.searchWidth(barWidth: 1440),
                       NativeProInboxLayout.topBarAvailable(barWidth: 1440) - 640)
        XCTAssertGreaterThan(NativeProInboxLayout.searchWidth(barWidth: 1440), NativeProInboxLayout.searchMinWidth)
    }

    /// The default window (1144) still fits the whole strip with a usable search field.
    func testDefaultWindowKeepsTheFullStrip() {
        XCTAssertEqual(NativeProInboxLayout.stripWidth(barWidth: 1144), 640)
        XCTAssertGreaterThanOrEqual(NativeProInboxLayout.searchWidth(barWidth: 1144), NativeProInboxLayout.searchMinWidth)
    }

    /// At the window's minimum width the strip gives way so the search keeps its 180.
    func testNarrowBarShrinksTheStripToProtectTheSearch() {
        let bar: CGFloat = 900
        let strip = NativeProInboxLayout.stripWidth(barWidth: bar)
        XCTAssertLessThan(strip, 640)
        XCTAssertGreaterThanOrEqual(strip, NativeProInboxLayout.stripMinWidth)
        XCTAssertEqual(NativeProInboxLayout.searchWidth(barWidth: bar), NativeProInboxLayout.searchMinWidth)
    }

    /// The strip never goes under its minimum while the bar can hold it; below that it is the bar.
    func testStripFloorAndAbsurdlyNarrowBars() {
        // Just enough for the strip's floor plus the search's floor.
        let tight = NativeProInboxLayout.stripMinWidth + NativeProInboxLayout.searchMinWidth
        let tightBar = tight + (NativeProInboxLayout.lightsInset + NativeProInboxLayout.inset
                                + 4 * NativeProInboxLayout.topBarGap + 3 * NativeProInboxLayout.glyphWidth)
        XCTAssertEqual(NativeProInboxLayout.stripWidth(barWidth: tightBar), NativeProInboxLayout.stripMinWidth)
        XCTAssertEqual(NativeProInboxLayout.searchWidth(barWidth: tightBar), NativeProInboxLayout.searchMinWidth)
        // Under the two floors the strip holds its 420 and the search goes under its minimum.
        XCTAssertEqual(NativeProInboxLayout.stripWidth(barWidth: tightBar - 100), NativeProInboxLayout.stripMinWidth)
        XCTAssertEqual(NativeProInboxLayout.searchWidth(barWidth: tightBar - 100), NativeProInboxLayout.searchMinWidth - 100)
        // Once the bar cannot hold 420 the strip is whatever is left and the search collapses.
        let overhead = NativeProInboxLayout.lightsInset + NativeProInboxLayout.inset
            + 4 * NativeProInboxLayout.topBarGap + 3 * NativeProInboxLayout.glyphWidth
        XCTAssertEqual(NativeProInboxLayout.stripWidth(barWidth: 300 + overhead), 300)
        XCTAssertEqual(NativeProInboxLayout.searchWidth(barWidth: 300 + overhead), 0)
        XCTAssertEqual(NativeProInboxLayout.stripWidth(barWidth: 0), 0)
        XCTAssertEqual(NativeProInboxLayout.searchWidth(barWidth: 0), 0)
        XCTAssertEqual(NativeProInboxLayout.stripWidth(barWidth: -50), 0)
    }

    /// Strip plus search is always exactly what the bar has left after the insets, gaps and glyphs.
    func testStripAndSearchAlwaysSumToTheAvailableWidth() {
        for bar: CGFloat in [300, 600, 900, 1000, 1144, 1440, 2000] {
            let available = NativeProInboxLayout.topBarAvailable(barWidth: bar)
            XCTAssertEqual(NativeProInboxLayout.stripWidth(barWidth: bar) + NativeProInboxLayout.searchWidth(barWidth: bar),
                           available, accuracy: 0.001, "bar \(bar)")
        }
    }

    /// The panes: 460 for the list and at least 420 for the reader fit inside the design's minimum window.
    @MainActor func testListAndReaderFitTheMinimumWindow() {
        XCTAssertLessThanOrEqual(NativeProInboxLayout.listWidth + NativeProInboxLayout.readerMinWidth + 1,
                                 AppDesign.nativePro.mainWindowMinSize.width)
        XCTAssertLessThanOrEqual(NativeProInboxLayout.listWidth, NativeProInboxLayout.listMaxWidth)
    }

    // MARK: - Feed health tally

    func testHealthTallyCountsEachCaseOnce() {
        let tally = NativeProInboxLayout.HealthTally(healths: [
            .ok, .ok, .stale(daysSinceArticle: 20), .failing(errors: 3), .ok, .stale(daysSinceArticle: 15),
        ])
        XCTAssertEqual(tally, NativeProInboxLayout.HealthTally(total: 6, ok: 3, stale: 2, failing: 1))
    }

    func testHealthTallyOfNothing() {
        XCTAssertEqual(NativeProInboxLayout.HealthTally(healths: []), NativeProInboxLayout.HealthTally(total: 0, ok: 0, stale: 0, failing: 0))
    }
}
