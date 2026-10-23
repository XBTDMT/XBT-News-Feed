import XCTest
@testable import PulseFeed

/// One formatter for every price in the app (popover strip, sidebar, tiles, menu bar capsule).
final class PriceFormattingTests: XCTestCase {
    func testDXYIsAnIndexWithTwoDecimalsAndNoDollar() {
        XCTAssertEqual(PriceFormatting.price(99.163, symbol: "DXY"), "99.16")
    }
    func testThousandsGroupWithoutDecimals() {
        XCTAssertEqual(PriceFormatting.price(109842.4, symbol: "BTC"), "$109,842")
    }
    func testUnderAThousandKeepsTwoDecimals() {
        XCTAssertEqual(PriceFormatting.price(69.437, symbol: "MAG7"), "$69.44")
    }
    func testSubDollarKeepsFourDecimals() {
        XCTAssertEqual(PriceFormatting.price(0.42129, symbol: "X"), "$0.4213")
    }
    func testChangeHasSignAndOneDecimal() {
        XCTAssertEqual(PriceFormatting.change(1.84), "+1.8%")
        XCTAssertEqual(PriceFormatting.change(-1.41), "-1.4%")
        XCTAssertNil(PriceFormatting.change(nil))
        XCTAssertEqual(PriceFormatting.change(-0.02), "0.0%", "a change that rounds to zero carries no sign")
        XCTAssertEqual(PriceFormatting.change(0.04), "0.0%")
    }
    func testRowsFollowTheChosenOrderAndSkipMissing() {
        let p = [
            "dxy": PriceUpdate(symbol: "dxy", price: 99.16, change24h: -0.02, timestamp: Date()),
            "bitcoin": PriceUpdate(symbol: "bitcoin", price: 109842, change24h: 1.8, timestamp: Date()),
        ]
        let rows = MarketsModel.rows(prices: p, history: ["bitcoin": [1, 2, 3]],
                                     instruments: SettingsFreeze.todaysInstruments, quotes: .yahoo)
        XCTAssertEqual(rows.map(\.label), ["BTC", "DXY"])
        XCTAssertEqual(rows[0].sparkline, [1, 2, 3])
        XCTAssertEqual(rows[0].isUp, true)
        XCTAssertEqual(rows[1].isUp, false)
        XCTAssertEqual(rows[1].priceText, "99.16")
    }
}
