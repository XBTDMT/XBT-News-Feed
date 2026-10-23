import SwiftUI
import AppKit

// MARK: - Panel and grid

/// What the card sliding over the right of the board shows. One at a time; `esc` closes it.
enum DeckBoardPanel: Equatable {
    case article(ArticleInfo)
    /// Today's Brief in full.
    case brief
    /// "starred", "saved" or a category tag: that list, each row opening as `.article`.
    case list(String)
    /// The top bar's search: FTS results, then the web results the model fetches.
    case search
    /// A web search result in the reader.
    case web(URL)

    var listTag: String? {
        if case .list(let tag) = self { return tag }
        return nil
    }

    var articleID: String? {
        if case .article(let article) = self { return article.articleID }
        return nil
    }
}

/// The D2 sheet's grid: six equal columns under a 52pt top bar, 12pt gaps, 16pt sides; the top row
/// (markets ×5 over four columns, Breaking, Brief) is 92pt, the price credit's own 14pt line sits
/// under it while the prices owe one, the widget row takes the rest, and the reader is a 460pt card
/// over the two right-hand widgets.
enum DeckBoardLayout {
    static let columns = 6
    static let gap: CGFloat = 12
    static let sideInset: CGFloat = 16
    static let topInset: CGFloat = 4
    static let bottomInset: CGFloat = 12
    static let topBarHeight: CGFloat = 52
    /// Left padding that clears the traffic lights (the sheet's 92).
    static let trafficLightInset: CGFloat = 92
    static let topRowHeight: CGFloat = 92
    /// The price credit's line under the market cards: 10pt text 2pt below them, right-aligned.
    static let creditRowHeight: CGFloat = 14

    /// The widget row's height on a board `boardHeight` tall (everything under the top bar): what the
    /// insets, the top row, its gap and the credit line (when there is one) leave.
    static func widgetRowHeight(boardHeight: CGFloat, hasCredit: Bool) -> CGFloat {
        max(0, boardHeight - topInset - bottomInset - topRowHeight - gap - (hasCredit ? creditRowHeight : 0))
    }
    /// The reader's width at the sheet's 1440: it covers Unread and Sources exactly there.
    static let readerWidth: CGFloat = 460

    /// The reader card covers the two right-hand widgets exactly on a wider window, and never
    /// drops below the sheet's 460 on a narrower one.
    static func readerWidth(column: CGFloat) -> CGFloat {
        max(readerWidth, span(2, column: column))
    }
    /// Rows the Top stories card ranks; the card scrolls past what fits.
    static let topStoriesLimit = 10

    /// Width of one column for a board `boardWidth` points wide (the side insets come off first).
    static func columnWidth(boardWidth: CGFloat) -> CGFloat {
        max(0, (boardWidth - 2 * sideInset - CGFloat(columns - 1) * gap) / CGFloat(columns))
    }

    /// Width of a widget spanning `count` columns (its inner gaps included).
    static func span(_ count: Int, column: CGFloat) -> CGFloat {
        CGFloat(count) * column + CGFloat(max(0, count - 1)) * gap
    }

    /// The Unread card's rows: most unread first, ties in registry order, every category kept.
    static func unreadOrder(_ categories: [NewsCategory], counts: [String: Int]) -> [NewsCategory] {
        categories.enumerated().sorted { a, b in
            let ca = counts[a.element.id] ?? 0, cb = counts[b.element.id] ?? 0
            return ca != cb ? ca > cb : a.offset < b.offset
        }.map(\.element)
    }
}

// MARK: - Shared pieces

/// "Top stories … by coverage · 24h" — the 11pt semibold title row every board card starts with.
struct DeckBoardHeader<Trailing: View>: View {
    let title: String
    var color: Color = DeckPalette.secondary
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
            Spacer(minLength: 4)
            trailing()
        }
        .frame(height: 16)
    }
}

