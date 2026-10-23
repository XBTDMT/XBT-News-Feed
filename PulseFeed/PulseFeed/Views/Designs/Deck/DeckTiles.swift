import SwiftUI
import AppKit
import GRDB

// MARK: - Identity, navigation, shared chrome

/// The seven tiles. Only one is expanded at a time.
enum DeckTileID: Hashable {
    case breaking, markets, brief, unread, starred, saved, search

    /// The window section a ⌘-click on the tile opens.
    var windowSection: String {
        switch self {
        case .breaking, .unread: return "all"
        case .markets, .search: return "overview"
        case .brief: return "digest"
        case .starred: return "starred"
        case .saved: return "saved"
        }
    }
}

/// Hands a section from the popover to the window (a bar tap, a ⌘-click). The window consumes it
/// on appear or, when it is already open, on the next request.
@MainActor
@Observable
final class DeckNavigation {
    static let shared = DeckNavigation()
    private(set) var requestID = 0
    private var section: String?

    func request(_ section: String) {
        self.section = section
        requestID += 1
    }

    func consume() -> String? {
        defer { section = nil }
        return section
    }
}

/// What every tile needs from the popover.
struct DeckTileContext {
    let appDB: AppDatabase
    let expanded: Binding<DeckTileID?>
    let openWindow: (String) -> Void
    let lastLooked: Date?
    let tick: Bool

    func isExpanded(_ id: DeckTileID) -> Bool { expanded.wrappedValue == id }

    func collapse() {
        withAnimation(.easeInOut(duration: 0.2)) { expanded.wrappedValue = nil }
    }
}

/// The R2-Deck-B sheet's colours. Light values are the sheet's hexes; dark values are the nearest
/// system greys so the design still reads when the appearance is switched.
enum DeckPalette {
    static let canvas = Color(light: "#F2F2F7", dark: "#1C1C1E")
    static let card = Color(light: "#FFFFFF", dark: "#2C2C2E")
    static let text = Color(light: "#1D1D1F", dark: "#F5F5F7")
    static let body = Color(light: "#3A3A3C", dark: "#D1D1D6")
    static let secondary = Color(light: "#6E6E73", dark: "#98989D")
    static let tertiary = Color(light: "#8E8E93", dark: "#8E8E93")
    static let quaternary = Color(light: "#AEAEB2", dark: "#636366")
    static let chevron = Color(light: "#C7C7CC", dark: "#48484A")
    static let chevronExpanded = Color(light: "#AEAEB2", dark: "#636366")
    /// The 1px rule between rows inside a tile.
    static let rule = Color(light: "#F2F2F7", dark: "#3A3A3C")
    /// The 1px rule between list rows and pane borders in the window.
    static let listRule = Color(light: "#E5E5EA", dark: "#3A3A3C")
    static let fieldFill = Color(light: "#F2F2F7", dark: "#2C2C2E")
    static let band = Color(light: "#FAFAFC", dark: "#232325")
    static let selectedRow = Color(light: "#EAF2FF", dark: "#1F2A3A")
    static let chipFill = Color(light: "#E5E5EA", dark: "#3A3A3C")
    static let accent = Color(hex: "#0A84FF")
    static let red = Color(hex: "#FF3B30")
    static let green = Color(hex: "#34C759")
    static let gold = Color(hex: "#FFCC00")
    static let sun = Color(hex: "#E0A800")
    static let amber = Color(hex: "#FF9F0A")
    static let upText = Color(light: "#1E8E3E", dark: "#30D158")
    static let downText = Color(light: "#D93025", dark: "#FF453A")
    static let amberText = Color(light: "#B25E00", dark: "#FFB340")
    static let importantText = Color(light: "#B7950B", dark: "#FFD60A")
}

/// Card surface as the sheet draws it: white, 12pt radius, a half-point hairline at 8% black and a
/// 1pt soft shadow; expanded tiles lift to a 14pt shadow and a 10% hairline.
private struct DeckTileChrome: ViewModifier {
    let isExpanded: Bool
    var verticalPadding: CGFloat = 12

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12)
        content
            .padding(.horizontal, 12)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(DeckPalette.card, in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.black.opacity(isExpanded ? 0.10 : 0.08), lineWidth: 0.5))
            .shadow(color: .black.opacity(isExpanded ? 0.08 : 0.04), radius: isExpanded ? 7 : 1, y: isExpanded ? 4 : 1)
    }
}

