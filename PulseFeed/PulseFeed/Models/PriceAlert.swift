import GRDB
import Foundation

struct PriceAlert: Codable, FetchableRecord, PersistableRecord, Sendable, Identifiable {
    var id: String
    var asset: String           // CoinGecko IDs: bitcoin, ethereum, solana, ripple
    var targetPrice: Double
    var direction: String       // "above" or "below"
    var isEnabled: Bool
    var isTriggered: Bool
    var triggeredAt: String?
    var createdAt: String?

    static let databaseTableName = "priceAlert"
}

/// Price data from WebSocket or CoinGecko REST
struct PriceUpdate: Sendable {
    let symbol: String          // CoinGecko ID: "bitcoin", "ethereum", etc.
    let price: Double
    var high24h: Double? = nil
    var low24h: Double? = nil
    var volume24h: Double? = nil
    var change24h: Double? = nil
    let timestamp: Date
    var sparklineData: [Double] = []  // Historical price points for chart
}
