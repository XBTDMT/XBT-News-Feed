import XCTest
@testable import PulseFeed

final class CryptoStreamTests: XCTestCase {
    func testGeminiCandleFrame() throws {
        let frame = #"{"changes":[[1792716660000,81425.56,81438.49,81419.04,81431.66,0.0037],[1792716600000,81417.83,81437.75,81416.82,81425.56,0.0004]],"symbol":"BTCUSD","type":"candles_1m_updates"}"#
        let updates = GeminiStream(coins: ["bitcoin"]).parse(frame)
        XCTAssertEqual(updates.count, 1)
        let u = try XCTUnwrap(updates.first)
        XCTAssertEqual(u.symbol, "bitcoin")
        XCTAssertEqual(u.price, 81431.66)
        XCTAssertNil(u.change24h)
    }

    func testGeminiIgnoresOtherFrames() {
        let g = GeminiStream(coins: ["bitcoin"])
        XCTAssertTrue(g.parse(#"{"type":"heartbeat","timestamp":1792716660000}"#).isEmpty)
        XCTAssertTrue(g.parse("not json").isEmpty)
        XCTAssertTrue(g.parse(#"{"changes":[],"symbol":"BTCUSD","type":"candles_1m_updates"}"#).isEmpty)
        XCTAssertTrue(g.parse(#"{"changes":[[1,2,3,4,5,6]],"symbol":"DOGEUSD","type":"candles_1m_updates"}"#).isEmpty)
    }

    func testGeminiSubscribeNamesTheChosenCoins() throws {
        let g = GeminiStream(coins: ["bitcoin", "solana"])
        XCTAssertEqual(g.url.absoluteString, "wss://api.gemini.com/v2/marketdata")
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(XCTUnwrap(g.subscribeMessage).utf8)) as? [String: Any])
        XCTAssertEqual(json["type"] as? String, "subscribe")
        let subs = try XCTUnwrap(json["subscriptions"] as? [[String: Any]])
        XCTAssertEqual(subs.first?["name"] as? String, "candles_1m")
        XCTAssertEqual(subs.first?["symbols"] as? [String], ["BTCUSD", "SOLUSD"])
    }

    func testChangeFromOpen() throws {
        let bare = PriceUpdate(symbol: "bitcoin", price: 110, timestamp: Date())
        XCTAssertEqual(try XCTUnwrap(bare.withChange(fromOpen: 100).change24h), 10.0, accuracy: 1e-9)
        let had = PriceUpdate(symbol: "bitcoin", price: 110, change24h: -3, timestamp: Date())
        XCTAssertEqual(had.withChange(fromOpen: 100).change24h, -3)
        XCTAssertNil(bare.withChange(fromOpen: nil).change24h)
        XCTAssertNil(bare.withChange(fromOpen: 0).change24h)
    }

    func testNoCoinsMeansNoStream() {
        XCTAssertNil(CryptoStreams.spec(source: .gemini, coins: []))
        XCTAssertNil(CryptoStreams.spec(source: .gemini, coins: ["spy"]))
        XCTAssertEqual(CryptoStreams.spec(source: .gemini, coins: ["bitcoin"])?.name, "Gemini")
    }

}