/// Tap toggles the tile; ⌘-click opens the window on the tile's section. Buttons inside the tile
/// (stars, bars, chips) win over this gesture, so they never toggle it.
private struct DeckTapModifier: ViewModifier {
    let id: DeckTileID
    @Binding var expanded: DeckTileID?
    let enabled: Bool
    let openWindow: (String) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content
                .contentShape(Rectangle())
                .onTapGesture {
                    if NSEvent.modifierFlags.contains(.command) {
                        openWindow(id.windowSection)
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            expanded = (expanded == id) ? nil : id
                        }
                    }
                }
        } else {
            content
        }
    }
}

extension View {
    func deckChrome(isExpanded: Bool, verticalPadding: CGFloat = 12) -> some View {
        modifier(DeckTileChrome(isExpanded: isExpanded, verticalPadding: verticalPadding))
    }

    func deckTap(_ id: DeckTileID, ctx: DeckTileContext, enabled: Bool = true) -> some View {
        modifier(DeckTapModifier(id: id, expanded: ctx.expanded, enabled: enabled, openWindow: ctx.openWindow))
    }
}

/// "● Breaking · 2 ⌄" — the 11pt semibold title row every big tile starts with.
struct DeckTileHeader<Leading: View, Trailing: View>: View {
    let title: String
    var color: Color = DeckPalette.secondary
    let isExpanded: Bool
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 6) {
            leading()
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
            Spacer(minLength: 4)
            trailing()
            DeckChevron(isExpanded: isExpanded)
        }
        .frame(height: 16)
    }
}

extension DeckTileHeader where Leading == EmptyView {
    init(title: String, color: Color = DeckPalette.secondary, isExpanded: Bool, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.init(title: title, color: color, isExpanded: isExpanded, leading: { EmptyView() }, trailing: { trailing() })
    }
}

/// 6pt status dot (breaking red, important gold, tier green).
struct DeckDot: View {
    let color: Color
    var body: some View { Circle().fill(color).frame(width: 6, height: 6) }
}

struct DeckChevron: View {
    let isExpanded: Bool

    var body: some View {
        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(isExpanded ? DeckPalette.chevronExpanded : DeckPalette.chevron)
    }
}

/// The 1px rule between stories inside a tile.
struct DeckRule: View {
    var color: Color = DeckPalette.rule
    var body: some View { color.frame(height: 1) }
}

/// A line-only sparkline (the sheet draws no fill under it), normalised to its frame.
struct DeckSparkline: View {
    let data: [Double]
    let color: Color
    var lineWidth: CGFloat = 1.6

    var body: some View {
        GeometryReader { geo in
            if data.count >= 2, let lo = data.min(), let hi = data.max() {
                let range = max(hi - lo, 0.000_001)
                let inset = lineWidth / 2
                let w = geo.size.width, h = geo.size.height - lineWidth
                Path { path in
                    for (i, v) in data.enumerated() {
                        let x = w * CGFloat(i) / CGFloat(data.count - 1)
                        let y = inset + h - h * CGFloat((v - lo) / range)
                        if i == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

/// Idea ① inside a tile: "Since last looked · 4 new" in accent, then a 1px 35% accent line.
struct DeckSinceDivider: View {
    let newCount: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(DeckLayout.sinceDividerText(newCount: newCount))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DeckPalette.accent)
                .lineLimit(1)
                .fixedSize()
            DeckPalette.accent.opacity(0.35).frame(height: 1)
        }
        .frame(height: 16)
    }
}

/// "+1.8%" on a tinted capsule: green text on green, red on red, grey when unknown.
struct DeckChangeCapsule: View {
    let text: String
    let isUp: Bool?

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(DeckPalette.changeText(isUp))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(DeckPalette.changeFill(isUp).opacity(0.16), in: Capsule())
            .lineLimit(1)
            .fixedSize()
    }
}

extension DeckPalette {
    static func changeText(_ isUp: Bool?) -> Color {
        guard let isUp else { return tertiary }
        return isUp ? upText : downText
    }

    static func changeFill(_ isUp: Bool?) -> Color {
        guard let isUp else { return tertiary }
        return isUp ? green : red
    }

    /// The sheet's mood chip: amber for "cautious"/mixed, green for a positive mood, red for a
    /// negative one.
    static func moodColors(_ mood: String) -> (text: Color, fill: Color) {
        let m = mood.lowercased()
        if m.contains("bull") || m.contains("positive") || m.contains("risk-on") || m.contains("optimis") {
            return (upText, green.opacity(0.16))
        }
        if m.contains("bear") || m.contains("negative") || m.contains("risk-off") || m.contains("fear") {
            return (downText, red.opacity(0.16))
        }
        return (amberText, amber.opacity(0.18))
    }
}

/// "cautious" — 11pt semibold on a tinted capsule.
struct DeckMoodChip: View {
    let mood: String

    var body: some View {
        let colors = DeckPalette.moodColors(mood)
        Text(mood)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(colors.text)
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .background(colors.fill, in: Capsule())
            .lineLimit(1)
    }
}

// MARK: - Strip

/// A row-mate drawn header-only under the expanded tile: title, its headline number, the chevron.
/// Tapping it swaps the expansion to this tile.
struct DeckStripTile<Leading: View, Headline: View>: View {
    let id: DeckTileID
    let title: String
    var color: Color = DeckPalette.secondary
    let ctx: DeckTileContext
    /// Markets only: the price credit, inline between the title and the headline (on the Spacer, so
    /// nothing moves). Only a strip too narrow for it puts it on a 10pt line under the row instead,
    /// in the same 44pt with tighter padding.
    var credit: String? = nil
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let headline: () -> Headline

    @State private var creditFits = true
    private var creditBelow: String? { creditFits ? nil : credit }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                leading()
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                    .lineLimit(1)
                MarketsCreditSlot(credit: credit, minLength: 4, neighbourGap: 6, alignment: .leading, color: DeckPalette.tertiary,
                                  fits: $creditFits)
                headline()
                DeckChevron(isExpanded: false)
            }
            .frame(height: 20)
            if let creditBelow {
                MarketsCredit(text: creditBelow, font: .system(size: 10), color: DeckPalette.tertiary)
                    .frame(height: 13)
            }
        }
        .deckChrome(isExpanded: false, verticalPadding: creditBelow == nil ? 12 : 5)
        .frame(height: DeckLayout.stripHeight)
        .deckTap(id, ctx: ctx)
    }
}

