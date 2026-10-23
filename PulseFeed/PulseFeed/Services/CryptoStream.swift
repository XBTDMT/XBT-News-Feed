import Foundation

/// A live coin-price stream the WebSocket manager can run while on power (spec D12, G-2).
protocol CryptoStreamSpec: Sendable {
    var name: String { get }
    var url: URL { get }
    /// Sent once after the socket opens; nil when the URL alone subscribes.
    var subscribeMessage: String? { get }
    func parse(_ text: String) -> [PriceUpdate]
}

/// Gemini's public market-data socket: one-minute candles for the chosen coins, no key
/// ("Data provided by Gemini"). It sends prices only; the engine fills the day's change from CoinGecko.
struct GeminiStream: CryptoStreamSpec {
    static let pairs: [String: String] = ["bitcoin": "BTCUSD", "ethereum": "ETHUSD", "solana": "SOLUSD", "ripple": "XRPUSD"]

    let coins: [String]

    var name: String { "Gemini" }
    var url: URL { URL(string: "wss://api.gemini.com/v2/marketdata")! }

    var subscribeMessage: String? {
        let symbols = coins.compactMap { Self.pairs[$0] }
        let body: [String: Any] = ["type": "subscribe", "subscriptions": [["name": "candles_1m", "symbols": symbols]]]
        return (try? JSONSerialization.data(withJSONObject: body)).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// `candles_1m_updates`: newest candle first, `[time, open, high, low, close, volume]`.
    func parse(_ text: String) -> [PriceUpdate] {
        guard let json = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
              json["type"] as? String == "candles_1m_updates",
              let pair = json["symbol"] as? String,
              let coin = Self.pairs.first(where: { $0.value == pair })?.key,
              let newest = (json["changes"] as? [[Any]])?.first, newest.count > 4,
              let close = (newest[4] as? NSNumber)?.doubleValue else { return [] }
        return [PriceUpdate(symbol: coin, price: close, timestamp: Date())]
    }
}

enum CryptoStreams {
    /// The stream for the chosen coins, or nil when no coin is chosen (the socket then stays shut).
    static func spec(source: CryptoStreamSource, coins: [String]) -> (any CryptoStreamSpec)? {
        let chosen = coins.filter { GeminiStream.pairs[$0] != nil }
        guard !chosen.isEmpty else { return nil }
        switch source {
        case .gemini: return GeminiStream(coins: chosen)
        case .binance:
            return GeminiStream(coins: chosen)
        }
    }
}

extension PriceUpdate {
    /// Fills a missing 24 h change from the price a day ago; a change the source sent is kept.
    func withChange(fromOpen open: Double?) -> PriceUpdate {
        guard change24h == nil, let open, open > 0 else { return self }
        var u = self
        u.change24h = (price - open) / open * 100
        return u
    }
}