/// "1,659" — the 15pt bold number at the right of a header.
struct DeckBoardBigNumber: View {
    let value: Int
    var color: Color = DeckPalette.text

    var body: some View {
        Text("\(value)")
            .font(.system(size: 15, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(color)
    }
}

/// "EARLIER" — the uppercase group label inside a list.
struct DeckBoardGroupLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .kerning(0.66)
            .foregroundStyle(DeckPalette.tertiary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }
}

/// The board's story row as the sheet draws it: "Source · Category · IMPORTANT" and the time on
/// one 11pt line (the category in its swatch colour), the title on up to two lines, then the
/// coverage chips. The open row sits on a pale blue. Rows carry 6pt side padding so the highlight
/// can outrun the text; the list that holds them pulls itself out by the same 6pt.
struct DeckBoardStoryRow: View {
    let article: ArticleInfo
    let appDB: AppDatabase
    var tick: Bool = false
    var selected = false
    var showsCategory = true

    private var priority: (label: String, color: Color)? {
        switch article.priority {
        case "breaking": return ("BREAKING", DeckPalette.red)
        case "important": return ("IMPORTANT", DeckPalette.importantText)
        default: return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                meta.lineLimit(1)
                Spacer(minLength: 8)
                Text(article.dateArrived.relativeTime).monospacedDigit()
                DeckBoardNotInterestedButton(article: article, appDB: appDB)
            }
            .font(.system(size: 11))
            .foregroundStyle(DeckPalette.tertiary)
            Text(article.title ?? "Untitled")
                .font(.system(size: 13, weight: priority == nil ? .semibold : .bold))
                .foregroundStyle(priority == nil ? DeckPalette.body : DeckPalette.text)
                .lineSpacing(1.5)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if article.sourceCount > 1 {
                SourceChips(article: article, appDB: appDB)
            }
        }
        .padding(EdgeInsets(top: 8, leading: 6, bottom: 10, trailing: 6))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? DeckPalette.selectedRow : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .bottom) { DeckRule().padding(.horizontal, 6) }
        .contentShape(Rectangle())
        .onAppear { EngagementLog.shared.shown(article.articleID) }
    }

    private var meta: Text {
        var text = Text(article.feedTitle)
        if showsCategory {
            let category = NewsCategory.named(article.feedCategory)
            text = text + Text(" · ") + Text(category.short).fontWeight(.semibold).foregroundStyle(Color(hex: category.colorHex))
        }
        if let priority {
            text = text + Text(" · ") + Text(priority.label).fontWeight(.bold).foregroundStyle(priority.color)
        }
        return text
    }
}

/// A Top stories row: the rank in 15pt bold grey, then source · time, the title and the chips.
struct DeckBoardRankedRow: View {
    let rank: Int
    let article: ArticleInfo
    let appDB: AppDatabase
    var tick: Bool = false
    var selected = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(rank)")
                .font(.system(size: 15, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(DeckPalette.quaternary)
                .fixedSize()
                .frame(minWidth: 18, alignment: .leading)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(article.feedTitle).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(article.dateArrived.relativeTime).monospacedDigit()
                    DeckBoardNotInterestedButton(article: article, appDB: appDB)
                }
                .font(.system(size: 11))
                .foregroundStyle(DeckPalette.tertiary)
                Text(article.title ?? "Untitled")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DeckPalette.body)
                    .lineSpacing(1.5)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if article.sourceCount > 1 {
                    SourceChips(article: article, appDB: appDB).padding(.top, 1)
                }
            }
        }
        .padding(EdgeInsets(top: 8, leading: 6, bottom: 10, trailing: 6))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? DeckPalette.selectedRow : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .bottom) { DeckRule().padding(.horizontal, 6) }
        .contentShape(Rectangle())
        .onAppear { EngagementLog.shared.shown(article.articleID) }
    }
}