// MARK: - Compact row

/// The row inside an expanded tile, as the sheet draws it at full width: one meta line (dot,
/// "Source · 4m" left; star and bookmark right), the title on at most two lines, then the chips.
struct DeckCompactRow: View {
    let article: ArticleInfo
    let appDB: AppDatabase
    var tick: Bool = false
    var showsPriority = true

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                if showsPriority, let color = priorityColor {
                    DeckDot(color: color)
                }
                Text("\(article.feedTitle) · \(article.dateArrived.relativeTime)")
                    .font(.system(size: 11))
                    .foregroundStyle(DeckPalette.tertiary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Button {
                    Task { try? await appDB.toggleStarred(article.articleID) }
                } label: {
                    Image(systemName: article.isStarred == true ? "star.fill" : "star")
                        .font(.system(size: 11))
                        .foregroundStyle(article.isStarred == true ? DeckPalette.gold : DeckPalette.quaternary)
                }
                .buttonStyle(.plain)
                .help(article.isStarred == true ? "Unstar" : "Star")
                Button {
                    Task { try? await appDB.toggleSaved(article.articleID) }
                } label: {
                    Image(systemName: article.isSaved == true ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 11))
                        .foregroundStyle(article.isSaved == true ? DeckPalette.accent : DeckPalette.quaternary)
                }
                .buttonStyle(.plain)
                .help(article.isSaved == true ? "Remove from Saved" : "Save")
                Button {
                    Task { try? await appDB.dismiss(articleID: article.articleID, log: EngagementStudy.isEnabled(.standard)) }
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(DeckPalette.quaternary)
                }
                .buttonStyle(.plain)
                .help("Not interested")
                .accessibilityLabel("Not interested")
            }
            .frame(height: 14)
            Text(article.title ?? "Untitled")
                .font(.system(size: 12.5, weight: article.isRead == true ? .regular : .semibold))
                .lineSpacing(1.5)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if article.sourceCount > 1 {
                SourceChips(article: article, appDB: appDB)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .onAppear { EngagementLog.shared.shown(article.articleID) }
    }

    private var priorityColor: Color? {
        switch article.priority {
        case "breaking": return DeckPalette.red
        case "important": return DeckPalette.gold
        default: return nil
        }
    }

    private func open() {
        if let urlString = article.url, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
        Task { try? await appDB.markRead(article.articleID) }
    }
}

// MARK: - Breaking

