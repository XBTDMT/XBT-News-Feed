import SwiftUI
import AppKit
import Sparkle

/// Stream (R4-Stream-B) popover, 660 tall: canvas background, white cards, coral accent, Manrope.
/// A 34pt header with the unread pill, five 34pt market cards, the floating chip capsule that
/// overlaps the lead card by 14pt, then the stream — a hero card for the lead with its picture at
/// 16:9 (223pt across the 396pt card), up to two 150pt picture cards for multi-source stories with
/// a picture, cluster cards for the other 3-source stories, and rows for the rest (76pt with a
/// 64pt thumbnail on AC, 34pt bare) — split by the coral since-you-last-looked divider, and the
/// 24pt status footer. ⌘F reveals search; the header's expand glyph opens the window.
struct StreamPopover: View {
    let appDB: AppDatabase
    let updater: SPUStandardUpdaterController
    @Environment(FeedEngine.self) private var engine
    @Environment(\.designTokens) private var tokens
    @ObservedObject private var power = PowerMonitor.shared
    @State private var model: FeedListModel
    @State private var recapCardShown = false
    /// Whether the price credit fits in the header's free space; when not, it goes under the cards.
    @State private var creditInHeader = true
    @State private var counts: UnreadCountsModel
    @State private var selectedTag = "all"
    @State private var showSearch = false
    @State private var lastLooked: Date? = LastLookedStore.read()
    @State private var isVisible = false

    init(appDB: AppDatabase, updater: SPUStandardUpdaterController) {
        self.appDB = appDB
        self.updater = updater
        _model = State(initialValue: FeedListModel(appDB: appDB))
        _counts = State(initialValue: UnreadCountsModel(appDB: appDB))
    }

    /// What the list observes: nil for All and Brief, else the tag (a category, starred, saved).
    private var observedCategory: String? {
        (selectedTag == "all" || selectedTag == "digest") ? nil : selectedTag
    }

    private var policy: ImagePolicy { ImageGate.policy(for: power.tier) }

    /// Thumbnails and the extra picture cards only when the tier allows every image (AC).
    private var thumbnails: Bool { policy == .heroAndThumbnails }

    private var cardsAllowed: Bool {
        selectedTag != "starred" && selectedTag != "saved" && model.searchText.isEmpty
    }

    var body: some View {
        let markets = MarketsModel.display(prices: engine.latestPrices, history: engine.priceHistory)
        let credit = markets.rows.isEmpty ? nil : markets.credit
        VStack(spacing: 0) {
            header(credit: credit)
                .padding(.horizontal, 14)
                .frame(height: 34)

            if !markets.rows.isEmpty {
                marketsStrip(markets.rows, credit: creditInHeader ? nil : credit)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }

            if showSearch || !model.searchText.isEmpty {
                searchField
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }

            StreamChipRow(selected: $selectedTag, style: .floating, enabled: counts.enabledCategories)
                .padding(.horizontal, 12)
                .padding(.bottom, -14)
                .zIndex(2)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
        }
        .background(tokens.canvas)
        .frame(width: AppDesign.stream.popoverSize.width, height: AppDesign.stream.popoverSize.height)
        .task(id: observedCategory) { await model.observe(category: observedCategory) }
        .task { await counts.observe() }
        .task(id: isVisible) {
            guard isVisible else { return }
            await model.tickWhileVisible()
        }
        .task(id: model.searchText) { await model.runSearch(model.searchText) }
        .onAppear {
            isVisible = true
            lastLooked = LastLookedStore.read()
        }
        .onDisappear {
            isVisible = false
            LastLookedStore.markLooked()
            if recapCardShown {
                recapCardShown = false
                Task { await engine.markRecapRead() }
            }
        }
        .background {
            Button("", action: toggleSearch)
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
        }
    }

    // MARK: - Header

