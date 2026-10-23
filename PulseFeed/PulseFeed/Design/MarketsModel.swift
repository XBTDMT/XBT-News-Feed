import Foundation
import AppKit

/// One instrument as the markets strip / tiles / sidebar draw it.
struct MarketRow: Identifiable, Sendable {
    let id: String          // engine key: bitcoin, mag7, spy, gold, dxy, …
    let label: String       // BTC, MAG7, SPYx, Gold, USD idx, …
    let priceText: String
    let changeText: String?
    let isUp: Bool?
    let sparkline: [Double]
}

enum MarketsModel {
    /// The person's instruments, in their order, labelled for the provider that supplies them.
    static func rows(prices: [String: PriceUpdate], history: [String: [Double]],
                     instruments: [String], quotes: QuoteSource) -> [MarketRow] {
        instruments.compactMap { id in
            guard let p = prices[id] else { return nil }
            let label = MarketInstrument.label(id, quotes: quotes)
            return MarketRow(
                id: id, label: label,
                priceText: PriceFormatting.price(p.price, symbol: label),
                changeText: PriceFormatting.change(p.change24h),
                isUp: p.change24h.map { $0 >= 0 },
                sparkline: history[id] ?? [])
        }
    }

    /// What the views draw, from one read of the providers per render (the effective providers read the
    /// key files): this install's chosen instruments labelled for its effective quote provider, the rows
    /// that have a price, and the credit they owe.
    static func display(prices: [String: PriceUpdate], history: [String: [Double]]) -> MarketsDisplay {
        let providers = DataProviders.stored(.standard).effective(keys: .standard)
        let instruments = MarketInstrument.stored(.standard)
        return MarketsDisplay(
            rows: rows(prices: prices, history: history, instruments: instruments, quotes: providers.quotes),
            chosen: instruments.map { ($0, MarketInstrument.label($0, quotes: providers.quotes)) },
            providers: providers)
    }
}

/// One render's markets: the rows with a price, the chosen instruments (for layouts that hold places)
/// and the effective providers the credit is worked out from.
struct MarketsDisplay {
    let rows: [MarketRow]
    let chosen: [(id: String, label: String)]
    let providers: DataProviders

    /// The credit the drawn rows owe (`DataProviders.stripCredit`); nil when none is owed.
    var credit: String? { credit(for: rows.map(\.id)) }

    func credit(for instruments: [String]) -> String? {
        DataProviders.stripCredit(providers, instruments: instruments)
    }
}

/// Whether the price credit fits a row's free Spacer (ruling D9: it goes in free space, nothing moves).
/// The credit's width comes from its font, so the decision never waits on a measurement; the slot may
/// borrow from each of its two neighbour gaps down to 4pt (6pt of a 10pt gap, so 12 in all).
enum MarketsCreditFit {
    static let minGap: CGFloat = 4

    /// What a slot between two `neighbourGap` gaps may borrow in all.
    static func borrow(neighbourGap: CGFloat) -> CGFloat { 2 * max(0, neighbourGap - minGap) }

    static func fits(slot: CGFloat, credit: CGFloat, borrow: CGFloat = borrow(neighbourGap: 10)) -> Bool {
        credit <= slot + borrow
    }

    /// The width `text` draws at in `font`, rounded up to a whole point (SwiftUI lays text out on points).
    static func width(_ text: String, font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    /// Native Pro's popover header as `NativeProPopover.header` lays it out: 392pt inside the 420pt
    /// popover's 14pt insets, 10pt gaps, "Today" 15 bold, the unread badge (11 bold monospaced digits +
    /// 14 padding), "Updated …" at 11, the credit's slot, three 16pt glyphs. Returns the slot's width.
    static func nativeProHeaderSlot(badge: String?, updated: String?) -> CGFloat {
        var items = [width("Today", font: .systemFont(ofSize: 15, weight: .bold))]
        if let badge { items.append(width(badge, font: .monospacedDigitSystemFont(ofSize: 11, weight: .bold)) + 14) }
        if let updated { items.append(width(updated, font: .systemFont(ofSize: 11))) }
        let gaps = CGFloat(items.count + 3) * 10      // the items, the slot and three glyphs
        return max(0, 392 - items.reduce(0, +) - 3 * 16 - gaps)
    }
}