/// Red dot, "Breaking", the unread breaking count. Collapsed (half width): the first two stories as
/// source line + title. Expanded (full width): the "Since last looked · N new" divider, every
/// breaking then important story as compact rows, and "N breaking · N important".
struct DeckBreakingTile: View {
    /// Unread breaking stories first, then important; newest-first inside each.
    let stories: [ArticleInfo]
    let breakingCount: Int
    let ctx: DeckTileContext
    /// Drawn as the header-only strip under another expanded tile.
    var strip = false

    private var isExpanded: Bool { ctx.isExpanded(.breaking) }

    private var split: SinceLastLooked.Partition<ArticleInfo> {
        SinceLastLooked.partition(stories, arrival: { $0.arrivalDate }, lastLooked: ctx.lastLooked)
    }

    private var height: CGFloat {
        guard isExpanded else { return DeckLayout.tileHeight }
        // The collapsed tile already holds two stories; each further row adds one row height.
        return DeckLayout.expandedHeight(
            collapsed: DeckLayout.tileHeight, contentRows: stories.count - 1, rowHeight: 64, cap: DeckLayout.expandedCap)
    }

    private var count: some View {
        Text("\(breakingCount)")
            .font(.system(size: 15, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(DeckPalette.red)
    }

    var body: some View {
        if strip {
            DeckStripTile(id: .breaking, title: "Breaking", color: DeckPalette.red, ctx: ctx) {
                DeckDot(color: DeckPalette.red)
            } headline: {
                count
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                DeckTileHeader(title: "Breaking", color: DeckPalette.red, isExpanded: isExpanded) {
                    DeckDot(color: DeckPalette.red)
                } trailing: {
                    count
                }
                .deckTap(.breaking, ctx: ctx)

                if isExpanded {
                    expandedBody
                } else {
                    collapsedBody
                }
            }
            .deckChrome(isExpanded: isExpanded)
            .frame(height: height)
            .deckTap(.breaking, ctx: ctx, enabled: !isExpanded)
        }
    }

    @ViewBuilder
    private var collapsedBody: some View {
        if let first = stories.first {
            storyBlock(first, titleLines: 2, chips: true)
                .layoutPriority(1)
            if stories.count > 1 {
                DeckRule()
                storyBlock(stories[1], titleLines: 2, chips: false)
            }
        } else {
            Text("No breaking stories unread")
                .font(.system(size: 12))
                .foregroundStyle(DeckPalette.tertiary)
        }
        Spacer(minLength: 0)
        newSinceLine
    }

    /// Source line, title, chips — the sheet's story anatomy without the row actions.
    private func storyBlock(_ story: ArticleInfo, titleLines: Int, chips: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                DeckDot(color: dotColor(story))
                Text("\(story.feedTitle) · \(story.dateArrived.relativeTime)")
                    .font(.system(size: 11))
                    .foregroundStyle(DeckPalette.tertiary)
                    .lineLimit(1)
            }
            Text(story.title ?? "Untitled")
                .font(.system(size: 12.5, weight: .semibold))
                .lineSpacing(1.5)
                .lineLimit(titleLines)
            if chips, story.sourceCount > 1 {
                SourceChips(article: story, appDB: ctx.appDB)
            }
        }
    }

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !split.new.isEmpty {
                        DeckSinceDivider(newCount: split.newCount)
                    }
                    ForEach(Array(stories.enumerated()), id: \.element.id) { index, story in
                        if index > 0 { DeckRule() }
                        DeckCompactRow(article: story, appDB: ctx.appDB, tick: ctx.tick)
                    }
                    if stories.isEmpty {
                        Text("No breaking or important stories unread")
                            .font(.system(size: 12))
                            .foregroundStyle(DeckPalette.tertiary)
                            .padding(.vertical, 8)
                    }
                }
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 5) {
                DeckDot(color: DeckPalette.red)
                Text("\(stories.filter { $0.priority == "breaking" }.count) breaking")
                DeckDot(color: DeckPalette.gold).padding(.leading, 4)
                Text("\(stories.filter { $0.priority == "important" }.count) important")
            }
            .font(.system(size: 11))
            .foregroundStyle(DeckPalette.tertiary)
            .lineLimit(1)
        }
    }

    private var newSinceLine: some View {
        Text(DeckLayout.newSinceText(newCount: split.newCount, lastLooked: ctx.lastLooked))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(DeckPalette.accent)
            .lineLimit(1)
    }

    private func dotColor(_ story: ArticleInfo) -> Color {
        story.priority == "breaking" ? DeckPalette.red : DeckPalette.gold
    }
}

