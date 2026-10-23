import XCTest
@testable import PulseFeed

/// The Deck board's grid arithmetic and the Unread card's row order — pure, so the window can be
/// sized before it draws.
final class DeckBoardLayoutTests: XCTestCase {
    func testSixColumnsShareTheWidthAfterInsetsAndGaps() {
        // 1440 wide: 1440 − 32 − 5×12 = 1348 → 224.67 per column.
        XCTAssertEqual(DeckBoardLayout.columnWidth(boardWidth: 1440), 1348.0 / 6, accuracy: 0.001)
        XCTAssertEqual(DeckBoardLayout.columnWidth(boardWidth: 0), 0)
    }

    func testSpansIncludeTheirInnerGaps() {
        let column = DeckBoardLayout.columnWidth(boardWidth: 1440)
        XCTAssertEqual(DeckBoardLayout.span(1, column: column), column)
        XCTAssertEqual(DeckBoardLayout.span(2, column: column), 2 * column + 12, accuracy: 0.001)
        // Two two-column widgets plus two single columns and their three gaps fill the board.
        let total = 2 * DeckBoardLayout.span(2, column: column) + 2 * column + 3 * DeckBoardLayout.gap
        XCTAssertEqual(total, 1440 - 32, accuracy: 0.001)
    }

    func testReaderCoversTheTwoRightHandColumnsButNeverShrinksBelow460() {
        // 1440: two columns + gap = 461.3, the sheet's 460 to the point.
        XCTAssertEqual(DeckBoardLayout.readerWidth(column: DeckBoardLayout.columnWidth(boardWidth: 1440)), 1348.0 / 3 + 12, accuracy: 0.001)
        // 1512 (this Mac's full width): wider, so the card still covers Unread and Sources exactly.
        let wide = DeckBoardLayout.columnWidth(boardWidth: 1512)
        XCTAssertEqual(DeckBoardLayout.readerWidth(column: wide), 2 * wide + 12, accuracy: 0.001)
        // 1280 (the minimum): two columns are 408, so the sheet's 460 wins.
        XCTAssertEqual(DeckBoardLayout.readerWidth(column: DeckBoardLayout.columnWidth(boardWidth: 1280)), 460)
    }

    /// The board's rows fill its height: top inset, market cards, the price credit's own line (when the
    /// prices owe one), the gap, the widget row, the bottom inset. The credit line comes out of the
    /// widget row, nowhere else.
    func testRowsSumToTheBoardHeightWithTheCreditRow() {
        let L = DeckBoardLayout.self
        for board: CGFloat in [668, 848, 1000] {   // the 720 minimum and the 900 default, less the 52pt top bar
            let with = L.widgetRowHeight(boardHeight: board, hasCredit: true)
            XCTAssertEqual(L.topInset + L.topRowHeight + L.creditRowHeight + L.gap + with + L.bottomInset, board, accuracy: 0.001)
            let without = L.widgetRowHeight(boardHeight: board, hasCredit: false)
            XCTAssertEqual(L.topInset + L.topRowHeight + L.gap + without + L.bottomInset, board, accuracy: 0.001)
            XCTAssertEqual(without - with, L.creditRowHeight, accuracy: 0.001)
        }
        XCTAssertGreaterThanOrEqual(L.creditRowHeight, 13, "a 10pt line with room above it")
        XCTAssertEqual(L.widgetRowHeight(boardHeight: 0, hasCredit: true), 0)
    }

    func testUnreadOrderIsMostUnreadFirstThenRegistryOrder() {
        let cats = NewsCategory.all.filter { ["crypto", "tech", "ai", "sports"].contains($0.id) }
        let order = DeckBoardLayout.unreadOrder(cats, counts: ["ai": 989, "tech": 178, "sports": 178])
        XCTAssertEqual(order.map(\.id), ["ai", "tech", "sports", "crypto"])
        XCTAssertEqual(DeckBoardLayout.unreadOrder(cats, counts: [:]).map(\.id), ["crypto", "tech", "ai", "sports"])
    }
}
