import Foundation

// Where the strip's numbers come from (spec D10, D12, G-2). Coins always come from CoinGecko's poll (and
// the live stream on power); everything else from the quote source the install uses.

struct CoinGeckoMarket: Codable {
    let id: String
    let current_price: Double
    let price_change_percentage_24h: Double?
    let sparkline_in_7d: CoinGeckoSparkline?
}

struct CoinGeckoSparkline: Codable {
    let price: [Double]
}

/// BTC, ETH, SOL and XRP from CoinGecko's keyless markets call (credit: "Powered by CoinGecko").
enum CryptoQuotes {
    static let coinGeckoIDs = ["bitcoin", "ethereum", "solana", "ripple"]

    static func url(ids: [String]) -> URL? {
        guard !ids.isEmpty else { return nil }
        return URL(string: "https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&ids=\(ids.joined(separator: ","))&sparkline=true")
    }

    /// The last 48 points (~24 h) of the 7-day sparkline ride along for the charts.
    static func parse(_ data: Data, now: Date = Date()) throws -> [PriceUpdate] {
        try JSONDecoder().decode([CoinGeckoMarket].self, from: data).map { coin in
            PriceUpdate(symbol: coin.id, price: coin.current_price, change24h: coin.price_change_percentage_24h,
                        timestamp: now, sparklineData: Array((coin.sparkline_in_7d?.price ?? []).suffix(48)))
        }
    }
}

/// Stocks and gold as CoinGecko's tokenized copies, the dollar as the ECB's daily rates: no key needed.
/// The labels say so ("SPYx", "PAXG", "USD idx"; `MarketInstrument.label`).
enum KeylessQuotes {
    /// Every id answered when the keyless providers were checked on 2026-10-22.
    static let coinGeckoIDs: [String: [String]] = [
        "spy": ["sp500-xstock"],
        "qqq": ["nasdaq-xstock"],
        "mag7": ["apple-xstock", "microsoft-xstock", "nvidia-xstock", "amazon-xstock", "alphabet-xstock",
                 "meta-xstock", "tesla-xstock"],
        "gold": ["pax-gold"],
    ]

    static func coinGeckoURL(instruments: [String]) -> URL? {
        let ids = Set(instruments.flatMap { coinGeckoIDs[$0] ?? [] }).sorted()
        return CryptoQuotes.url(ids: ids)
    }

    /// One update per chosen instrument whose tokens all answered; MAG7x is the seven tokens' mean
    /// price, mean change and point-wise mean sparkline.
    static func parseCoinGecko(_ data: Data, instruments: [String], now: Date = Date()) -> [PriceUpdate] {
        guard let coins = try? JSONDecoder().decode([CoinGeckoMarket].self, from: data) else { return [] }
        let byID = Dictionary(coins.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return instruments.compactMap { instrument in
            guard let ids = coinGeckoIDs[instrument] else { return nil }
            let found = ids.compactMap { byID[$0] }
            guard found.count == ids.count, !found.isEmpty else { return nil }
            let n = Double(found.count)
            let price = found.map(\.current_price).reduce(0, +) / n
            let changes = found.compactMap(\.price_change_percentage_24h)
            let change = changes.count == found.count ? changes.reduce(0, +) / n : nil
            let series = found.map { Array(($0.sparkline_in_7d?.price ?? []).suffix(48)) }
            let length = series.map(\.count).min() ?? 0
            let spark = (0..<length).map { i in series.map { $0[$0.count - length + i] }.reduce(0, +) / n }
            return PriceUpdate(symbol: instrument, price: price, change24h: change, timestamp: now, sparklineData: spark)
        }
    }

    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// A week of the ECB's daily reference rates against the dollar, so the newest two give the change.
    static func frankfurterURL(now: Date) -> URL {
        let start = day.string(from: now.addingTimeInterval(-7 * 86400))
        return URL(string: "https://api.frankfurter.dev/v1/\(start)..?base=USD&symbols=EUR,JPY,GBP,CAD,SEK,CHF")!
    }

    /// ICE's DXY formula on ECB rates; it must be labelled a computed index, never "DXY".
    static func dollarIndex(_ r: [String: Double]) -> Double? {
        guard let eur = r["EUR"], let jpy = r["JPY"], let gbp = r["GBP"], let cad = r["CAD"], let sek = r["SEK"],
              let chf = r["CHF"], eur > 0, gbp > 0 else { return nil }
        return 50.14348112 * pow(1 / eur, -0.576) * pow(jpy, 0.136) * pow(1 / gbp, -0.119)
            * pow(cad, 0.091) * pow(sek, 0.042) * pow(chf, 0.036)
    }

    private struct FrankfurterRange: Codable { let rates: [String: [String: Double]] }

    static func parseFrankfurter(_ data: Data, instruments: [String], now: Date = Date()) -> [PriceUpdate] {
        guard let range = try? JSONDecoder().decode(FrankfurterRange.self, from: data) else { return [] }
        let days = range.rates.keys.sorted()
        func series(_ value: ([String: Double]) -> Double?) -> [Double] { days.compactMap { range.rates[$0].flatMap(value) } }
        func update(_ symbol: String, _ values: [Double]) -> PriceUpdate? {
            guard let last = values.last else { return nil }
            let change = values.count >= 2 && values[values.count - 2] > 0
                ? (last - values[values.count - 2]) / values[values.count - 2] * 100 : nil
            return PriceUpdate(symbol: symbol, price: last, change24h: change, timestamp: now, sparklineData: values)
        }
        var out: [PriceUpdate] = []
        for instrument in instruments {
            switch instrument {
            case "dxy": if let u = update("dxy", series(dollarIndex)) { out.append(u) }
            case "eurusd": if let u = update("eurusd", series { $0["EUR"].flatMap { $0 > 0 ? 1 / $0 : nil } }) { out.append(u) }
            default: continue
            }
        }
        return out
    }
}

/// Real exchange quotes with the person's own free Finnhub key; gold, oil and the dollar through the funds
/// that track them (Finnhub's forex and metals are premium).
enum FinnhubQuotes {
    static let symbols: [String: String] = ["spy": "SPY", "qqq": "QQQ", "mag7": "MAGS", "gold": "GLD", "oil": "USO", "dxy": "UUP"]