/// The learning week's "Not interested" on a board row: an 11pt xmark.circle in the compact row's
/// idle-star grey at the meta line's end. A plain button, so the row's own tap stays the row's.
private struct DeckBoardNotInterestedButton: View {
    let article: ArticleInfo
    let appDB: AppDatabase

    var body: some View {
        Button {
            Task { try? await appDB.dismiss(articleID: article.articleID, log: EngagementStudy.isEnabled(.standard)) }
        } label: {
            Image(systemName: "xmark.circle")
                .font(.system(size: 11))
                .foregroundStyle(DeckPalette.quaternary)
                .frame(width: 13, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Not interested")
        .accessibilityLabel("Not interested")
    }
}

// MARK: - Top row

/// One of the five market cards: "BTC −0.4%" on a 10pt line, the price at 16pt bold, a sparkline.
/// An instrument with no quote yet keeps its card, with a dash.
struct DeckBoardMarketCard: View {
    let label: String
    let row: MarketRow?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DeckPalette.secondary)
                    .lineLimit(1)
                Spacer(minLength: 2)
                if let change = row?.changeText {
                    Text(change)
                        .font(.system(size: 10, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(DeckPalette.changeText(row?.isUp))
                        .padding(.horizontal, 6)
                        .frame(height: 16)
                        .background(DeckPalette.changeFill(row?.isUp).opacity(0.16), in: Capsule())
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .frame(height: 16)
            Text(row?.priceText ?? "\u{2014}")
                .font(.system(size: 16, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(row == nil ? DeckPalette.quaternary : DeckPalette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            DeckSparkline(data: row?.sparkline ?? [], color: DeckPalette.changeFill(row?.isUp), lineWidth: 1.5)
                .frame(minHeight: 18, maxHeight: .infinity)
        }
        .deckChrome(isExpanded: false, verticalPadding: 10)
    }
}

/// "● Breaking 0" — the first unread breaking headline (or "No breaking stories unread"), then
/// "● 1 important · Bloomberg · 14m" or, with nothing important, the "N new since HH:mm" line.
struct DeckBoardBreakingCard: View {
    /// Unread breaking stories first, then important; newest-first inside each.
    let stories: [ArticleInfo]
    let breakingCount: Int
    let lastLooked: Date?
    let onOpen: (ArticleInfo) -> Void

    private var breaking: ArticleInfo? { stories.first { $0.priority == "breaking" } }
    private var important: ArticleInfo? { stories.first { $0.priority == "important" } }
    private var importantCount: Int { stories.filter { $0.priority == "important" }.count }
    private var newCount: Int {
        SinceLastLooked.partition(stories, arrival: { $0.arrivalDate }, lastLooked: lastLooked).newCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            DeckBoardHeader(title: "Breaking", color: DeckPalette.red) {
                DeckBoardBigNumber(value: breakingCount, color: DeckPalette.red)
            }
            .overlay(alignment: .leading) {
                DeckDot(color: DeckPalette.red).offset(x: -12)
            }
            .padding(.leading, 12)
            if let breaking {
                Button {
                    onOpen(breaking)
                } label: {
                    Text(breaking.title ?? "Untitled")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(DeckPalette.body)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            } else {
                Text("No breaking stories unread")
                    .font(.system(size: 11.5))
                    .foregroundStyle(DeckPalette.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let important {
                Button {
                    onOpen(important)
                } label: {
                    HStack(spacing: 5) {
                        DeckDot(color: DeckPalette.gold)
                        Text("\(importantCount) important · \(important.feedTitle) · \(important.dateArrived.relativeTime)")
                            .font(.system(size: 11))
                            .foregroundStyle(DeckPalette.tertiary)
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Text(DeckLayout.newSinceText(newCount: newCount, lastLooked: lastLooked))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DeckPalette.accent)
                    .lineLimit(1)
            }
        }
        .deckChrome(isExpanded: false, verticalPadding: 10)
    }
}

/// "☀ Brief · cautious" — two lines of the summary and "10 stories ›", which opens the full brief in
/// the slide-over. A nil digest asks the engine for one and says so.
struct DeckBoardBriefCard: View {
    let digest: DailyDigest?
    let onOpen: () -> Void
    let onGenerate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "sun.max")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DeckPalette.sun)
                Text("Brief")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DeckPalette.secondary)
                Spacer(minLength: 4)
                if let mood = digest?.marketMood, !mood.isEmpty {
                    DeckMoodChip(mood: mood)
                }
            }
            .frame(height: 16)
            if let digest {
                Text(digest.summary)
                    .font(.system(size: 11.5))
                    .lineSpacing(1)
                    .foregroundStyle(DeckPalette.body)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Button(action: onOpen) {
                    Text("\(digest.topStories.count) stories \u{203A}")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DeckPalette.accent)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .help("Read today's brief")
            } else {
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Generating brief\u{2026}").font(.system(size: 11)).foregroundStyle(DeckPalette.tertiary)
                }
                Spacer(minLength: 0)
            }
        }
        .deckChrome(isExpanded: false, verticalPadding: 10)
        .contentShape(Rectangle())
        .onTapGesture { if digest != nil { onOpen() } }
        .task { if digest == nil { onGenerate() } }
    }
}

// MARK: - Widget row

/// "✦ Since you last looked · 200 · Mark these read": the last recap's text under the header while
/// there is something new (the same words as the recap notification and the popover's card), then
/// the new stories as rows and, under "Earlier", the rest of the unread list.
struct DeckBoardSinceCard: View {
    let split: SinceLastLooked.Partition<ArticleInfo>
    /// The header's number: `newSinceObservation`, which the menu bar shows too, so the count is
    /// honest past the list's 200-row cap.
    let newCount: Int
    let recap: SummaryText?
    let lastLooked: Date?
    let appDB: AppDatabase
    let tick: Bool
    let selectedID: String?
    let onOpen: (ArticleInfo) -> Void
    let onMarkRead: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(DeckPalette.accent)
                Text("Since you last looked")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DeckPalette.accent)
                    .lineLimit(1)
                Spacer(minLength: 4)
                DeckBoardBigNumber(value: newCount, color: DeckPalette.accent)
                if newCount > 0 {
                    Button("Mark these read", action: onMarkRead)
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(DeckPalette.accent)
                        .padding(.horizontal, 7)
                        .frame(height: 18)
                        .background(DeckPalette.accent.opacity(0.12), in: Capsule())
                        .padding(.leading, 2)
                        .help("Mark the stories since you last looked as read")
                }
            }
            .frame(height: 18)
            .padding(.bottom, 4)

            if newCount > 0, let recap {
                Text(recap.body)
                    .font(.system(size: 12))
                    .lineSpacing(2)
                    .foregroundStyle(DeckPalette.body)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 6)
                DeckRule(color: DeckPalette.listRule)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(split.new) { row($0) }
                    if !split.seen.isEmpty {
                        DeckBoardGroupLabel(
                            text: split.new.isEmpty ? DeckLayout.newSinceText(newCount: 0, lastLooked: lastLooked) : "Earlier")
                        ForEach(split.seen) { row($0) }
                    }
                    if split.new.isEmpty, split.seen.isEmpty {
                        Text("Nothing unread")
                            .font(.system(size: 12))
                            .foregroundStyle(DeckPalette.tertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 10)
                    }
                }
            }
            .padding(.horizontal, -6)
        }
        .deckChrome(isExpanded: false)
    }

    private func row(_ article: ArticleInfo) -> some View {
        DeckBoardStoryRow(article: article, appDB: appDB, tick: tick, selected: selectedID == article.articleID)
            .onTapGesture { onOpen(article) }
    }
}

