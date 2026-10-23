import SwiftUI
import AppKit

/// Five instruments with sparklines. `.strip` = one grouped card with five columns (Native Pro);
/// `.cards` = five separate cards (Stream); `.rows` = vertical rows (Deck's expanded tile, sidebars).
struct MarketsStrip: View {
    enum Style { case strip, cards, rows }

    let rows: [MarketRow]
    var style: Style = .strip
    /// The price credit to draw under the instruments (`MarketsDisplay.credit`).
    var credit: String? = nil
    /// `.cards` only: a fixed card width (inside a horizontal ScrollView) instead of sharing the row.
    var cardWidth: CGFloat? = nil
    @Environment(\.designTokens) private var tokens

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            instruments
            if let credit {
                MarketsCredit(text: credit, font: tokens.font(10), color: tokens.secondaryText)
            }
        }
    }

    @ViewBuilder
    private var instruments: some View {
        switch style {
        case .strip:
            HStack(spacing: 0) {
                ForEach(rows) { row in
                    cell(row).frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 6)
            .background(tokens.card, in: RoundedRectangle(cornerRadius: tokens.radius))
        case .cards:
            HStack(spacing: 4) {
                ForEach(rows) { row in
                    cell(row)
                        .padding(.vertical, 8)
                        .frame(width: cardWidth)
                        .frame(maxWidth: cardWidth == nil ? .infinity : nil)
                        .background(tokens.card, in: RoundedRectangle(cornerRadius: tokens.radius))
                        .overlay(RoundedRectangle(cornerRadius: tokens.radius).stroke(tokens.cardBorder, lineWidth: 1))
                }
            }
        case .rows:
            VStack(spacing: 6) {
                ForEach(rows) { row in
                    HStack(spacing: 8) {
                        Text(row.label).font(tokens.font(11, weight: .bold)).fixedSize()
                            .frame(width: 42, alignment: .leading)
                        if row.sparkline.count >= 2 {
                            SparklineView(data: row.sparkline, color: color(row)).frame(maxWidth: 80).frame(height: 18)
                        } else {
                            Spacer()
                        }
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(row.priceText).font(tokens.font(11, weight: .semibold)).monospacedDigit()
                            if let change = row.changeText {
                                Text(change).font(tokens.font(10, weight: .semibold)).monospacedDigit().foregroundStyle(color(row))
                            }
                        }
                        .frame(width: 70, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func cell(_ row: MarketRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 2) {
                Text(row.label).font(tokens.font(10, weight: .bold)).foregroundStyle(tokens.secondaryText)
                    .lineLimit(1).fixedSize()
                Spacer(minLength: 2)
                if let change = row.changeText {
                    Text(change).font(tokens.font(10, weight: .semibold)).monospacedDigit().foregroundStyle(color(row))
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            Text(row.priceText).font(tokens.font(12, weight: .bold)).monospacedDigit().lineLimit(1)
            if row.sparkline.count >= 2 {
                SparklineView(data: row.sparkline, color: color(row)).frame(height: 14)
            } else {
                Color.clear.frame(height: 14)
            }
        }
        .padding(.horizontal, 5)
    }

    private func color(_ row: MarketRow) -> Color {
        guard let isUp = row.isUp else { return tokens.secondaryText }
        return isUp ? tokens.ok : tokens.breaking
    }
}

/// The credit the shown prices owe (`DataProviders.stripCredit`), drawn beside them in each design's own
/// caption font and colour: never under 10pt (CoinGecko's terms), "Powered by CoinGecko" a link to
/// coingecko.com. A `Link` rather than a link inside the text, so it wins over a tile's tap gesture.
struct MarketsCredit: View {
    let text: String
    var font: Font = .system(size: 10)
    var color: Color = .secondary

    var body: some View {
        let parts = Self.split(text)
        HStack(spacing: 0) {
            if !parts.before.isEmpty { Text(parts.before).lineLimit(1) }
            if parts.hasLink {
                Link(destination: DataProviders.coinGeckoURL) {
                    Text(DataProviders.coinGeckoCredit).underline()
                }
                .foregroundStyle(color)
                .tint(color)
                .fixedSize()
                .layoutPriority(1)
                .help("coingecko.com")
            }
            if !parts.after.isEmpty { Text(parts.after).lineLimit(1) }
        }
        .font(font)
        .foregroundStyle(color)
    }

    /// The text around the CoinGecko credit, which is the part that links.
    static func split(_ text: String) -> (before: String, hasLink: Bool, after: String) {
        guard let r = text.range(of: DataProviders.coinGeckoCredit) else { return (text, false, "") }
        return (String(text[..<r.lowerBound]), true, String(text[r.upperBound...]))
    }
}

/// A row's Spacer that also carries the price credit, so a header can hold it without anything moving:
/// the credit is an overlay (the row lays out exactly as with a bare Spacer) and shows while
/// `MarketsCreditFit.fits` says so: the credit's width comes from `measureFont` (the font it draws in),
/// the slot may borrow from each neighbour gap (`neighbourGap`, the row's spacing) down to 4pt. A
/// credit that needs the borrow is centred on the
/// slot; one that fits without it keeps `alignment`. `fits` reports back, so the caller can draw the
/// credit somewhere else when the row has no room.
struct MarketsCreditSlot: View {
    let credit: String?
    var minLength: CGFloat = 8
    /// The row's spacing on either side of the slot.
    var neighbourGap: CGFloat = 10
    var alignment: Alignment = .trailing
    var font: Font = .system(size: 10)
    var measureFont: NSFont = .systemFont(ofSize: 10)
    var color: Color = .secondary
    @Binding var fits: Bool

    /// The Spacer's laid-out width; nil until the first layout, when the credit is assumed to fit.
    @State private var slotWidth: CGFloat?

    private var creditWidth: CGFloat {
        credit.map { MarketsCreditFit.width($0, font: measureFont) } ?? 0
    }

    private var shows: Bool {
        guard credit != nil else { return false }
        let borrow = MarketsCreditFit.borrow(neighbourGap: neighbourGap)
        return slotWidth.map { MarketsCreditFit.fits(slot: $0, credit: creditWidth, borrow: borrow) } ?? true
    }

    var body: some View {
        Spacer(minLength: minLength)
            .overlay {
                if let credit {
                    MarketsCredit(text: credit, font: font, color: color)
                        .fixedSize()
                        .frame(width: slotWidth.map { max($0, creditWidth) }, alignment: alignment)
                        .opacity(shows ? 1 : 0)
                        .allowsHitTesting(shows)
                        .accessibilityHidden(!shows)
                }
            }
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onAppear { slotWidth = geo.size.width }
                        .onChange(of: geo.size.width) { _, w in slotWidth = w }
                }
            }
            .onChange(of: shows, initial: true) { _, now in
                if fits != now { fits = now }
            }
    }
}
