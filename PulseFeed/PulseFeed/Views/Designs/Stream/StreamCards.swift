import SwiftUI
import AppKit

// Stream (R4-Stream-B): the pieces every Stream surface composes, drawn to the sheet's pixel
// values, with the picture made the dominant element (2026-09-07): the lead carries a 16:9
// picture, up to two multi-source stories with a picture become 150pt picture cards, 3-source
// clusters are cards with a 64pt thumbnail, and everything else is a row — 34pt bare, 76pt with
// its 64pt thumbnail on the trailing side — where consecutive rows share one card.

// MARK: - Palette

/// The sheet's ink and grey scale beyond the design tokens (ink #17181C, ink2 #3D4048, faint
/// #9AA0A8, idle icon #C5C9CF), plus the amber, purple and gradient constants it uses.
enum StreamPalette {
    static let ink = Color(light: "#17181C", dark: "#F1F2F4")
    static let ink2 = Color(light: "#3D4048", dark: "#C9CCD2")
    static let faint = Color(light: "#9AA0A8", dark: "#6B7079")
    static let iconIdle = Color(light: "#C5C9CF", dark: "#4A4F58")
    static let star = Color(hex: "#F2B01E")
    static let amberText = Color(light: "#8A6A05", dark: "#E8B931")
    static let amberFill = Color(hex: "#E8B931").opacity(0.22)
    static let summaryInk = Color(light: "#5E3BB0", dark: "#B9A3F0")
    static let summaryGlyph = Color(hex: "#8E5BE8")
    static let summaryFill = Color(hex: "#8E5BE8").opacity(0.08)
    static let scrim = Color(hex: "#17181C")