/// "Top stories · by coverage · 24h" — `TopStories.rank` drawn as numbered rows.
struct DeckBoardTopStoriesCard: View {
    let stories: [ArticleInfo]
    let appDB: AppDatabase
    let tick: Bool
    let selectedID: String?
    let onOpen: (ArticleInfo) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DeckBoardHeader(title: "Top stories") {
                Text("by coverage · 24h")
                    .font(.system(size: 11))
                    .foregroundStyle(DeckPalette.secondary)
                    .lineLimit(1)
            }
            .padding(.bottom, 2)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(stories.enumerated()), id: \.element.id) { index, article in
                        DeckBoardRankedRow(
                            rank: index + 1, article: article, appDB: appDB, tick: tick,
                            selected: selectedID == article.articleID
                        )
                        .onTapGesture { onOpen(article) }
                    }
                    if stories.isEmpty {
                        Text("No unread stories in the last 24 hours")
                            .font(.system(size: 12))
                            .foregroundStyle(DeckPalette.tertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 10)
                    }
                }
            }
            .padding(.horizontal, -6)
        }
        .deckChrome(isExpanded: false)
    }
}

/// "Unread 1,659" — one horizontal bar per switched-on category, most unread first: the popover's
/// Unread bars turned on their side with the count at the right. A row opens that category's list.
struct DeckBoardUnreadCard: View {
    let byCategory: [String: Int]
    let total: Int
    /// The categories that are switched on (registry order).
    let categories: [NewsCategory]
    let onOpen: (String) -> Void

