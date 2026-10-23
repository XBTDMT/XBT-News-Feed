import SwiftUI

struct PriceTickerView: View {
    let prices: [String: PriceUpdate]

    var body: some View {
        HStack(spacing: 6) {
            if let btc = prices["bitcoin"] {
                priceLabel("BTC", price: btc)
            }
            if let mag7 = prices["mag7"] {
                priceLabel("MAG7", price: mag7)
            }
            if let spy = prices["spy"] {
                priceLabel("SPY", price: spy)
            }
            if let gold = prices["gold"] {
                priceLabel("Gold", price: gold)
            }
            if let dxy = prices["dxy"] {
                priceLabel("DXY", price: dxy)
            }
        }
    }

    private func priceLabel(_ symbol: String, price: PriceUpdate) -> some View {
        HStack(spacing: 2) {
            Text(symbol)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(PriceFormatting.price(price.price, symbol: symbol))
                .font(.system(size: 11))
                .monospacedDigit()
            if let change = price.change24h {
                Text(String(format: "%+.1f%%", change))
                    .font(.system(size: 9))
                    .monospacedDigit()
                    .foregroundStyle(change >= 0 ? .green : .red)
            }
        }
    }

}