    static let heroGradient = LinearGradient(
        colors: [Color(hex: "#D9B4A6"), Color(hex: "#7A4A43")], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let thumbGradient = LinearGradient(
        colors: [Color(hex: "#C9CED8"), Color(hex: "#5E6879")], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let detailGradient = LinearGradient(
        colors: [Color(hex: "#C9D3E3"), Color(hex: "#5C6B85")], startPoint: .topLeading, endPoint: .bottomTrailing)
}

// MARK: - Layout

enum StreamBlock: Identifiable {
    case hero(ArticleInfo)
    /// A multi-source story with a picture, drawn as a shorter hero card (the popover's 150pt band).
    case picture(ArticleInfo)
    case cluster(ArticleInfo)
    case rows([ArticleInfo])

    var id: String {
        switch self {
        case .hero(let article): return "hero-" + article.articleID
        case .picture(let article): return "picture-" + article.articleID
        case .cluster(let article): return "cluster-" + article.articleID
        case .rows(let list): return "rows-" + (list.first?.articleID ?? "")
        }
    }

    var isHero: Bool {
        if case .hero = self { return true }
        return false
    }

    var isPicture: Bool {
        if case .picture = self { return true }
        return false
    }

    /// Hero and picture cards start with an image band, so the popover's chip capsule may overlap them.
    var isImageCard: Bool { isHero || isPicture }
}

enum StreamLayout {
    // MARK: Pictures

    /// The lead's picture is 16:9 of its card's width: 236pt at the popover's 420pt, 223pt at the
    /// 396pt card inside it, 270pt in a 480pt window column.
    static let pictureAspect: CGFloat = 16.0 / 9.0

    static func pictureHeight(width: CGFloat) -> CGFloat {
        (width / pictureAspect).rounded()
    }

    /// The non-lead picture card's band: shorter than the lead so the popover never becomes an image strip.
    static let pictureBandHeight: CGFloat = 150

    /// Beyond the lead, at most this many picture cards in the popover.
    static let popoverPictureBudget = 2

    /// A row's or story card's thumbnail is a 64pt rounded square on the trailing side.
    static let thumbnailSide: CGFloat = 64
    static let thumbnailInset: CGFloat = 6

    /// 34pt bare; a row carrying a thumbnail grows just enough to fit it (64 + 6 above and below).
    static func rowHeight(hasThumbnail: Bool) -> CGFloat {
        hasThumbnail ? thumbnailSide + 2 * thumbnailInset : 34
    }

    /// Whether the story has a picture a view can try to load: an absolute http(s) URL. A row without
    /// one keeps its bare layout rather than showing an empty box.
    static func hasPicture(_ article: ArticleInfo) -> Bool {
        guard let raw = article.imageURL, !raw.isEmpty, let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", url.host != nil
        else { return false }
        return true
    }

    // MARK: Blocks

    /// The lead: the newest unread BREAKING story; else the newest 3-source cluster; else the newest.
    static func hero(in articles: [ArticleInfo]) -> ArticleInfo? {
        if let breaking = articles.first(where: { $0.priority == "breaking" && $0.isRead != true }) {
            return breaking
        }
        if let cluster = articles.first(where: { $0.sourceCount >= 3 }) { return cluster }
        return articles.first
    }

    static func isCard(_ article: ArticleInfo, heroID: String?) -> Bool {
        article.articleID == heroID || article.sourceCount >= 3
    }

    /// Newest-first input; cards keep their place, rows between them are grouped. While
    /// `pictureBudget` lasts, a non-lead story carried by two or more outlets that has a picture
    /// becomes a picture card (the lead never spends it); past the budget a 3-source story is a
    /// cluster card and the rest are rows. Off (0) the blocks are the sheet's.
    static func blocks(
        _ articles: [ArticleInfo], heroID: String?, cardsAllowed: Bool, pictureBudget: Int = 0
    ) -> [StreamBlock] {
        var out: [StreamBlock] = []
        var pending: [ArticleInfo] = []
        var budget = pictureBudget
        func flush() {
            if !pending.isEmpty { out.append(.rows(pending)); pending = [] }
        }
        for article in articles {
            if cardsAllowed, article.articleID == heroID {
                flush()
                out.append(.hero(article))
            } else if cardsAllowed, budget > 0, article.sourceCount >= 2, hasPicture(article) {
                flush()
                out.append(.picture(article))
                budget -= 1
            } else if cardsAllowed, article.sourceCount >= 3 {
                flush()
                out.append(.cluster(article))
            } else {
                pending.append(article)
            }
        }
        flush()
        return out
    }

    /// How much of the budget a block list spent, so the section under the divider gets the rest.
    static func pictureCards(in blocks: [StreamBlock]) -> Int {
        blocks.filter(\.isPicture).count
    }
}

enum StreamText {
    /// The registry's label ("AI", "F1", "Cars & Bikes"); an id the registry lacks is capitalised.
    static func category(_ raw: String) -> String {
        NewsCategory.all.first { $0.id == raw.lowercased() }?.label ?? raw.capitalized
    }

    static func open(_ article: ArticleInfo) {
        if let urlString = article.url, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    /// The primary outlet first, then the others carrying the story.
    static func outlets(_ article: ArticleInfo) -> [String] {
        let others = (article.otherSources ?? "").components(separatedBy: ", ").filter { !$0.isEmpty }
        return [article.feedTitle] + others.filter { $0 != article.feedTitle }
    }

    static func others(_ article: ArticleInfo) -> [String] {
        Array(outlets(article).dropFirst())
    }

    /// The popover strip's compact price: "$109.8k", "$4,477", "$770", "$69.44", "99.16".
    static func compactPrice(_ value: Double, symbol: String) -> String {
        if symbol.uppercased() == "DXY" { return String(format: "%.2f", value) }
        if value >= 10_000 {
            let s = String(format: "%.1f", value / 1000)
            return "$" + (s.hasSuffix(".0") ? String(s.dropLast(2)) : s) + "k"
        }
        if value >= 1000 { return PriceFormatting.price(value, symbol: symbol) }
        if value >= 100 { return "$\(Int(value.rounded()))" }
        if value >= 1 { return String(format: "$%.2f", value) }
        return String(format: "$%.4f", value)
    }

    /// "+1.8%" / "−1.4%" with a true minus sign; nil when unknown.
    static func change(_ pct: Double?, decimals: Int = 1) -> String? {
        guard let pct else { return nil }
        let magnitude = String(format: "%.\(decimals)f%%", abs(pct))
        return (pct < 0 ? "\u{2212}" : "+") + magnitude
    }

    /// Below ±0.05% the sheet greys the change out.
    static func isFlat(_ pct: Double?) -> Bool {
        guard let pct else { return true }
        return abs(pct) < 0.05
    }

    /// "Since you last looked · 13:40 · 4 new", the sheet's order (time before count).
    static func dividerText(newCount: Int, lastLooked: Date?) -> String {
        var text = "Since you last looked"
        if let lastLooked {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            f.locale = Locale(identifier: "en_US_POSIX")
            text += " · " + f.string(from: lastLooked)
        }
        return text + " · \(newCount) new"
    }
}

// MARK: - Card chrome

struct StreamCardModifier: ViewModifier {
    var radius: CGFloat?
    var elevated = false
    @Environment(\.designTokens) private var tokens

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius ?? tokens.radius, style: .continuous)
        content
            .background(tokens.card, in: shape)
            .clipShape(shape)
            .overlay(shape.stroke(tokens.cardBorder, lineWidth: 1))
            .shadow(
                color: elevated ? StreamPalette.scrim.opacity(0.06) : .clear, radius: elevated ? 8 : 0, x: 0,
                y: elevated ? 6 : 0)
    }
}

extension View {
    /// White card with the sheet's 1pt ring (#E3E5E9) at the design radius (12) unless overridden;
    /// `elevated` adds the soft `0 6px 16px` shadow the lead and cluster cards carry.
    func streamCard(radius: CGFloat? = nil, elevated: Bool = false) -> some View {
        modifier(StreamCardModifier(radius: radius, elevated: elevated))
    }
}

/// The market sparkline as the sheet draws it: a line only, no fill.
struct StreamSparkline: Shape {
    let data: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard data.count >= 2, let lo = data.min(), let hi = data.max() else { return path }
        let range = hi - lo
        for (index, value) in data.enumerated() {
            let x = rect.minX + rect.width * CGFloat(index) / CGFloat(data.count - 1)
            let y = range > 0 ? rect.maxY - rect.height * CGFloat((value - lo) / range) : rect.midY
            if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }
}

// MARK: - Chips row

/// All · Brief · Crypto · Tech · Sports · F1 · Finance · World · Starred · Saved. The selected chip
/// is coral with white text, the rest bare. `.floating` is the popover's white capsule with a
/// border and a drop shadow (it overlaps the lead card); `.segmented` is the window toolbar's
/// canvas-coloured capsule.
struct StreamChipRow: View {
    enum Style { case floating, segmented }