// MARK: - Markets

/// BTC large with its change capsule and a line sparkline; expanded (full width) adds the other four
/// instruments as 26pt rows; the caption says how live the quotes are on the current power tier, and
/// the price credit (10pt) names what the prices on show owe: under the caption at half width, at the
/// caption row's right once expanded.
/// "BTC" sits in the header so a six-digit price and the capsule fit at half width.
struct DeckMarketsTile: View {
    let rows: [MarketRow]
    /// The effective providers the rows came from (`MarketsDisplay.providers`), for the credit.
    let providers: DataProviders
    let tier: PowerTier
    let ctx: DeckTileContext
    var strip = false

    private var isExpanded: Bool { ctx.isExpanded(.markets) }
    /// Expanded (full width), the credit rides at the right of the caption row when it fits there.
    @State private var creditInCaption = true
    /// The credit as its own 10pt line under the caption: always while collapsed (half width has no
    /// room beside the caption), and expanded only when the caption row cannot hold it.
    private var creditBelow: String? { isExpanded && creditInCaption ? nil : credit }
    /// BTC when we have it; otherwise whichever instrument arrived first (BTC lags on battery).
    private var lead: MarketRow? { rows.first { $0.id == "bitcoin" } ?? rows.first }
    private var others: [MarketRow] { rows.filter { $0.id != lead?.id } }

    private var height: CGFloat {
        guard isExpanded else { return DeckLayout.tileHeight }
        // A credit that falls back under the caption takes one more 16pt row.
        return DeckLayout.expandedHeight(
            collapsed: DeckLayout.tileHeight, contentRows: others.count + (creditBelow == nil ? 0 : 1), rowHeight: 16,
            cap: DeckLayout.expandedCap)
    }

    private var headerTrailing: some View {
        Text(lead.map { "\($0.label) · 24h" } ?? "24h")
            .font(.system(size: 11))
            .foregroundStyle(DeckPalette.secondary)
            .lineLimit(1)
    }

    /// The credit the prices on show owe: the lead's while collapsed, every row's once expanded.
    private var credit: String? {
        DataProviders.stripCredit(providers, instruments: isExpanded ? rows.map(\.id) : lead.map { [$0.id] } ?? [])
    }