    private var rows: [NewsCategory] { DeckBoardLayout.unreadOrder(categories, counts: byCategory) }
    private var top: Int { rows.map { byCategory[$0.id] ?? 0 }.max() ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DeckBoardHeader(title: "Unread") { DeckBoardBigNumber(value: total) }
            ScrollView {
                VStack(spacing: 7) {
                    ForEach(rows) { category in
                        bar(category, count: byCategory[category.id] ?? 0)
                    }
                    if rows.isEmpty {
                        Text("No categories switched on")
                            .font(.system(size: 12))
                            .foregroundStyle(DeckPalette.tertiary)
                            .padding(.vertical, 6)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .deckChrome(isExpanded: false)
    }

    private func bar(_ category: NewsCategory, count: Int) -> some View {
        Button {
            onOpen(category.id)
        } label: {
            HStack(spacing: 8) {
                Text(category.short)
                    .font(.system(size: 11))
                    .foregroundStyle(DeckPalette.secondary)
                    .lineLimit(1)
                    .frame(width: 44, alignment: .leading)
                GeometryReader { geo in
                    let fraction = top > 0 ? CGFloat(count) / CGFloat(top) : 0
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: category.colorHex).opacity(count > 0 ? 1 : 0.3))
                        .frame(width: max(3, (geo.size.width * fraction).rounded()))
                }
                .frame(height: 8)
                Text("\(count)")
                    .font(.system(size: 11, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(count > 0 ? DeckPalette.text : DeckPalette.quaternary)
                    .frame(width: 30, alignment: .trailing)
            }
            .frame(height: 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open \(category.label)")
    }
}

/// "Sources 69 · 66 ok · 2 stale · 1 failing", the Starred and Saved strip tiles, and idea ③'s
/// status line at the foot.
struct DeckBoardSourcesCard: View {
    let stats: DeckStats
    let onStarred: () -> Void
    let onSaved: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DeckBoardHeader(title: "Sources") { DeckBoardBigNumber(value: stats.feeds) }
            HStack(spacing: 0) {
                Text("\(stats.feedsOK) ok").foregroundStyle(DeckPalette.upText)
                Text(" · ").foregroundStyle(DeckPalette.tertiary)
                Text("\(stats.feedsStale) stale").foregroundStyle(DeckPalette.amberText)
                Text(" · ").foregroundStyle(DeckPalette.tertiary)
                Text("\(stats.feedsFailing) failing").foregroundStyle(DeckPalette.downText)
            }
            .font(.system(size: 11))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            stripTile("star.fill", color: DeckPalette.gold, title: "Starred", count: stats.starred, action: onStarred)
            stripTile("bookmark.fill", color: DeckPalette.accent, title: "Saved", count: stats.saved, action: onSaved)
            Spacer(minLength: 0)
            DeckStatusLine().frame(height: 16)
        }
        .deckChrome(isExpanded: false)
    }

    /// "★ Starred … 0" — a 38pt strip with a 1px hairline, the number at the right.
    private func stripTile(_ symbol: String, color: Color, title: String, count: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(color).frame(width: 14)
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(DeckPalette.secondary).lineLimit(1)
                Spacer(minLength: 4)
                DeckBoardBigNumber(value: count)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(DeckPalette.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(DeckPalette.listRule, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open \(title)")
    }
}

// MARK: - Slide-over

/// The 460pt card that slides in over the Unread and Sources widgets: a 38pt header ("Bloomberg
/// Markets · Finance · IMPORTANT · 14m … esc ✕"), then the article (`ArticleDetailView`), the full
/// brief, a list, the search results or a web result. The board underneath stays live.
struct DeckBoardPanelView: View {
    let panel: DeckBoardPanel
    let appDB: AppDatabase
    /// The board's list model: its search results and web results.
    let model: FeedListModel
    /// The list panel's own observation (starred, saved or a category).
    let listModel: FeedListModel
    let digest: DailyDigest?
    let tick: Bool
    let onOpenArticle: (ArticleInfo) -> Void
    let onOpenWeb: (URL) -> Void
    let onStory: (DigestStory) -> Void
    let onGenerate: () -> Void
    /// Clears the brief and every unread story with it.
    var onClear: (() -> Void)? = nil
    let onClose: () -> Void

    private static let cornerRadius: CGFloat = 12

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 14)
                .frame(height: 38)
                .overlay(alignment: .bottom) { DeckRule(color: DeckPalette.listRule) }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(DeckPalette.card)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: Self.cornerRadius).strokeBorder(Color.black.opacity(0.10), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.16), radius: 18, x: -7, y: 0)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            title.lineLimit(1)
            Spacer(minLength: 8)
            Text("esc")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DeckPalette.tertiary)
                .padding(.horizontal, 5)
                .frame(height: 16)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(DeckPalette.listRule, lineWidth: 1))
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DeckPalette.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close (esc)")
        }
        .font(.system(size: 11))
        .foregroundStyle(DeckPalette.tertiary)
    }

    @ViewBuilder
    private var title: some View {
        switch panel {
        case .article(let article):
            let category = NewsCategory.named(article.feedCategory)
            HStack(spacing: 4) {
                Text(article.feedTitle).fontWeight(.semibold).foregroundStyle(DeckPalette.body)
                Text("·")
                Text(category.short).fontWeight(.semibold).foregroundStyle(Color(hex: category.colorHex))
                if article.priority == "breaking" {
                    Text("·")
                    Text("BREAKING").fontWeight(.bold).foregroundStyle(DeckPalette.red)
                } else if article.priority == "important" {
                    Text("·")
                    Text("IMPORTANT").fontWeight(.bold).foregroundStyle(DeckPalette.importantText)
                }
                Text("·")
                Text(article.dateArrived.relativeTime).monospacedDigit()
            }
        case .brief:
            HStack(spacing: 6) {
                Image(systemName: "sun.max").font(.system(size: 11, weight: .bold)).foregroundStyle(DeckPalette.sun)
                Text("Today's Brief").fontWeight(.semibold).foregroundStyle(DeckPalette.body)
                if let mood = digest?.marketMood, !mood.isEmpty {
                    DeckMoodChip(mood: mood)
                }
            }
        case .list(let tag):
            HStack(spacing: 6) {
                switch tag {
                case "starred":
                    Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(DeckPalette.gold)
                    Text("Starred").fontWeight(.semibold).foregroundStyle(DeckPalette.body)
                case "saved":
                    Image(systemName: "bookmark.fill").font(.system(size: 11)).foregroundStyle(DeckPalette.accent)
                    Text("Saved").fontWeight(.semibold).foregroundStyle(DeckPalette.body)
                default:
                    let category = NewsCategory.named(tag)
                    RoundedRectangle(cornerRadius: 2).fill(Color(hex: category.colorHex)).frame(width: 8, height: 8)
                    Text(category.label).fontWeight(.semibold).foregroundStyle(DeckPalette.body)
                }
                Text("·")
                Text("\(listModel.articles.count)").monospacedDigit()
            }
        case .search:
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .semibold))
                Text("Search").fontWeight(.semibold).foregroundStyle(DeckPalette.body)
                Text("·")
                Text("\(model.searchResults.count) results").monospacedDigit()
            }
        case .web(let url):
            HStack(spacing: 6) {
                Image(systemName: "globe").font(.system(size: 11, weight: .semibold))
                Text("Web").fontWeight(.semibold).foregroundStyle(DeckPalette.body)
                Text("·")
                Text(url.host() ?? url.absoluteString)
            }
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch panel {
        case .article(let article):
            ArticleDetailView(article: article, appDB: appDB)
        case .brief:
            ScrollView {
                BriefCard(digest: digest, mode: .full, onStory: onStory, onGenerate: onGenerate,
                          onClear: onClear)
                    .padding(16)
            }
        case .list(let tag):
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(listModel.articles) { article in
                        DeckBoardStoryRow(
                            article: article, appDB: appDB, tick: tick,
                            showsCategory: tag == "starred" || tag == "saved"
                        )
                        .onTapGesture { onOpenArticle(article) }
                    }
                    if listModel.articles.isEmpty {
                        Text(emptyListText(tag))
                            .font(.system(size: 12))
                            .foregroundStyle(DeckPalette.tertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 12)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
            }
        case .search:
            searchResults
        case .web(let url):
            ReaderWebView(url: url, isReaderMode: .constant(true), theme: AppDesign.current.readerTheme)
        }
    }

    private func emptyListText(_ tag: String) -> String {
        switch tag {
        case "starred": return "Nothing starred yet"
        case "saved": return "Nothing saved yet"
        default: return "Nothing unread in \(NewsCategory.named(tag).label)"
        }
    }

    private var searchResults: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(model.searchResults) { article in
                    DeckBoardStoryRow(article: article, appDB: appDB, tick: tick)
                        .onTapGesture { onOpenArticle(article) }
                }
                if model.isSearchingWeb {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Searching the web\u{2026}").font(.system(size: 11)).foregroundStyle(DeckPalette.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                if !model.webSearchResults.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "globe").font(.system(size: 10))
                        Text("WEB RESULTS").font(.system(size: 11, weight: .bold)).kerning(0.66)
                    }
                    .foregroundStyle(DeckPalette.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
                    ForEach(model.webSearchResults) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.source).font(.system(size: 11)).foregroundStyle(DeckPalette.tertiary).lineLimit(1)
                            Text(item.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(DeckPalette.body).lineLimit(2)
                        }
                        .padding(EdgeInsets(top: 8, leading: 6, bottom: 10, trailing: 6))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .bottom) { DeckRule().padding(.horizontal, 6) }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let url = URL(string: item.url) { onOpenWeb(url) }
                        }
                    }
                }
                if model.searchText.count < 2 {
                    Text("Type at least 2 characters to search")
                        .font(.system(size: 12))
                        .foregroundStyle(DeckPalette.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 12)
                } else if model.searchResults.isEmpty, model.webSearchResults.isEmpty, !model.isSearchingWeb {
                    Text("No articles match \u{201C}\(model.searchText)\u{201D}")
                        .font(.system(size: 12))
                        .foregroundStyle(DeckPalette.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
        }
    }
}
