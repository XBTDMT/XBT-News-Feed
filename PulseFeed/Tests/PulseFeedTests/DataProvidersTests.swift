import XCTest
@testable import PulseFeed

final class DataProvidersTests: XCTestCase {
    private var suite: String!
    private var d: UserDefaults!
    private var dir: URL!
    private var keys: ProviderKeyStore!

    override func setUpWithError() throws {
        suite = "DataProvidersTests-\(UUID().uuidString)"
        d = UserDefaults(suiteName: suite)
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("dp-\(UUID().uuidString)")
        keys = ProviderKeyStore(directory: dir)
    }

    override func tearDownWithError() throws {
        d.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: dir)
    }

    func testPublicDefaults() {
        XCTAssertEqual(DataProviders.stored(d), DataProviders(quotes: .keyless, liveScores: .balldontlie, cryptoStream: .gemini))
    }

    func testPublicQuotesFollowTheKey() throws {
        XCTAssertEqual(DataProviders.stored(d).effective(keys: keys).quotes, .keyless)
        try keys.set(.finnhub, "k")
        XCTAssertEqual(DataProviders.stored(d).effective(keys: keys).quotes, .finnhub)
    }

    func testUnknownOrUnavailableStoredValueFallsBackToTheDefault() {
        let fallback = DataProviders.stored(d)
        d.set("bloomberg", forKey: DataProviders.quotesKey)
        XCTAssertEqual(DataProviders.stored(d), fallback)
        d.set("yahoo", forKey: DataProviders.quotesKey)
        XCTAssertEqual(DataProviders.stored(d).quotes, BuildFlavor.isPublic ? .keyless : .yahoo)
    }

    func testFinnhubNeedsItsKey() throws {
        var p = DataProviders.stored(d)
        p.quotes = .finnhub
        p.store(d)
        XCTAssertEqual(DataProviders.stored(d).effective(keys: keys).quotes, BuildFlavor.isPublic ? .keyless : .yahoo)
        try keys.set(.finnhub, "k")
        XCTAssertEqual(DataProviders.stored(d).effective(keys: keys).quotes, .finnhub)
    }

    func testCredits() {
        let keyless = DataProviders(quotes: .keyless, liveScores: .balldontlie, cryptoStream: .gemini)
        let k = DataProviders.credits(keyless, instruments: ["bitcoin", "spy", "dxy"])
        XCTAssertTrue(k.contains("Powered by CoinGecko"))
        XCTAssertTrue(k.contains("Source: ECB"))
        XCTAssertTrue(k.contains("Data provided by Gemini"))
        let yahoo = DataProviders(quotes: .yahoo, liveScores: .espn, cryptoStream: .binance)
        let y = DataProviders.credits(yahoo, instruments: ["spy"])
        XCTAssertTrue(y.contains("Yahoo Finance"))
        XCTAssertFalse(y.contains("Powered by CoinGecko"))
        XCTAssertEqual(DataProviders.credits(keyless, instruments: []), [])
    }

    // MARK: - The line beside the prices (CoinGecko's terms: near the data, linked, at 10pt or more)

    func testStripCreditForKeylessDefaults() throws {
        let keyless = DataProviders(quotes: .keyless, liveScores: .balldontlie, cryptoStream: .gemini)
        let line = try XCTUnwrap(DataProviders.stripCredit(keyless, instruments: ["bitcoin", "mag7", "spy", "gold", "dxy"]))
        XCTAssertTrue(line.contains("Powered by CoinGecko"))
        XCTAssertTrue(line.contains("Source: ECB"))
        XCTAssertEqual(line, "Powered by CoinGecko · Gemini · Source: ECB")
    }

    func testStripCreditEmptyWhenNothingShown() {
        let keyless = DataProviders(quotes: .keyless, liveScores: .balldontlie, cryptoStream: .gemini)
        XCTAssertNil(DataProviders.stripCredit(keyless, instruments: []))
    }

    func testStripCreditWithFinnhubStocksOnly() {
        let finnhub = DataProviders(quotes: .finnhub, liveScores: .balldontlie, cryptoStream: .gemini)
        XCTAssertNil(DataProviders.stripCredit(finnhub, instruments: ["spy"]))
        XCTAssertEqual(DataProviders.stripCredit(finnhub, instruments: ["spy", "eurusd"]), "Source: ECB")
    }

    /// Keyless stocks and gold are CoinGecko's tokens; the dollar alone is only the ECB's.
    func testStripCreditNamesOnlyWhatTheShownPricesUse() {
        let keyless = DataProviders(quotes: .keyless, liveScores: .balldontlie, cryptoStream: .gemini)
        XCTAssertEqual(DataProviders.stripCredit(keyless, instruments: ["gold"]), "Powered by CoinGecko")
        XCTAssertEqual(DataProviders.stripCredit(keyless, instruments: ["dxy"]), "Source: ECB")
        XCTAssertEqual(DataProviders.stripCredit(keyless, instruments: ["ethereum"]), "Powered by CoinGecko · Gemini")
    }

    /// A render's credit is worked out from the rows it draws, not from the chosen places still waiting.
    func testDisplayCreditFollowsTheRowsDrawn() {
        let keyless = DataProviders(quotes: .keyless, liveScores: .balldontlie, cryptoStream: .gemini)
        func row(_ id: String) -> MarketRow {
            MarketRow(id: id, label: id, priceText: "1", changeText: nil, isUp: nil, sparkline: [])
        }
        let waiting = MarketsDisplay(rows: [row("dxy")], chosen: [("bitcoin", "BTC"), ("dxy", "USD idx")], providers: keyless)
        XCTAssertEqual(waiting.credit, "Source: ECB")
        XCTAssertNil(MarketsDisplay(rows: [], chosen: [("bitcoin", "BTC")], providers: keyless).credit)
    }

    // MARK: - Where the credit fits (ruling D9: free space only)

    /// A slot borrows from each neighbour gap down to 4pt: 12 between 10pt gaps, 8 between 8s, none at 4.
    func testCreditFitBorrowsFromTheGapsDownToFour() {
        XCTAssertEqual(MarketsCreditFit.borrow(neighbourGap: 10), 12)
        XCTAssertEqual(MarketsCreditFit.borrow(neighbourGap: 8), 8)
        XCTAssertEqual(MarketsCreditFit.borrow(neighbourGap: 6), 4)
        XCTAssertEqual(MarketsCreditFit.borrow(neighbourGap: 3), 0)
        XCTAssertTrue(MarketsCreditFit.fits(slot: 100, credit: 112))
        XCTAssertFalse(MarketsCreditFit.fits(slot: 99.5, credit: 112))
        XCTAssertFalse(MarketsCreditFit.fits(slot: 100, credit: 112, borrow: 0))
    }

    /// The owner's Native Pro header with their usual state: a 3-digit unread badge and "Updated 48m ago"
    /// leaves a slot just short of "Powered by CoinGecko" (the reviewer's finding); the borrow makes it fit,
    /// for a 2-digit badge too, and even for "999+" (1pt to spare).
    func testNativeProHeaderHoldsTheCoinGeckoCredit() {
        let credit = MarketsCreditFit.width(DataProviders.coinGeckoCredit, font: .systemFont(ofSize: 10))
        XCTAssertGreaterThanOrEqual(credit, 111)
        let threeDigits = MarketsCreditFit.nativeProHeaderSlot(badge: "142", updated: "Updated 48m ago")
        XCTAssertLessThan(threeDigits, credit, "without the borrow it would fall back")
        XCTAssertTrue(MarketsCreditFit.fits(slot: threeDigits, credit: credit))
        XCTAssertTrue(MarketsCreditFit.fits(
            slot: MarketsCreditFit.nativeProHeaderSlot(badge: "57", updated: "Updated 48m ago"), credit: credit))
        XCTAssertTrue(MarketsCreditFit.fits(
            slot: MarketsCreditFit.nativeProHeaderSlot(badge: "999+", updated: "Updated 48m ago"), credit: credit))
        for minutes in 10...59 {
            XCTAssertTrue(MarketsCreditFit.fits(
                slot: MarketsCreditFit.nativeProHeaderSlot(badge: "999", updated: "Updated \(minutes)m ago"),
                credit: credit), "\(minutes)m")
        }
        // The public build's longest line has no room there: it goes under the strip.
        let longest = MarketsCreditFit.width("Powered by CoinGecko · Gemini · Source: ECB", font: .systemFont(ofSize: 10))
        XCTAssertFalse(MarketsCreditFit.fits(
            slot: MarketsCreditFit.nativeProHeaderSlot(badge: "142", updated: "Updated 48m ago"), credit: longest))
    }

    /// The private build's Yahoo and Binance owe no line; its coins still come from CoinGecko.
    func testStripCreditForPrivateProviders() {
        let yahoo = DataProviders(quotes: .yahoo, liveScores: .espn, cryptoStream: .binance)
        XCTAssertEqual(DataProviders.stripCredit(yahoo, instruments: ["bitcoin", "mag7", "spy", "gold", "dxy"]), "Powered by CoinGecko")
        XCTAssertNil(DataProviders.stripCredit(yahoo, instruments: ["spy", "dxy"]))
    }
}