    @Binding var selected: String
    var style: Style = .floating
    /// Categories that are switched on; the fixed chips (All, Brief, Starred, Saved) always show.
    var enabled: Set<String> = Set(NewsCategory.all.map(\.id))
    @Environment(\.designTokens) private var tokens

    private var tags: [(tag: String, label: String)] {
        [("all", "All"), ("digest", "Brief")]
            + NewsCategory.visible(enabledIDs: enabled).map { ($0.id, $0.label) }
            + [("starred", "Starred"), ("saved", "Saved")]
    }

    var body: some View {
        switch style {
        case .floating:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(tags, id: \.tag) { item in chip(item.tag, item.label) }
                }
            }
            .padding(3)
            .frame(height: 32)
            .background(tokens.card, in: Capsule())
            .clipShape(Capsule())
            .overlay(Capsule().stroke(tokens.cardBorder, lineWidth: 1))
            .shadow(color: StreamPalette.scrim.opacity(0.12), radius: 10, x: 0, y: 8)
        case .segmented:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(tags, id: \.tag) { item in chip(item.tag, item.label) }
                }
                .padding(3)
                .background(tokens.canvas, in: Capsule())
            }
        }
    }

    private func chip(_ tag: String, _ label: String) -> some View {
        let isSelected = tag == selected
        return Button {
            selected = tag
        } label: {
            HStack(spacing: 5) {
                if tag == "digest" {
                    Image(systemName: "sun.max")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isSelected ? Color.white : tokens.accent)
                }
                Text(label)
                    .font(tokens.font(12, weight: isSelected ? .bold : .semibold))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(isSelected ? Color.white : StreamPalette.ink)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(isSelected ? tokens.accent : Color.clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Small pieces

/// BREAKING (red) or IMPORTANT (amber); nothing otherwise. `.row` is the 12pt-tall pill inside a
/// meta line, `.medium` the window card's, `.card` the 18pt one on the lead image.
struct StreamPriorityPill: View {
    enum Size { case row, medium, card }

    let priority: String?
    var size: Size = .row
    @Environment(\.designTokens) private var tokens

    var body: some View {
        if priority == "breaking" {
            pill("BREAKING", foreground: .white, fill: tokens.breaking)
        } else if priority == "important" {
            pill("IMPORTANT", foreground: StreamPalette.amberText, fill: StreamPalette.amberFill)
        }
    }

    private func pill(_ text: String, foreground: Color, fill: Color) -> some View {
        let height: CGFloat = size == .card ? 18 : (size == .medium ? 15 : 12)
        let radius: CGFloat = size == .card ? 5 : (size == .medium ? 4 : 3)
        return Text(text)
            .font(tokens.font(11, weight: .heavy))
            .tracking(size == .card ? 0.66 : 0.55)
            .foregroundStyle(foreground)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, size == .card ? 7 : 5)
            .frame(height: height)
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Idea ②, as the sheet draws it: the primary and other outlets as overlapping white pills with a
/// coral ring ("MS TR BBC"), then the count in a filled coral pill. Tapping opens Coverage. Renders
/// nothing for single-source stories.
struct StreamSourceChips: View {
    enum Size { case row, medium, card }

    let article: ArticleInfo
    let appDB: AppDatabase
    var size: Size = .row
    @Environment(\.designTokens) private var tokens
    @State private var showCoverage = false

    private var height: CGFloat { size == .card ? 18 : (size == .medium ? 16 : 12) }
    private var ring: CGFloat { size == .row ? 1 : 1.5 }
    private var overlap: CGFloat { size == .row ? 3 : 4 }

    var body: some View {
        if article.sourceCount > 1 {
            let names = StreamText.outlets(article)
            let monos = Monogram.assign(names)
            Button {
                showCoverage = true
            } label: {
                HStack(spacing: -overlap) {
                    ForEach(Array(names.prefix(3)), id: \.self) { name in
                        pill(monos[name] ?? Monogram.make(name), filled: false)
                    }
                    pill("\(article.sourceCount)", filled: true)
                }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Coverage: \(article.sourceCount) sources")
            .popover(isPresented: $showCoverage, arrowEdge: .bottom) {
                StreamCoveragePopover(article: article, appDB: appDB)
            }
        }
    }

    private func pill(_ text: String, filled: Bool) -> some View {
        Text(text)
            .font(tokens.font(11, weight: .heavy))
            .foregroundStyle(filled ? Color.white : tokens.accent)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, filled ? (size == .row ? 5 : 7) : (size == .row ? 4 : 5))
            .frame(height: height)
            .background(filled ? tokens.accent : tokens.card, in: Capsule())
            .overlay(Capsule().stroke(filled ? Color.clear : tokens.accent, lineWidth: ring))
    }
}

/// The learning week's "Not interested": an xmark.circle in the star's idle grey (white on an
/// image). A plain button, so the card's own tap stays the card's.
struct StreamNotInterestedButton: View {
    let article: ArticleInfo
    let appDB: AppDatabase
    var size: CGFloat = 12
    var onImage = false

    var body: some View {
        Button {
            Task { try? await appDB.dismiss(articleID: article.articleID, log: EngagementStudy.isEnabled(.standard)) }
        } label: {
            Image(systemName: "xmark.circle")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(onImage ? .white : StreamPalette.iconIdle)
                .frame(width: size + 4, height: size + 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Not interested")
        .accessibilityLabel("Not interested")
    }
}

/// Star, bookmark and "not interested" at 12pt: idle #C5C9CF (white on an image), starred
/// #F2B01E, saved coral.
struct StreamStarSaveButtons: View {
    let article: ArticleInfo
    let appDB: AppDatabase
    var size: CGFloat = 12
    var onImage = false
    @Environment(\.designTokens) private var tokens

    private var idle: Color { onImage ? .white : StreamPalette.iconIdle }

    var body: some View {
        HStack(spacing: 4) {
            Button {
                Task { try? await appDB.toggleStarred(article.articleID) }
            } label: {
                Image(systemName: article.isStarred == true ? "star.fill" : "star")
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(article.isStarred == true ? StreamPalette.star : idle)
                    .frame(width: size + 4, height: size + 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(article.isStarred == true ? "Unstar" : "Star")

            Button {
                Task { try? await appDB.toggleSaved(article.articleID) }
            } label: {
                Image(systemName: article.isSaved == true ? "bookmark.fill" : "bookmark")
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(article.isSaved == true ? tokens.accent : idle)
                    .frame(width: size + 4, height: size + 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(article.isSaved == true ? "Remove from Saved" : "Save")

            StreamNotInterestedButton(article: article, appDB: appDB, size: size, onImage: onImage)
        }
    }
}

/// "Source · IMPORTANT · chips N · Category · 19m" in 11pt. `compact` is the 12pt-tall row form;
/// otherwise the window card's 17pt line with medium pills.
struct StreamMetaLine: View {
    let article: ArticleInfo
    let appDB: AppDatabase
    var showPriority = true
    var showTime = true
    var dimmed = false
    var compact = true
    /// Flipped by the owning list so relative times re-render; never read, only compared.
    var tick = false
    @Environment(\.designTokens) private var tokens

    var body: some View {
        HStack(spacing: 6) {
            Text(article.feedTitle)
                .font(tokens.font(11, weight: .bold))
                .foregroundStyle(dimmed ? StreamPalette.ink2 : StreamPalette.ink)
                .lineLimit(1)
            if showPriority {
                StreamPriorityPill(priority: article.priority, size: compact ? .row : .medium)
            }
            StreamSourceChips(article: article, appDB: appDB, size: compact ? .row : .medium)
            Text("· " + StreamText.category(article.feedCategory))
                .font(tokens.font(11))
                .foregroundStyle(StreamPalette.faint)
                .lineLimit(1)
            if showTime {
                Spacer(minLength: 4)
                Text(article.dateArrived.relativeTime)
                    .font(tokens.font(11))
                    .monospacedDigit()
                    .foregroundStyle(StreamPalette.faint)
            }
        }
        .frame(height: compact ? 12 : 17)
    }
}

// MARK: - Hero card

/// The lead. Its picture fills the card's width at 16:9 (`StreamLayout.pictureAspect`); a story
/// without one keeps the sheet's short gradient band (140pt popover, 120pt window), and a caller
/// may pin a `bandHeight` instead (the popover's 150pt picture card, the window's cluster cards).
/// `.popover`: the source with star and bookmark on one line and the priority pill, coverage
/// chips, category and time pills on the next, both on the image's bottom edge; the title below in
/// 14pt heavy. `.window`: the image carries only the pills, then title, source, other outlets and
/// star/bookmark below.
struct StreamHeroCard: View {
    enum Variant { case popover, window }

    let article: ArticleInfo
    let appDB: AppDatabase
    var variant: Variant = .popover
    /// Whether the policy allows this card an image at all (the caller applies `ImageGate`).
    var showImage: Bool
    /// The lead's placeholder is the sheet's rose-to-umber gradient; a cluster card's is slate.
    var isLead = true
    /// A fixed image height; nil draws the picture at 16:9 of the card's width.
    var bandHeight: CGFloat? = nil
    var tick = false
    let onOpen: () -> Void
    @Environment(\.designTokens) private var tokens

    private var showsPicture: Bool { showImage && StreamLayout.hasPicture(article) }
    private var placeholderHeight: CGFloat { variant == .popover ? 140 : 120 }
    private var placeholder: LinearGradient { isLead ? StreamPalette.heroGradient : StreamPalette.thumbGradient }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            imageBlock
            if variant == .popover {
                Text(article.title ?? "Untitled")
                    .font(tokens.font(14, weight: .heavy))
                    .tracking(-0.14)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(minHeight: 47)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(article.title ?? "Untitled")
                        .font(tokens.font(14, weight: .heavy))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Text(article.feedTitle)
                            .font(tokens.font(11, weight: .bold))
                            .foregroundStyle(StreamPalette.ink)
                            .lineLimit(1)
                        let others = StreamText.others(article)
                        if !others.isEmpty {
                            Text("· " + others.joined(separator: " · "))
                                .font(tokens.font(11))
                                .foregroundStyle(StreamPalette.faint)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        StreamStarSaveButtons(article: article, appDB: appDB, size: 12)
                    }
                    .frame(height: 16)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .streamCard(elevated: true)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .contextMenu { StreamRowMenu(article: article, appDB: appDB) }
        .onAppear { EngagementLog.shared.shown(article.articleID) }
    }

    private var imageBlock: some View {
        imageFrame
            .overlay { imageArea }
            .clipped()
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [StreamPalette.scrim.opacity(0), StreamPalette.scrim.opacity(0.58)],
                    startPoint: .top, endPoint: .bottom)
                .frame(height: 70)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    if variant == .popover {
                        HStack(spacing: 6) {
                            Text(article.feedTitle)
                                .font(tokens.font(11, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            StreamStarSaveButtons(article: article, appDB: appDB, size: 12, onImage: true)
                        }
                        .frame(height: 16)
                    }
                    HStack(spacing: 6) {
                        StreamPriorityPill(priority: article.priority, size: .card)
                        StreamSourceChips(article: article, appDB: appDB, size: .card)
                        if variant == .popover {
                            darkPill(StreamText.category(article.feedCategory))
                        }
                        Spacer(minLength: 4)
                        darkPill(article.dateArrived.relativeTime)
                    }
                    .frame(height: 18)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
    }

    private func darkPill(_ text: String) -> some View {
        Text(text)
            .font(tokens.font(11, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .frame(height: 18)
            .background(StreamPalette.scrim.opacity(0.45), in: Capsule())
    }

    /// The image's box: a pinned band, else 16:9 of the width when there is a picture, else the
    /// sheet's short placeholder band.
    @ViewBuilder
    private var imageFrame: some View {
        if let bandHeight {
            Color.clear.frame(height: bandHeight).frame(maxWidth: .infinity)
        } else if showsPicture {
            Color.clear.aspectRatio(StreamLayout.pictureAspect, contentMode: .fit).frame(maxWidth: .infinity)
        } else {
            Color.clear.frame(height: placeholderHeight).frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var imageArea: some View {
        if showsPicture, let url = URL(string: article.imageURL ?? "") {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }
}

/// A rounded 64pt picture for rows, cluster and story cards: the sheet's slate gradient until it
/// loads (and when a story has none, for the cluster card that always draws one).
struct StreamThumbnail: View {
    let article: ArticleInfo
    var side: CGFloat = StreamLayout.thumbnailSide

    var body: some View {
        Color.clear
            .frame(width: side, height: side)
            .overlay {
                if StreamLayout.hasPicture(article), let url = URL(string: article.imageURL ?? "") {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            StreamPalette.thumbGradient
                        }
                    }
                } else {
                    StreamPalette.thumbGradient
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Cluster card

/// A 3-source story that is not the lead: meta line with time, one-line title, the other outlets
/// underneath, and a 64pt thumbnail (the sheet's grey gradient when there is no image) in a 76pt
/// card; 56pt without the thumbnail when the tier forbids it.
struct StreamClusterCard: View {
    let article: ArticleInfo
    let appDB: AppDatabase
    var showThumbnail: Bool
    var tick = false
    let onOpen: () -> Void
    @Environment(\.designTokens) private var tokens

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                StreamMetaLine(article: article, appDB: appDB, tick: tick)
                Text(article.title ?? "Untitled")
                    .font(tokens.font(13, weight: .bold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(height: 15)
                Text(StreamText.others(article).joined(separator: " · "))
                    .font(tokens.font(11))
                    .foregroundStyle(StreamPalette.faint)
                    .lineLimit(1)
                    .frame(height: 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            StreamNotInterestedButton(article: article, appDB: appDB)
            if showThumbnail {
                StreamThumbnail(article: article)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: showThumbnail ? StreamLayout.rowHeight(hasThumbnail: true) : 56)
        .streamCard(elevated: true)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .contextMenu { StreamRowMenu(article: article, appDB: appDB) }
        .onAppear { EngagementLog.shared.shown(article.articleID) }
    }
}

// MARK: - Compact row

/// "source · chips · category" then a 13pt title; time, star, bookmark. 34pt with a single-line
/// title; with `thumbnails` on and a picture to show, a 64pt thumbnail sits on the trailing side,
/// the row grows to 76pt and the title may take two lines (a story without a picture keeps the
/// bare row, no empty box). Rows under the divider (and read rows) dim to ink2 with a semibold title.
struct StreamCompactRow: View {
    let article: ArticleInfo
    let appDB: AppDatabase
    var dimmed = false
    /// Whether rows may carry thumbnails (the popover on AC); the window's list keeps the 34pt row.
    var thumbnails = false
    var tick = false
    let onOpen: () -> Void
    @Environment(\.designTokens) private var tokens
    @State private var isHovering = false

    private var muted: Bool { dimmed || article.isRead == true }
    private var hasThumbnail: Bool { thumbnails && StreamLayout.hasPicture(article) }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                StreamMetaLine(article: article, appDB: appDB, showTime: false, dimmed: muted, tick: tick)
                Text(article.title ?? "Untitled")
                    .font(tokens.font(13, weight: muted ? .semibold : .bold))
                    .foregroundStyle(muted ? StreamPalette.ink2 : StreamPalette.ink)
                    .lineLimit(hasThumbnail ? 2 : 1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(height: hasThumbnail ? nil : 15)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(article.dateArrived.relativeTime)
                .font(tokens.font(11))
                .monospacedDigit()
                .foregroundStyle(StreamPalette.faint)
            StreamStarSaveButtons(article: article, appDB: appDB, size: 12)
            if hasThumbnail {
                StreamThumbnail(article: article)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: StreamLayout.rowHeight(hasThumbnail: hasThumbnail))
        .background(isHovering ? Color.primary.opacity(0.03) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { isHovering = $0 }
        .contextMenu { StreamRowMenu(article: article, appDB: appDB) }
        .onAppear { EngagementLog.shared.shown(article.articleID) }
    }
}

/// Consecutive compact rows share one 10pt-radius card, separated by canvas-coloured hairlines.
struct StreamRowGroup: View {
    let articles: [ArticleInfo]
    let appDB: AppDatabase
    var dimmed = false
    /// Passed to every row; off by default so the window's list stays 34pt rows.
    var thumbnails = false
    var tick = false
    let onOpen: (ArticleInfo) -> Void
    @Environment(\.designTokens) private var tokens

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(articles.enumerated()), id: \.element.articleID) { index, article in
                if index > 0 {
                    Rectangle().fill(tokens.canvas).frame(height: 1)
                }
                StreamCompactRow(
                    article: article, appDB: appDB, dimmed: dimmed, thumbnails: thumbnails, tick: tick,
                    onOpen: { onOpen(article) })
            }
        }
        .streamCard(radius: 10)
    }
}

// MARK: - Story card (window)

/// The window's per-story card: meta line with time, a 13.5pt title (heavy when new, bold ink2
/// once seen) and the on-device summary line when one exists; with `showThumbnail` on and a
/// picture to show, a 64pt thumbnail on the trailing side.
struct StreamStoryCard: View {
    let article: ArticleInfo
    let appDB: AppDatabase
    var dimmed = false
    var showThumbnail = false
    var tick = false
    let onOpen: () -> Void
    @Environment(\.designTokens) private var tokens

    private var muted: Bool { dimmed || article.isRead == true }
    private var hasThumbnail: Bool { showThumbnail && StreamLayout.hasPicture(article) }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    StreamMetaLine(article: article, appDB: appDB, dimmed: muted, compact: false, tick: tick)
                    StreamNotInterestedButton(article: article, appDB: appDB)
                }
                Text(article.title ?? "Untitled")
                    .font(tokens.font(13.5, weight: muted ? .bold : .heavy))
                    .foregroundStyle(muted ? StreamPalette.ink2 : StreamPalette.ink)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if !muted, let summary = article.summary, !summary.isEmpty {
                    HStack(alignment: .top, spacing: 5) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(StreamPalette.summaryGlyph)
                            .padding(.top, 2)
                        Text(summary)
                            .font(tokens.font(11.5))
                            .foregroundStyle(StreamPalette.ink2)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if hasThumbnail {
                StreamThumbnail(article: article)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .streamCard()
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .contextMenu { StreamRowMenu(article: article, appDB: appDB) }
        .onAppear { EngagementLog.shared.shown(article.articleID) }
    }
}

// MARK: - Divider and status line

/// Idea ①, drawn to the sheet: "SINCE YOU LAST LOOKED · 13:40 · 4 NEW" in 11pt heavy coral, a
/// 2pt coral rule, and the "Mark these read" pill.
struct StreamSinceDivider: View {
    let newCount: Int
    let lastLooked: Date?
    var spacing: CGFloat = 8
    var onMarkRead: (() -> Void)? = nil
    @Environment(\.designTokens) private var tokens

    var body: some View {
        HStack(spacing: spacing) {
            Text(StreamText.dividerText(newCount: newCount, lastLooked: lastLooked).uppercased())
                .font(tokens.font(11, weight: .heavy))
                .tracking(0.88)
                .foregroundStyle(tokens.accent)
                .lineLimit(1)
                .fixedSize()
            Capsule().fill(tokens.accent).frame(height: 2)
            if let onMarkRead {
                Button("Mark these read", action: onMarkRead)
                    .buttonStyle(.plain)
                    .font(tokens.font(11, weight: .bold))
                    .foregroundStyle(tokens.accent)
                    .padding(.horizontal, spacing == 8 ? 7 : 8)
                    .frame(height: spacing == 8 ? 14 : 18)
                    .background(tokens.accent.opacity(0.12), in: Capsule())
            }
        }
        .frame(height: spacing == 8 ? 14 : 18)
    }
}

/// Idea ③ as the sheet's footer line: a 7pt tier dot, then "AC · polled 2m ago · next in 3m ·
/// 18 requests, 0.6 MB" with the tier word in bold ink2. Refreshes every 30 s.
struct StreamStatusLine: View {
    @Environment(FeedEngine.self) private var engine
    @Environment(\.designTokens) private var tokens
    @ObservedObject private var power = PowerMonitor.shared
    @State private var now = Date()

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(dotColor).frame(width: 7, height: 7)
            text
                .font(tokens.font(11))
                .monospacedDigit()
                .foregroundStyle(tokens.secondaryText)
                .lineLimit(1)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                now = Date()
            }
        }
    }

    private var text: Text {
        let line = StatusLine.format(
            tier: power.tier, now: now, lastTickAt: engine.lastTickAt, nextTickAt: engine.nextTickAt,
            requests: engine.lastTickStats?.requests, bytes: engine.lastTickStats?.bytes)
        let tier = StatusLine.tierWord(power.tier)
        guard line.hasPrefix(tier) else { return Text(line) }
        return Text(tier).fontWeight(.bold).foregroundStyle(StreamPalette.ink2) + Text(line.dropFirst(tier.count))
    }

    private var dotColor: Color {
        switch power.tier {
        case .ac: return tokens.ok
        case .battery: return tokens.important
        case .critical: return tokens.breaking
        }
    }
}

// MARK: - Menus, coverage, empty state and web results

struct StreamRowMenu: View {
    let article: ArticleInfo
    let appDB: AppDatabase

    var body: some View {
        if let urlString = article.url, let url = URL(string: urlString) {
            Button("Open in Browser") { NSWorkspace.shared.open(url) }
            Button("Open in Reader") { ArticleReaderWindowController.shared.open(url: url, title: article.title) }
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(urlString, forType: .string)
            }
            Divider()
        }
        Button(article.isStarred == true ? "Unstar" : "Star") {
            Task { try? await appDB.toggleStarred(article.articleID) }
        }
        Button(article.isSaved == true ? "Remove from Saved" : "Save") {
            Task { try? await appDB.toggleSaved(article.articleID) }
        }
        if article.isRead != true {
            Button("Mark Read") { Task { try? await appDB.markRead(article.articleID) } }
        }
    }
}

/// The Coverage popover from the sheet: "COVERAGE · 3 OUTLETS", then each outlet as a coral
/// monogram pill, "Outlet · primary · 44m", its own headline and an open arrow.
struct StreamCoveragePopover: View {
    let article: ArticleInfo
    let appDB: AppDatabase
    @Environment(\.designTokens) private var tokens
    @State private var members: [ClusterMember] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("COVERAGE · \(max(members.count, article.sourceCount)) OUTLETS")
                .font(tokens.font(11, weight: .heavy))
                .tracking(0.66)
                .foregroundStyle(tokens.secondaryText)
                .frame(height: 14)
            let monos = Monogram.assign(members.map(\.feedTitle))
            ForEach(members) { member in
                Rectangle().fill(tokens.canvas).frame(height: 1)
                Button {
                    if let urlString = member.url, let url = URL(string: urlString) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(monos[member.feedTitle] ?? Monogram.make(member.feedTitle))
                            .font(tokens.font(11, weight: .heavy))
                            .foregroundStyle(tokens.accent)
                            .padding(.horizontal, 5)
                            .frame(height: 16)
                            .background(tokens.card, in: Capsule())
                            .overlay(Capsule().stroke(tokens.accent, lineWidth: 1))
                        VStack(alignment: .leading, spacing: 1) {
                            (Text(member.feedTitle).fontWeight(.bold).foregroundStyle(StreamPalette.ink)
                                + Text(member.articleID == article.articleID ? " · primary" : "")
                                + Text(" · " + member.dateArrived.relativeTime))
                                .font(tokens.font(11))
                                .foregroundStyle(tokens.secondaryText)
                                .lineLimit(1)
                                .frame(height: 12)
                            Text(member.title ?? "Untitled")
                                .font(tokens.font(12, weight: .semibold))
                                .lineLimit(1)
                                .frame(height: 14)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(tokens.accent)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if members.isEmpty {
                Text("Loading…").font(tokens.font(11)).foregroundStyle(tokens.secondaryText)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: 280)
        .background(tokens.card)
        .task { members = (try? await appDB.fetchClusterMembers(primaryID: article.articleID)) ?? [] }
    }
}

struct StreamEmptyState: View {
    let title: String
    let message: String
    var symbol = "newspaper"
    @Environment(\.designTokens) private var tokens

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(tokens.secondaryText.opacity(0.6))
            Text(title).font(tokens.font(13, weight: .bold))
            Text(message).font(tokens.font(11)).foregroundStyle(tokens.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}

/// Google News results under the list while a 3+ character search runs.
struct StreamWebResults: View {
    let model: FeedListModel
    let onOpen: (URL) -> Void
    @Environment(\.designTokens) private var tokens

    var body: some View {
        if model.isSearchingWeb {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Searching the web\u{2026}").font(tokens.font(11)).foregroundStyle(tokens.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        if !model.webSearchResults.isEmpty {
            VStack(spacing: 0) {
                HStack(spacing: 5) {
                    Image(systemName: "globe").font(.system(size: 10, weight: .bold))
                    Text("WEB RESULTS").font(tokens.font(11, weight: .heavy)).tracking(0.66)
                    Spacer()
                }
                .foregroundStyle(tokens.secondaryText)
                .padding(.horizontal, 10)
                .frame(height: 26)
                ForEach(model.webSearchResults) { item in
                    Rectangle().fill(tokens.canvas).frame(height: 1)
                    Button {
                        if let url = URL(string: item.url) { onOpen(url) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.source).font(tokens.font(11, weight: .bold)).foregroundStyle(StreamPalette.ink)
                                .lineLimit(1)
                            Text(item.title).font(tokens.font(13, weight: .bold)).lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .streamCard(radius: 10)
        }
    }
}