    var body: some View {
        if strip {
            DeckStripTile(id: .markets, title: "Markets", ctx: ctx, credit: credit) {
                EmptyView()
            } headline: {
                if let lead {
                    HStack(spacing: 6) {
                        Text(lead.priceText).font(.system(size: 13, weight: .bold)).monospacedDigit().lineLimit(1)
                        if let change = lead.changeText {
                            DeckChangeCapsule(text: change, isUp: lead.isUp)
                        }
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                DeckTileHeader(title: "Markets", isExpanded: isExpanded) { headerTrailing }
                    .deckTap(.markets, ctx: ctx)

                if let lead {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(lead.priceText)
                            .font(.system(size: 20, weight: .bold))
                            .tracking(-0.4)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if let change = lead.changeText {
                            DeckChangeCapsule(text: change, isUp: lead.isUp)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 2)
                    DeckSparkline(data: lead.sparkline, color: DeckPalette.changeFill(lead.isUp), lineWidth: 1.6)
                        .frame(minHeight: 22, maxHeight: .infinity)
                        .padding(.vertical, 2)
                } else {
                    Text(MarketInstrument.stored(.standard).isEmpty ? "No prices chosen · Settings › Power" : "Waiting for quotes")
                        .font(.system(size: 12))
                        .foregroundStyle(DeckPalette.tertiary)
                    Spacer(minLength: 0)
                }

                if isExpanded {
                    DeckRule().padding(.vertical, 2)
                    ForEach(others) { row in instrumentRow(row) }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 5) {
                    DeckDot(color: tierColor)
                    Text(caption)
                        .font(.system(size: 11))
                        .foregroundStyle(DeckPalette.tertiary)
                        .lineLimit(1)
                    if isExpanded {
                        MarketsCreditSlot(credit: credit, minLength: 8, neighbourGap: 5, color: DeckPalette.tertiary,
                                          fits: $creditInCaption)
                    }
                }
                if let creditBelow {
                    MarketsCredit(text: creditBelow, font: .system(size: 10), color: DeckPalette.tertiary)
                }
            }
            .deckChrome(isExpanded: isExpanded)
            .frame(height: height)
            .deckTap(.markets, ctx: ctx, enabled: !isExpanded)
        }
    }

    /// "MAG7 ~~~ $69.44 / −1.41%" — label 36pt, the sparkline takes the middle, price column right.
    private func instrumentRow(_ row: MarketRow) -> some View {
        HStack(spacing: 6) {
            Text(row.label)
                .font(.system(size: 11, weight: .bold))
                .lineLimit(1)
                .frame(width: 40, alignment: .leading)
            DeckSparkline(data: row.sparkline, color: DeckPalette.changeFill(row.isUp), lineWidth: 1.4)
                .frame(height: 14)
                .frame(maxWidth: .infinity)
            VStack(alignment: .trailing, spacing: 0) {
                Text(row.priceText).font(.system(size: 11, weight: .semibold)).monospacedDigit()
                if let change = row.changeText {
                    Text(change).font(.system(size: 11)).monospacedDigit().foregroundStyle(DeckPalette.changeText(row.isUp))
                }
            }
            .lineLimit(1)
            .fixedSize()
            .frame(minWidth: 48, alignment: .trailing)
        }
        .frame(height: 26)
    }

    private var caption: String {
        switch tier {
        case .ac: return "Live on AC · 5 min quotes"
        case .battery: return "On battery · 30 min quotes"
        case .critical: return "Low battery · quotes paused"
        }
    }

    private var tierColor: Color {
        switch tier {
        case .ac: return DeckPalette.green
        case .battery: return DeckPalette.gold
        case .critical: return DeckPalette.red
        }
    }
}

// MARK: - Brief

/// Sun, "Brief", the mood chip. Collapsed: the summary on four lines and "N stories · engine".
/// Expanded: the full brief. A nil digest asks the engine for one and says so.
struct DeckBriefTile: View {
    let digest: DailyDigest?
    let ctx: DeckTileContext
    let onStory: (DigestStory) -> Void
    let onGenerate: () -> Void
    /// Clears the brief and every unread story with it.
    var onClear: (() -> Void)? = nil
    var strip = false

    private var isExpanded: Bool { ctx.isExpanded(.brief) }

    private var height: CGFloat {
        guard isExpanded else { return DeckLayout.tileHeight }
        let rows = digest.map { $0.topStories.count + $0.whatToWatch.count + 2 } ?? 1
        return DeckLayout.expandedHeight(
            collapsed: DeckLayout.tileHeight, contentRows: rows, rowHeight: 40, cap: DeckLayout.expandedCap)
    }

    private var sun: some View {
        Image(systemName: "sun.max")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(DeckPalette.sun)
    }

    @ViewBuilder
    private var moodChip: some View {
        if let mood = digest?.marketMood, !mood.isEmpty {
            DeckMoodChip(mood: mood)
        }
    }

    var body: some View {
        if strip {
            DeckStripTile(id: .brief, title: "Brief", ctx: ctx) { sun } headline: { moodChip }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                DeckTileHeader(title: "Brief", isExpanded: isExpanded) { sun } trailing: { moodChip }
                    .deckTap(.brief, ctx: ctx)

                if let digest {
                    if isExpanded {
                        ScrollView {
                            BriefCard(digest: digest, mode: .full, onStory: onStory, onGenerate: onGenerate,
                                      onClear: onClear)
                                .padding(.trailing, 2)
                        }
                        .frame(maxHeight: .infinity)
                    } else {
                        Text(digest.summary)
                            .font(.system(size: 12))
                            .lineSpacing(2)
                            .lineLimit(4)
                        Spacer(minLength: 0)
                        Text("\(digest.topStories.count) stories · \(digest.isFallback ? "basic brief" : "AI")")
                            .font(.system(size: 11))
                            .foregroundStyle(DeckPalette.tertiary)
                            .lineLimit(1)
                    }
                } else {
                    Spacer(minLength: 0)
                    VStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Generating brief…").font(.system(size: 11)).foregroundStyle(DeckPalette.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    Spacer(minLength: 0)
                }
            }
            .deckChrome(isExpanded: isExpanded)
            .frame(height: height)
            .deckTap(.brief, ctx: ctx, enabled: !isExpanded)
            .task { if digest == nil { onGenerate() } }
        }
    }
}

// MARK: - Unread

/// Total unread, six category bars with counts, "N new since HH:mm". A bar opens the window on
/// that category; expanded (full width) keeps the bars and adds the six as labelled rows.
struct DeckUnreadTile: View {
    let byCategory: [String: Int]
    let total: Int
    let newCount: Int
    let ctx: DeckTileContext
    var strip = false
    /// The categories that are switched on (registry order).
    var categories: [DeckCategory] = DeckLayout.categories