    static func url(symbol: String, key: String) -> URL {
        var c = URLComponents(string: "https://finnhub.io/api/v1/quote")!
        c.queryItems = [URLQueryItem(name: "symbol", value: symbol), URLQueryItem(name: "token", value: key)]
        return c.url!
    }

    static func parse(_ data: Data, instrument: String, now: Date = Date()) -> PriceUpdate? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let price = (json["c"] as? NSNumber)?.doubleValue, price > 0 else { return nil }
        return PriceUpdate(symbol: instrument, price: price, change24h: (json["dp"] as? NSNumber)?.doubleValue, timestamp: now)
    }
}

/// Fetches the non-coin instruments from one quote source. A call that fails gives no update for its
/// instruments, never an error: the strip keeps its last numbers.
struct QuoteFetcher: Sendable {
    let session: URLSession

    func fetch(instruments: [String], source: QuoteSource, keys: ProviderKeyStore, now: Date = Date()) async -> (updates: [PriceUpdate], requests: Int) {
        let wanted = instruments.filter { MarketInstrument.named($0)?.kind != .crypto }
        guard !wanted.isEmpty else { return ([], 0) }
        var updates: [PriceUpdate] = []
        var requests = 0
        func get(_ url: URL) async -> Data? {
            requests += 1
            guard let (data, response) = try? await session.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return data
        }
        let fx = wanted.filter { $0 == "dxy" || $0 == "eurusd" }
        switch source {
        case .keyless:
            if let url = KeylessQuotes.coinGeckoURL(instruments: wanted), let data = await get(url) {
                updates += KeylessQuotes.parseCoinGecko(data, instruments: wanted, now: now)
            }
            if !fx.isEmpty, let data = await get(KeylessQuotes.frankfurterURL(now: now)) {
                updates += KeylessQuotes.parseFrankfurter(data, instruments: fx, now: now)
            }
        case .finnhub:
            guard let key = keys.get(.finnhub) else { return ([], 0) }
            for id in wanted {
                guard let symbol = FinnhubQuotes.symbols[id] else { continue }
                if let data = await get(FinnhubQuotes.url(symbol: symbol, key: key)),
                   let u = FinnhubQuotes.parse(data, instrument: id, now: now) { updates.append(u) }
            }
            if wanted.contains("eurusd"), let data = await get(KeylessQuotes.frankfurterURL(now: now)) {
                updates += KeylessQuotes.parseFrankfurter(data, instruments: ["eurusd"], now: now)
            }
        case .yahoo:
            break   // the public build offers no Yahoo client (QuoteSource.available leaves it out)
        }
        return (updates, requests)
    }
}
