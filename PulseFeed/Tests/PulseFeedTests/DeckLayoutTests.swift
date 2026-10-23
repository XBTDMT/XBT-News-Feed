import XCTest
@testable import PulseFeed

/// Deck: the expanded tile's height is pure arithmetic — collapsed height plus one row height per
/// content row, never past the cap — so the popover can size a tile before it draws it.
final class DeckLayoutTests: XCTestCase {
    func testZeroRowsReturnsCollapsedHeight() {
        XCTAssertEqual(DeckLayout.expandedHeight(collapsed: 132, contentRows: 0, rowHeight: 64, cap: 420), 132)
    }

    func testGrowsByRowHeightPerRow() {
        XCTAssertEqual(DeckLayout.expandedHeight(collapsed: 132, contentRows: 1, rowHeight: 64, cap: 420), 196)
        XCTAssertEqual(DeckLayout.expandedHeight(collapsed: 132, contentRows: 2, rowHeight: 64, cap: 420), 260)
        XCTAssertEqual(DeckLayout.expandedHeight(collapsed: 100, contentRows: 3, rowHeight: 24, cap: 420), 172)
    }

    func testNeverExceedsCap() {
        XCTAssertEqual(DeckLayout.expandedHeight(collapsed: 132, contentRows: 50, rowHeight: 64, cap: 420), 420)
        XCTAssertEqual(DeckLayout.expandedHeight(collapsed: 132, contentRows: 5, rowHeight: 64, cap: 420), 420)
        // A cap below the collapsed height still wins: the caller asked for a ceiling.
        XCTAssertEqual(DeckLayout.expandedHeight(collapsed: 132, contentRows: 0, rowHeight: 64, cap: 100), 100)
    }

    func testNegativeRowsAreTreatedAsZero() {
        XCTAssertEqual(DeckLayout.expandedHeight(collapsed: 132, contentRows: -3, rowHeight: 64, cap: 420), 132)
    }

    // MARK: - Grid arrangement

    /// An expanded tile takes its whole row; its row-mates become strips beneath it, in row order.
    func testRowLayoutStacksTheExpandedTileOverItsRowMates() {
        let top: [DeckTileID] = [.breaking, .markets]
        XCTAssertEqual(DeckLayout.rowLayout(top, expanded: .breaking),
                       DeckLayout.RowLayout(expanded: .breaking, strips: [.markets]))
        XCTAssertEqual(DeckLayout.rowLayout(top, expanded: .markets),
                       DeckLayout.RowLayout(expanded: .markets, strips: [.breaking]))
        XCTAssertTrue(DeckLayout.rowLayout(top, expanded: .markets).isStacked)
    }

    func testRowLayoutIsSideBySideWhenNothingInTheRowIsExpanded() {
        let top: [DeckTileID] = [.breaking, .markets]
        XCTAssertEqual(DeckLayout.rowLayout(top, expanded: nil), DeckLayout.RowLayout(expanded: nil, strips: []))
        // A tile expanded in ANOTHER row leaves this one untouched.
        XCTAssertEqual(DeckLayout.rowLayout(top, expanded: .unread), DeckLayout.RowLayout(expanded: nil, strips: []))
        XCTAssertFalse(DeckLayout.rowLayout(top, expanded: .unread).isStacked)
    }

    func testRowLayoutOnTheThreeTileBottomRow() {
        let bottom: [DeckTileID] = [.starred, .saved, .search]
        XCTAssertEqual(DeckLayout.rowLayout(bottom, expanded: .search),
                       DeckLayout.RowLayout(expanded: .search, strips: [.starred, .saved]))
        XCTAssertEqual(DeckLayout.rowLayout(bottom, expanded: .saved),
                       DeckLayout.RowLayout(expanded: .saved, strips: [.starred, .search]))
        XCTAssertEqual(DeckLayout.rowLayout(bottom, expanded: .brief).strips, [])
    }

    func testStripIsShorterThanEveryCollapsedTile() {
        XCTAssertLessThan(DeckLayout.stripHeight, DeckLayout.smallTileHeight)
        XCTAssertLessThan(DeckLayout.stripHeight, DeckLayout.tileHeight)
    }

    // MARK: - Copy

    func testNewSinceText() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let d = cal.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 14, minute: 2))!
        XCTAssertEqual(
            DeckLayout.newSinceText(newCount: 4, lastLooked: d, timeZone: TimeZone(identifier: "UTC")!),
            "4 new since 14:02")
        XCTAssertEqual(DeckLayout.newSinceText(newCount: 1, lastLooked: nil), "1 new")
        XCTAssertEqual(DeckLayout.newSinceText(newCount: 0, lastLooked: d, timeZone: TimeZone(identifier: "UTC")!),
                       "Nothing new since 14:02")
    }

    func testSinceDividerTextIsTheSheetsCopy() {
        XCTAssertEqual(DeckLayout.sinceDividerText(newCount: 4), "Since last looked · 4 new")
        XCTAssertEqual(DeckLayout.sinceDividerText(newCount: 1), "Since last looked · 1 new")
    }

    func testGroupedByCategoryFollowsFixedOrderThenAlphabetical() {
        let items = [("a", "world"), ("b", "crypto"), ("c", "zzz"), ("d", "crypto"), ("e", "mma")]
        let groups = DeckLayout.groupedByCategory(items, category: { $0.1 })
        XCTAssertEqual(groups.map(\.category), ["crypto", "world", "mma", "zzz"])
        XCTAssertEqual(groups[0].items.map(\.0), ["b", "d"])
        XCTAssertTrue(DeckLayout.groupedByCategory([(String, String)](), category: { $0.1 }).isEmpty)
    }

    func testCategoryLabels() {
        XCTAssertEqual(DeckLayout.label(for: "f1"), "F1")
        XCTAssertEqual(DeckLayout.label(for: "crypto"), "Crypto")
        XCTAssertEqual(DeckLayout.label(for: "mma"), "Mma")
        XCTAssertEqual(DeckLayout.categories.map(\.tag), NewsCategory.all.map(\.id), "the Deck list mirrors the registry")
        XCTAssertEqual(DeckLayout.visible(["world", "crypto"]).map(\.tag), ["crypto", "world"])
        XCTAssertEqual(DeckLayout.colorHex(for: "f1"), "#FF3B30")
        XCTAssertEqual(DeckLayout.colorHex(for: "mma"), "#8E8E93")
    }

    func testBarHeights() {
        // Proportional to the largest count; zero stays at the floor so an empty category still shows a track.
        let heights = DeckLayout.barHeights(counts: [4, 8, 0], maxHeight: 44, floor: 3)
        XCTAssertEqual(heights, [22, 44, 3])
        XCTAssertEqual(DeckLayout.barHeights(counts: [0, 0], maxHeight: 44, floor: 3), [3, 3])
        XCTAssertEqual(DeckLayout.barHeights(counts: [], maxHeight: 44, floor: 3), [])
    }
}
