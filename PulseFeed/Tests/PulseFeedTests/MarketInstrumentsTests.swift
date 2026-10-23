import XCTest
@testable import PulseFeed

final class MarketInstrumentsTests: XCTestCase {
    private var suite: String!
    private var d: UserDefaults!

    override func setUp() {
        suite = "MarketInstrumentsTests-\(UUID().uuidString)"
        d = UserDefaults(suiteName: suite)
    }

    override func tearDown() { d.removePersistentDomain(forName: suite) }

    private func price(_ s: String) -> PriceUpdate {
        PriceUpdate(symbol: s, price: 100, change24h: 1.0, timestamp: Date())
    }

    func testAnInstallInUseKeepsItsStoredListOrderAndLabels() {
        d.set(["bitcoin", "mag7", "spy", "gold", "dxy"], forKey: SettingsFreeze.marketInstrumentsKey)
        let ids = MarketInstrument.stored(d)
        let prices = Dictionary(uniqueKeysWithValues: ids.map { ($0, price($0)) })
        let rows = MarketsModel.rows(prices: prices, history: [:], instruments: ids, quotes: .yahoo)
        XCTAssertEqual(rows.map(\.label), ["BTC", "MAG7", "SPY", "Gold", "DXY"])
        XCTAssertEqual(rows.map(\.id), ["bitcoin", "mag7", "spy", "gold", "dxy"])
    }

    func testNewUserHasNoInstruments() {
        XCTAssertEqual(MarketInstrument.stored(d), [])
        XCTAssertTrue(MarketsModel.rows(prices: ["bitcoin": price("bitcoin")], history: [:],
                                        instruments: MarketInstrument.stored(d), quotes: .keyless).isEmpty)
    }

    func testCleaning() {
        MarketInstrument.store(["spy", "nope", "spy", "bitcoin", "qqq", "gold", "dxy", "oil"], d)
        XCTAssertEqual(MarketInstrument.stored(d), ["spy", "bitcoin", "qqq", "gold", "dxy"])
        d.set(["bitcoin", "bogus", "bitcoin"], forKey: SettingsFreeze.marketInstrumentsKey)
        XCTAssertEqual(MarketInstrument.stored(d), ["bitcoin"])
    }

    func testKeylessLabelsSayWhatTheyAre() {
        let k: [String: String] = ["spy": "SPYx", "qqq": "QQQx", "mag7": "MAG7x", "gold": "PAXG", "dxy": "USD idx", "eurusd": "EUR/USD"]
        for (id, label) in k { XCTAssertEqual(MarketInstrument.label(id, quotes: .keyless), label, id) }
        XCTAssertEqual(MarketInstrument.label("gold", quotes: .finnhub), "GLD")
        XCTAssertEqual(MarketInstrument.label("oil", quotes: .finnhub), "USO")
        XCTAssertEqual(MarketInstrument.label("dxy", quotes: .finnhub), "UUP")
        XCTAssertEqual(MarketInstrument.label("dxy", quotes: .yahoo), "DXY")
        XCTAssertEqual(MarketInstrument.label("bitcoin", quotes: .keyless), "BTC")
    }

    func testOilNeedsAQuoteProvider() {
        XCTAssertFalse(MarketInstrument.isAvailable("oil", quotes: .keyless))
        XCTAssertTrue(MarketInstrument.isAvailable("oil", quotes: .finnhub))
        XCTAssertTrue(MarketInstrument.isAvailable("oil", quotes: .yahoo))
        for i in MarketInstrument.all where i.id != "oil" {
            for q in QuoteSource.allCases { XCTAssertTrue(MarketInstrument.isAvailable(i.id, quotes: q), "\(i.id) \(q)") }
        }
    }

    func testListAndSuggestion() {
        XCTAssertEqual(MarketInstrument.all.map(\.id),
                       ["bitcoin", "ethereum", "solana", "ripple", "spy", "qqq", "mag7", "gold", "oil", "dxy", "eurusd"])
        XCTAssertEqual(MarketInstrument.suggested, ["bitcoin", "spy", "qqq", "gold", "dxy"])
        XCTAssertEqual(MarketInstrument.maxChosen, 5)
    }

    func testIndexAndCurrencyAreNotDollars() {
        let prices = ["dxy": PriceUpdate(symbol: "dxy", price: 101.757, change24h: 0.1, timestamp: Date()),
                      "eurusd": PriceUpdate(symbol: "eurusd", price: 1.12051, change24h: -0.2, timestamp: Date())]
        let rows = MarketsModel.rows(prices: prices, history: [:], instruments: ["dxy", "eurusd"], quotes: .keyless)
        XCTAssertEqual(rows.map(\.priceText), ["101.76", "1.1205"])
        let yahoo = MarketsModel.rows(prices: prices, history: [:], instruments: ["dxy"], quotes: .yahoo)
        XCTAssertEqual(yahoo.first?.priceText, "101.76")
    }
}