    /// Name, unread capsule and "Updated …" at the left, the three buttons at the right; the price credit
    /// rides on the Spacer between them (10pt, against the buttons) whenever it fits there.
    private func header(credit: String?) -> some View {
        HStack(spacing: 8) {
            Text(AppInfo.displayName)
                .font(tokens.font(14, weight: .heavy))
                .tracking(-0.14)
                .lineLimit(1)
                .layoutPriority(1)
            if counts.total > 0 {
                Text("\(CompactCount.format(counts.total)) unread")
                    .font(tokens.font(11, weight: .bold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .padding(.horizontal, 7)
                    .frame(height: 16)
                    .background(tokens.accent, in: Capsule())
            }
            if let lastUpdated = model.lastUpdated {
                let _ = model.tick
                Text(Self.updatedText(lastUpdated))
                    .font(tokens.font(11))
                    .foregroundStyle(StreamPalette.faint)
                    .lineLimit(1)
            }
            MarketsCreditSlot(credit: credit, minLength: 4, neighbourGap: 8, font: tokens.font(10), measureFont: tokens.nsFont(10),
                              color: StreamPalette.faint, fits: $creditInHeader)
            headerButton("arrow.up.left.and.arrow.down.right", help: "Open in window") {
                MainWindowController.shared.open(appDB: appDB, feedEngine: engine)
            }
            Button(action: { engine.refreshAll() }) {
                if engine.isRefreshing {
                    ProgressView().controlSize(.mini).frame(width: 16, height: 16)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(tokens.secondaryText)
                        .frame(width: 16, height: 16)
                }
            }
            .buttonStyle(.plain)
            .help("Refresh")
            .keyboardShortcut("r", modifiers: .command)
            headerButton("checkmark.circle", help: "Mark all read", action: markAllRead)
                .keyboardShortcut("a", modifiers: [.command, .shift])
        }
    }

    private func headerButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tokens.secondaryText)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// "Updated now" / "Updated 2m ago".
    static func updatedText(_ date: Date) -> String {
        let rel = date.relativeTime
        return rel == "now" ? "Updated now" : "Updated \(rel) ago"
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(StreamPalette.faint)
            TextField("Search articles", text: $model.searchText)
                .textFieldStyle(.plain)
                .font(tokens.font(12))
            if !model.searchText.isEmpty {
                Button {
                    model.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(StreamPalette.faint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .streamCard(radius: 8)
    }

    // MARK: - Markets strip

    /// Five 34pt cards: label and 24h change on the first line, the compact price and a 20×10
    /// line sparkline on the second. `credit` is the fallback for a header with no room for it: then it
    /// sits under the cards, right-aligned, at 10pt.
    private func marketsStrip(_ rows: [MarketRow], credit: String?) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            marketCards(rows)
            if let credit {
                MarketsCredit(text: credit, font: tokens.font(10), color: StreamPalette.faint)
                    .padding(.trailing, 2)
            }
        }
    }

    private func marketCards(_ rows: [MarketRow]) -> some View {
        HStack(spacing: 4) {
            ForEach(rows) { row in
                let quote = engine.latestPrices[row.id]
                let color = changeColor(quote?.change24h)
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        Text(row.label)
                            .font(tokens.font(11, weight: .bold))
                            .foregroundStyle(StreamPalette.ink)
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        if let change = StreamText.change(quote?.change24h) {
                            Text(change)
                                .font(tokens.font(11, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(color)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    .frame(height: 12)
                    HStack(spacing: 2) {
                        Text(StreamText.compactPrice(quote?.price ?? 0, symbol: row.label))
                            .font(tokens.font(11, weight: .bold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 2)
                        if row.sparkline.count >= 2 {
                            StreamSparkline(data: row.sparkline)
                                .stroke(color, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                                .frame(width: 20, height: 10)
                        }
                    }
                    .frame(height: 14)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .streamCard(radius: 8)
            }
        }
    }

    private func changeColor(_ pct: Double?) -> Color {
        guard let pct, !StreamText.isFlat(pct) else { return StreamPalette.faint }
        return pct >= 0 ? tokens.ok : tokens.breaking
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if selectedTag == "digest" {
            ScrollView(showsIndicators: false) {
                BriefCard(digest: engine.dailyDigest, mode: .full, onStory: openStory,
                          onGenerate: { engine.refreshDigest() },
                          onClear: { Task { await engine.markBriefRead() } })
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .streamCard()
                    .padding(.horizontal, 12)
                    .padding(.top, 18)
                    .padding(.bottom, 4)
            }
        } else if model.displayed.isEmpty && model.webSearchResults.isEmpty && !model.isSearchingWeb {
            StreamEmptyState(title: emptyTitle, message: emptyMessage)
                .padding(.top, 18)
        } else {
            let split = model.partition(lastLooked: lastLooked)
            let heroID = cardsAllowed ? StreamLayout.hero(in: model.displayed)?.articleID : nil
            let budget = thumbnails ? StreamLayout.popoverPictureBudget : 0
            let newBlocks = StreamLayout.blocks(
                split.new, heroID: heroID, cardsAllowed: cardsAllowed, pictureBudget: budget)
            let seenBlocks = StreamLayout.blocks(
                split.seen, heroID: heroID, cardsAllowed: cardsAllowed,
                pictureBudget: budget - StreamLayout.pictureCards(in: newBlocks))
            let firstIsImageCard = (newBlocks.first ?? seenBlocks.first)?.isImageCard ?? false
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 4) {
                    if model.searchText.isEmpty, split.newCount > 0, let recap = engine.lastRecap {
                        // The chip capsule overlaps the first block by 14 pt (drawn for the hero image); give
                        // the card that room so the capsule never covers its title line.
                        RecapCard(summary: recap, newCount: split.newCount, onMarkRead: { markRead(split.new) })
                        .onAppear { recapCardShown = true }
                            .padding(.top, 18)
                    }
                    ForEach(newBlocks) { block in blockView(block, dimmed: false) }
                    if model.searchText.isEmpty, !split.new.isEmpty, !split.seen.isEmpty {
                        StreamSinceDivider(newCount: split.newCount, lastLooked: lastLooked, onMarkRead: {
                            markRead(split.new)
                        })
                        .padding(.horizontal, 2)
                    }
                    ForEach(seenBlocks) { block in blockView(block, dimmed: true) }
                    StreamWebResults(model: model, onOpen: { NSWorkspace.shared.open($0) })
                }
                .padding(.horizontal, 12)
                // The chip capsule overlaps the first 14pt; only a card's image band should sit under it.
                .padding(.top, firstIsImageCard ? 0 : 18)
                .padding(.bottom, 4)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: StreamBlock, dimmed: Bool) -> some View {
        switch block {
        case .hero(let article):
            StreamHeroCard(
                article: article, appDB: appDB, variant: .popover, showImage: policy != .none, tick: model.tick,
                onOpen: { openArticle(article) })
        case .picture(let article):
            // Only laid out while the tier allows every image, so the picture is always shown.
            StreamHeroCard(
                article: article, appDB: appDB, variant: .popover, showImage: true, isLead: false,
                bandHeight: StreamLayout.pictureBandHeight, tick: model.tick,
                onOpen: { openArticle(article) })
        case .cluster(let article):
            StreamClusterCard(
                article: article, appDB: appDB, showThumbnail: thumbnails, tick: model.tick,
                onOpen: { openArticle(article) })
        case .rows(let articles):
            StreamRowGroup(
                articles: articles, appDB: appDB, dimmed: dimmed, thumbnails: thumbnails, tick: model.tick,
                onOpen: openArticle)
        }
    }

    private var emptyTitle: String {
        if !model.searchText.isEmpty { return "No Results" }
        switch selectedTag {
        case "starred": return "Nothing Starred"
        case "saved": return "Nothing Saved"
        default: return "No Articles"
        }
    }

    private var emptyMessage: String {
        if engine.isRefreshing { return "Fetching feeds\u{2026}" }
        if model.searchText.count == 1 { return "Type at least 2 characters to search" }
        if !model.searchText.isEmpty { return "No articles match \u{201C}\(model.searchText)\u{201D}" }
        switch selectedTag {
        case "starred": return "Star a story to keep it here."
        case "saved": return "Bookmark a story to read it later."
        default: return "Press \u{2318}R to refresh"
        }
    }

    // MARK: - Footer

    /// 24pt: the settings gear, the tier dot and the status line. ⌘⇧W toggles the widget.
    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                SettingsWindowController.shared.open(appDB: appDB, updaterController: updater)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tokens.secondaryText)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings")
            StreamStatusLine()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(tokens.card)
        .overlay(alignment: .top) { Rectangle().fill(tokens.cardBorder).frame(height: 1) }
        .background {
            Button("") {
                HeadlineWidgetController.shared.toggle(appDB: appDB, feedEngine: engine)
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])
            .hidden()
        }
    }

    // MARK: - Actions

    private func toggleSearch() {
        showSearch.toggle()
        if !showSearch { model.searchText = "" }
    }

    private func openArticle(_ article: ArticleInfo) {
        StreamText.open(article)
        Task { try? await appDB.markRead(article.articleID) }
    }

    private func markRead(_ articles: [ArticleInfo]) {
        let ids = articles.map(\.articleID)
        Task { try? await appDB.markRead(ids: ids) }
    }

    private func markAllRead() {
        Task {
            switch selectedTag {
            case "all": try? await appDB.markAllRead()
            case "digest", "starred", "saved": break
            default: try? await appDB.markAllRead(category: selectedTag)
            }
        }
    }

    private func openStory(_ story: DigestStory) {
        if let matched = model.articles.first(where: { $0.articleID == story.id }) {
            StreamText.open(matched)
        } else if let matched = model.articles.first(where: {
            ($0.title ?? "").localizedCaseInsensitiveContains(String(story.headline.prefix(20)))
        }) {
            StreamText.open(matched)
        } else {
            let query = story.headline.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? story.headline
            if let url = URL(string: "https://www.google.com/search?q=\(query)") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