    private var isExpanded: Bool { ctx.isExpanded(.unread) }
    /// Six bars fit the tile; the expanded rows list every switched-on category.
    private var barCategories: [DeckCategory] { DeckLayout.top(categories, counts: byCategory) }

    private var height: CGFloat {
        guard isExpanded else { return DeckLayout.tileHeight }
        return DeckLayout.expandedHeight(
            collapsed: DeckLayout.tileHeight, contentRows: categories.count, rowHeight: 18, cap: DeckLayout.expandedCap)
    }

    private var totalText: some View {
        Text("\(total)").font(.system(size: 15, weight: .bold)).monospacedDigit().foregroundStyle(DeckPalette.text)
    }

    var body: some View {
        if strip {
            DeckStripTile(id: .unread, title: "Unread", ctx: ctx) { EmptyView() } headline: { totalText }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                DeckTileHeader(title: "Unread", isExpanded: isExpanded) { totalText }
                    .deckTap(.unread, ctx: ctx)

                Spacer(minLength: 0)
                let counts = barCategories.map { byCategory[$0.tag] ?? 0 }
                bars(counts: counts, maxHeight: isExpanded ? 44 : 64)
                HStack(spacing: 6) {
                    ForEach(Array(counts.enumerated()), id: \.offset) { _, n in
                        Text(CompactCount.format(n))
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(DeckPalette.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }

                if isExpanded {
                    DeckRule().padding(.vertical, 2)
                    ForEach(categories) { cat in categoryRow(cat, count: byCategory[cat.tag] ?? 0) }
                }

                Text(DeckLayout.newSinceText(newCount: newCount, lastLooked: ctx.lastLooked))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DeckPalette.accent)
                    .lineLimit(1)
            }
            .deckChrome(isExpanded: isExpanded)
            .frame(height: height)
            .deckTap(.unread, ctx: ctx, enabled: !isExpanded)
        }
    }

    private func bars(counts: [Int], maxHeight: CGFloat) -> some View {
        let heights = DeckLayout.barHeights(counts: counts, maxHeight: maxHeight, floor: 3)
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(barCategories.enumerated()), id: \.element.id) { index, cat in
                Button {
                    ctx.openWindow(cat.tag)
                } label: {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: cat.colorHex).opacity(counts[index] > 0 ? 1 : 0.3))
                        .frame(maxWidth: .infinity)
                        .frame(height: heights[index])
                }
                .buttonStyle(.plain)
                .help("Open \(cat.label) in the window")
            }
        }
        .frame(height: maxHeight, alignment: .bottom)
    }

    private func categoryRow(_ cat: DeckCategory, count: Int) -> some View {
        Button {
            ctx.openWindow(cat.tag)
        } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(Color(hex: cat.colorHex)).frame(width: 8, height: 8)
                Text(cat.label).font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 4)
                Text("\(count)")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(DeckPalette.secondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(DeckPalette.chevron)
            }
            .frame(height: 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open \(cat.label) in the window")
    }
}

// MARK: - Small tiles

