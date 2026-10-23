import XCTest
@testable import PulseFeed

final class MarketQuotesTests: XCTestCase {
    private let rates22: [String: Double] = ["CAD": 1.4034, "CHF": 0.82204, "EUR": 0.89246, "GBP": 0.74761, "JPY": 157.05, "SEK": 9.917]

    func testDollarIndexOnTheECBRatesOf2026_10_22() throws {
        let v = try XCTUnwrap(KeylessQuotes.dollarIndex(rates22))
        XCTAssertEqual(v, 101.76, accuracy: 0.01)
        XCTAssertNil(KeylessQuotes.dollarIndex(["EUR": 0.9]))
    }

    func testFrankfurterGivesTodayAndTheDailyChange() throws {
        let json = """
        {"amount":1.0,"base":"USD","start_date":"2026-10-21","end_date":"2026-10-22","rates":{
          "2026-10-21":{"CAD":1.4046,"CHF":0.82300,"EUR":0.89300,"GBP":0.74900,"JPY":157.80,"SEK":9.930},
          "2026-10-22":{"CAD":1.4034,"CHF":0.82204,"EUR":0.89246,"GBP":0.74761,"JPY":157.05,"SEK":9.917}}}
        """
        let updates = KeylessQuotes.parseFrankfurter(Data(json.utf8), instruments: ["dxy", "eurusd"])
        let eur = try XCTUnwrap(updates.first { $0.symbol == "eurusd" })
        XCTAssertEqual(eur.price, 1 / 0.89246, accuracy: 0.0001)
        let yesterday = 1 / 0.89300
        XCTAssertEqual(try XCTUnwrap(eur.change24h), (eur.price - yesterday) / yesterday * 100, accuracy: 0.0001)
        XCTAssertEqual(eur.sparklineData.count, 2)
        let dxy = try XCTUnwrap(updates.first { $0.symbol == "dxy" })
        XCTAssertEqual(dxy.price, 101.76, accuracy: 0.01)
        XCTAssertNotNil(dxy.change24h)

        let only = KeylessQuotes.parseFrankfurter(Data(json.utf8), instruments: ["eurusd"])
        XCTAssertEqual(only.map(\.symbol), ["eurusd"])
    }

    func testFrankfurterURLStartsAWeekBack() {
        let now = ISO8601DateFormatter().date(from: "2026-10-22T12:00:00Z")!
        XCTAssertEqual(KeylessQuotes.frankfurterURL(now: now).absoluteString,
                       "https://api.frankfurter.dev/v1/2026-10-15..?base=USD&symbols=EUR,JPY,GBP,CAD,SEK,CHF")
    }

    func testKeylessCoinGeckoAsksOnlyForWhatIsChosen() {
        XCTAssertEqual(KeylessQuotes.coinGeckoURL(instruments: ["spy", "gold", "bitcoin"])?.absoluteString,
                       "https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&ids=pax-gold,sp500-xstock&sparkline=true")
        XCTAssertNil(KeylessQuotes.coinGeckoURL(instruments: ["bitcoin"]))
        XCTAssertNil(KeylessQuotes.coinGeckoURL(instruments: ["dxy"]))
    }

    private func coins(_ ids: [String]) -> Data {
        let rows = ids.enumerated().map { i, id in
            #"{"id":"\#(id)","current_price":\#(i + 1),"price_change_percentage_24h":\#(i + 1),"sparkline_in_7d":{"price":[1,2,3]}}"#
        }
        return Data(("[" + rows.joined(separator: ",") + "]").utf8)
    }

    func testMag7xIsTheMeanOfSeven() throws {
        let seven = KeylessQuotes.coinGeckoIDs["mag7"]!
        XCTAssertEqual(seven.count, 7)
        let all = KeylessQuotes.parseCoinGecko(coins(seven), instruments: ["mag7"])
        let mag = try XCTUnwrap(all.first { $0.symbol == "mag7" })
        XCTAssertEqual(mag.price, 4, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(mag.change24h), 4, accuracy: 1e-9)
        XCTAssertEqual(mag.sparklineData, [1, 2, 3])
        XCTAssertTrue(KeylessQuotes.parseCoinGecko(coins(Array(seven.prefix(6))), instruments: ["mag7"]).isEmpty)
    }

    func testKeylessCoinGeckoMapsTokensToInstruments() {
        let u = KeylessQuotes.parseCoinGecko(coins(["sp500-xstock", "pax-gold"]), instruments: ["spy", "gold"])
        XCTAssertEqual(Set(u.map(\.symbol)), ["spy", "gold"])
    }

    func testFinnhubParse() throws {
        let u = try XCTUnwrap(FinnhubQuotes.parse(Data(#"{"c":712.4,"dp":-1.2,"pc":721.0}"#.utf8), instrument: "qqq"))
        XCTAssertEqual(u.symbol, "qqq")
        XCTAssertEqual(u.price, 712.4)
        XCTAssertEqual(u.change24h, -1.2)
        XCTAssertNil(FinnhubQuotes.parse(Data(#"{"c":0}"#.utf8), instrument: "spy"))
        XCTAssertEqual(FinnhubQuotes.url(symbol: "SPY", key: "k1").absoluteString,
                       "https://finnhub.io/api/v1/quote?symbol=SPY&token=k1")
    }


    func testCryptoQuotesURL() {
        XCTAssertEqual(CryptoQuotes.url(ids: ["bitcoin", "ripple"])?.absoluteString,
                       "https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&ids=bitcoin,ripple&sparkline=true")
        XCTAssertNil(CryptoQuotes.url(ids: []))
    }
}