/// "★ 3 Starred" · "⊡ 12 Saved" · "⌕ Search 16,680" — the bottom row, collapsed. 10pt vertical
/// padding, a 16pt glyph, the number 15pt bold over an 11pt label.
struct DeckSmallTile: View {
    let id: DeckTileID
    let symbol: String
    let symbolColor: Color
    let primary: String
    let secondary: String
    /// True when `primary` is a number (15pt bold); false for the "Search" word (12pt semibold).
    var primaryIsValue = true
    let ctx: DeckTileContext

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: primaryIsValue ? .regular : .semibold))
                .foregroundStyle(symbolColor)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(primary)
                    .font(.system(size: primaryIsValue ? 15 : 12, weight: primaryIsValue ? .bold : .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                Text(secondary)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(DeckPalette.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .deckChrome(isExpanded: false, verticalPadding: 10)
        .frame(height: DeckLayout.smallTileHeight)
        .deckTap(id, ctx: ctx)
    }
}

/// A small tile as a strip beside its expanded row-mate: glyph, number and label on one line.
struct DeckSmallStrip: View {
    let id: DeckTileID
    let symbol: String
    let symbolColor: Color
    let primary: String
    let secondary: String
    let ctx: DeckTileContext

    var body: some View {
        DeckStripTile(id: id, title: secondary, ctx: ctx) {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(symbolColor).frame(width: 14)
        } headline: {
            Text(primary).font(.system(size: 13, weight: .bold)).monospacedDigit().lineLimit(1)
        }
    }
}

/// Starred or Saved, expanded across the row: the list as compact rows.
struct DeckListTile: View {
    let id: DeckTileID
    let symbol: String
    let symbolColor: Color
    let title: String
    let count: Int
    let ctx: DeckTileContext
    @State private var items: [ArticleInfo] = []

    private var category: String { id == .starred ? "starred" : "saved" }

    private var height: CGFloat {
        DeckLayout.expandedHeight(
            collapsed: DeckLayout.smallTileHeight, contentRows: max(items.count, 1), rowHeight: 64, cap: DeckLayout.expandedCap)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(symbolColor)
                Text("\(count) \(title)").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                Spacer(minLength: 4)
                DeckChevron(isExpanded: true)
            }
            .frame(height: 16)
            .deckTap(id, ctx: ctx)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, article in
                        if index > 0 { DeckRule() }
                        DeckCompactRow(article: article, appDB: ctx.appDB, tick: ctx.tick, showsPriority: false)
                    }
                    if items.isEmpty {
                        Text("Nothing \(title.lowercased()) yet")
                            .font(.system(size: 12))
                            .foregroundStyle(DeckPalette.tertiary)
                            .padding(.vertical, 8)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .deckChrome(isExpanded: true)
        .frame(height: height)
        .task(id: category) { await observe() }
    }

    private func observe() async {
        do {
            for try await rows in ArticleInfo.observation(category: category).values(in: ctx.appDB.dbPool) {
                items = rows
            }
        } catch {
            // Observation cancelled
        }
    }
}

/// Search, expanded across the row: the field bound to the shared model, results as compact rows,
/// then the web results the model fetches after three characters.
struct DeckSearchTile: View {
    @Bindable var model: FeedListModel
    let total: Int
    let ctx: DeckTileContext
    @FocusState private var focused: Bool

    private var isQuery: Bool { model.searchText.count >= 2 }

    private var height: CGFloat {
        let rows = isQuery ? model.displayed.count + model.webSearchResults.count : 0
        return DeckLayout.expandedHeight(
            collapsed: DeckLayout.smallTileHeight, contentRows: max(rows, 1), rowHeight: 64, cap: DeckLayout.expandedCap)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .semibold)).foregroundStyle(DeckPalette.text)
                TextField("Search \(total.formatted()) articles", text: $model.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($focused)
                if !model.searchText.isEmpty {
                    Button {
                        model.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(DeckPalette.quaternary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear")
                }
                Button {
                    ctx.collapse()
                } label: {
                    DeckChevron(isExpanded: true)
                }
                .buttonStyle(.plain)
                .help("Collapse")
            }
            .frame(height: 16)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !isQuery {
                        Text("Type at least 2 characters to search")
                            .font(.system(size: 11))
                            .foregroundStyle(DeckPalette.tertiary)
                            .padding(.vertical, 8)
                    } else if model.displayed.isEmpty, model.webSearchResults.isEmpty, !model.isSearchingWeb {
                        Text("No articles match \"\(model.searchText)\"")
                            .font(.system(size: 11))
                            .foregroundStyle(DeckPalette.tertiary)
                            .padding(.vertical, 8)
                    }
                    if isQuery {
                        ForEach(Array(model.displayed.enumerated()), id: \.element.id) { index, article in
                            if index > 0 { DeckRule() }
                            DeckCompactRow(article: article, appDB: ctx.appDB, tick: ctx.tick, showsPriority: false)
                        }
                        webResults
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .deckChrome(isExpanded: true)
        .frame(height: height)
        .onAppear { focused = true }
    }

    @ViewBuilder
    private var webResults: some View {
        if model.isSearchingWeb {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Searching the web\u{2026}").font(.system(size: 11)).foregroundStyle(DeckPalette.tertiary)
            }
            .padding(.vertical, 8)
        }
        if !model.webSearchResults.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: "globe").font(.system(size: 10))
                Text("Web Results").font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(DeckPalette.tertiary)
            .padding(.vertical, 6)
            ForEach(model.webSearchResults) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.system(size: 12)).lineLimit(2)
                    Text(item.source).font(.system(size: 11)).foregroundStyle(DeckPalette.tertiary)
                }
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    if let url = URL(string: item.url) { NSWorkspace.shared.open(url) }
                }
                DeckRule()
            }
        }
    }
}
