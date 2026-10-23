import SwiftUI
import AppKit

/// Deck main window — D2 "Board" (the window option chosen on 2026-09-07, borrowed from R5 Board): a
/// dashboard in Deck's clothes. A 52pt top bar (brand, unread badge, "Updated now · 69 sources",
/// search, Starred and Saved pills, refresh, settings), then a six-column grid: five sparkline
/// market cards, Breaking and Brief across the top; beneath, Since you last looked (the recap and
/// the new stories), Top stories (coverage × recency), Unread by category and Sources. A story
/// opens as a 460pt card that slides in from the right over Unread and Sources and slides back on
/// `esc`; the board stays live underneath. The popover is untouched and reads as the board's
/// top-left corner.
struct DeckWindow: View {
    let appDB: AppDatabase
    @Environment(FeedEngine.self) private var engine
    /// Every unread primary — the board's one observation (Since, Top stories, Breaking, search).
    @State private var model: FeedListModel
    /// The slide-over list's own observation (starred, saved or a category).
    @State private var listModel: FeedListModel
    @State private var counts: UnreadCountsModel
    @State private var stats = DeckStats()
    @State private var breakingCount = 0
    /// Unread primaries since you last looked — the menu bar's number, not the list's capped one.
    @State private var newSinceCount = 0
    @State private var panel: DeckBoardPanel?
    @State private var lastLooked: Date? = LastLookedStore.read()
    @State private var isVisible = false
    @State private var debugStoryOpened = false
    private let nav = DeckNavigation.shared

    init(appDB: AppDatabase) {
        self.appDB = appDB
        _model = State(initialValue: FeedListModel(appDB: appDB))
        _listModel = State(initialValue: FeedListModel(appDB: appDB))
        _counts = State(initialValue: UnreadCountsModel(appDB: appDB))
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            GeometryReader { geo in
                let column = DeckBoardLayout.columnWidth(boardWidth: geo.size.width)
                let markets = MarketsModel.display(prices: engine.latestPrices, history: engine.priceHistory)
                let credit = markets.credit
                VStack(spacing: DeckBoardLayout.gap) {
                    VStack(spacing: 0) {
                        topRow(column: column, markets: markets)
                            .frame(height: DeckBoardLayout.topRowHeight)
                        // The price credit's own line, right-aligned under the market cards; the widget
                        // row below gives up its height (DeckBoardLayout.widgetRowHeight).
                        if let credit {
                            MarketsCredit(text: credit, font: .system(size: 10), color: DeckPalette.tertiary)
                                .padding(.top, 2)
                                .frame(width: DeckBoardLayout.span(4, column: column),
                                       height: DeckBoardLayout.creditRowHeight, alignment: .topTrailing)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    ZStack(alignment: .topTrailing) {
                        widgetRow(column: column)
                        if let panel {
                            DeckBoardPanelView(
                                panel: panel, appDB: appDB, model: model, listModel: listModel,
                                digest: engine.dailyDigest, tick: model.tick,
                                onOpenArticle: open(_:), onOpenWeb: { show(.web($0)) },
                                onStory: openDigestStory(_:), onGenerate: { engine.refreshDigest() },
                                onClear: { Task { await engine.markBriefRead() } },
                                onClose: closePanel)
                            .frame(width: DeckBoardLayout.readerWidth(column: column))
                            .frame(maxHeight: .infinity)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: DeckBoardLayout.widgetRowHeight(boardHeight: geo.size.height, hasCredit: credit != nil))
                }
                .padding(.horizontal, DeckBoardLayout.sideInset)
                .padding(.top, DeckBoardLayout.topInset)
                .padding(.bottom, DeckBoardLayout.bottomInset)
            }
        }
        .background(DeckPalette.canvas)
        .background {
            if panel != nil {
                Button("") { closePanel() }
                    .keyboardShortcut(.escape, modifiers: [])
                    .hidden()
            }
        }
        .task { await model.observe(category: nil) }
        .task { await counts.observe() }
        .task { await observeStats() }
        .task { await observeBreakingCount() }
        .task(id: lastLooked) { await observeNewSince() }
        .task(id: panel?.listTag) {
            guard let tag = panel?.listTag else { return }
            listModel.articles = []
            await listModel.observe(category: tag)
        }
        .task(id: isVisible) {
            guard isVisible else { return }
            await model.tickWhileVisible()
        }
        .task(id: model.searchText) { await model.runSearch(model.searchText) }
        .onChange(of: model.searchText) { _, text in
            if text.count >= 2 {
                if panel != .search { show(.search) }
            } else if text.isEmpty, panel == .search {
                closePanel()
            }
        }
        .onChange(of: model.articles.isEmpty) { openDebugStoryIfRequested() }
        .onAppear {
            isVisible = true
            lastLooked = LastLookedStore.read()
            if let section = nav.consume() { select(section) }
        }
        .onChange(of: nav.requestID) {
            if let section = nav.consume() { select(section) }
        }
        .onDisappear { isVisible = false }
        .frame(minWidth: AppDesign.deck.mainWindowMinSize.width, minHeight: AppDesign.deck.mainWindowMinSize.height)
    }

    // MARK: - Derived

    /// The unread list split against the last-looked time (idea ①). Always the observation, never
    /// the search results, so the board does not reshuffle while you type.
    private var split: SinceLastLooked.Partition<ArticleInfo> {
        SinceLastLooked.partition(model.articles, arrival: { $0.arrivalDate }, lastLooked: lastLooked)
    }

    /// Unread breaking stories first, then important; the observation is newest-first already.
    private var breakingStories: [ArticleInfo] {
        model.articles.filter { $0.priority == "breaking" } + model.articles.filter { $0.priority == "important" }
    }

    /// Re-ranked on every tick, so a cluster slides down as it ages.
    private var topStories: [ArticleInfo] {
        _ = model.tick
        return TopStories.rank(model.articles, now: Date(), limit: DeckBoardLayout.topStoriesLimit)
    }

    // MARK: - Top bar

    /// "XBTDMT Feed (1.7k) Updated now · 69 sources … [Search] ★ 0 ▮ 0 ↻ ⚙" on 52pt, clear of the
    /// traffic lights.
    private var topBar: some View {
        HStack(spacing: 12) {
            Text(AppInfo.shortName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(DeckPalette.text)
                .lineLimit(1)
            if counts.total > 0 {
                Text(counts.total > 999 ? CompactCount.format(counts.total) : "\(counts.total)")
                    .font(.system(size: 11, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 1)
                    .background(DeckPalette.red, in: Capsule())
            }
            Text(updatedText)
                .font(.system(size: 11))
                .foregroundStyle(DeckPalette.tertiary)
                .lineLimit(1)
            Spacer(minLength: 12)
            searchField
            topPill("star.fill", color: DeckPalette.gold, count: stats.starred, help: "Starred") { show(.list("starred")) }
            topPill("bookmark.fill", color: DeckPalette.accent, count: stats.saved, help: "Saved") { show(.list("saved")) }
            Button(action: { engine.refreshAll() }) {
                if engine.isRefreshing {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DeckPalette.secondary)
                }
            }
            .buttonStyle(.plain)
            .frame(width: 18, height: 18)
            .help("Refresh")
            Button {
                MenuActions.shared.openSettings(nil)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DeckPalette.secondary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.leading, DeckBoardLayout.trafficLightInset)
        .padding(.trailing, DeckBoardLayout.sideInset)
        .frame(height: DeckBoardLayout.topBarHeight)
    }

    /// "Updated 2m · 69 sources" — "Updated now" inside the first minute, as the popover says it.
    private var updatedText: String {
        _ = model.tick
        var parts: [String] = []
        if let lastUpdated = model.lastUpdated { parts.append(DeckPopover.updatedText(lastUpdated)) }
        if stats.feeds > 0 { parts.append("\(stats.feeds) sources") }
        return parts.joined(separator: " · ")
    }

    /// The 260×26 white field with the magnifier inside and a hairline; typing opens the search
    /// panel, clearing closes it.
    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DeckPalette.tertiary)
            TextField(stats.total > 0 ? "Search \(stats.total.formatted()) articles" : "Search\u{2026}", text: $model.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !model.searchText.isEmpty {
                Button {
                    model.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(DeckPalette.quaternary)
                }
                .buttonStyle(.plain)
                .help("Clear")
            }
        }
        .padding(.horizontal, 8)
        .frame(width: 260, height: 26)
        .background(DeckPalette.card, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.black.opacity(0.10), lineWidth: 0.5))
    }

    /// "★ 0" — a white pill; opens that list in the slide-over.
    private func topPill(_ symbol: String, color: Color, count: Int, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(color)
                Text("\(count)").font(.system(size: 11, weight: .semibold)).monospacedDigit().foregroundStyle(DeckPalette.text)
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(DeckPalette.card, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.black.opacity(0.10), lineWidth: 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Grid

    /// Five market cards over four columns, then Breaking and Brief, one column each.
    private func topRow(column: CGFloat, markets: MarketsDisplay) -> some View {
        let marketsWidth = DeckBoardLayout.span(4, column: column)
        let cardWidth = (marketsWidth - 4 * DeckBoardLayout.gap) / 5
        return HStack(spacing: DeckBoardLayout.gap) {
            HStack(spacing: DeckBoardLayout.gap) {
                ForEach(markets.chosen, id: \.id) { entry in
                    DeckBoardMarketCard(label: entry.label, row: markets.rows.first { $0.id == entry.id })
                        .frame(width: cardWidth)
                }
            }
            .frame(width: marketsWidth)
            DeckBoardBreakingCard(
                stories: breakingStories, breakingCount: breakingCount, lastLooked: lastLooked, onOpen: open(_:)
            )
            .frame(width: column)
            DeckBoardBriefCard(digest: engine.dailyDigest, onOpen: { show(.brief) }, onGenerate: { engine.refreshDigest() })
                .frame(width: column)
        }
    }

    /// Since you last looked (two columns), Top stories (two), Unread, Sources.
    private func widgetRow(column: CGFloat) -> some View {
        HStack(alignment: .top, spacing: DeckBoardLayout.gap) {
            DeckBoardSinceCard(
                split: split, newCount: max(newSinceCount, split.newCount), recap: engine.lastRecap,
                lastLooked: lastLooked, appDB: appDB, tick: model.tick,
                selectedID: panel?.articleID, onOpen: open(_:), onMarkRead: markNewRead
            )
            .frame(width: DeckBoardLayout.span(2, column: column))
            DeckBoardTopStoriesCard(
                stories: topStories, appDB: appDB, tick: model.tick, selectedID: panel?.articleID, onOpen: open(_:)
            )
            .frame(width: DeckBoardLayout.span(2, column: column))
            DeckBoardUnreadCard(
                byCategory: counts.byCategory, total: counts.total, categories: counts.visibleCategories,
                onOpen: { show(.list($0)) }
            )
            .frame(width: column)
            DeckBoardSourcesCard(stats: stats, onStarred: { show(.list("starred")) }, onSaved: { show(.list("saved")) })
                .frame(width: column)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Panel actions

    /// Opens a story in the slide-over. The story is marked read when the card closes or moves on
    /// to another story, so its row stays on the board, highlighted, while it is being read.
    private func open(_ article: ArticleInfo) {
        if case .article(let current) = panel, current.articleID != article.articleID {
            markRead(current)
        }
        withAnimation(.easeInOut(duration: 0.25)) { panel = .article(article) }
    }

    private func show(_ next: DeckBoardPanel) {
        if case .article(let current) = panel { markRead(current) }
        withAnimation(.easeInOut(duration: 0.25)) { panel = next }
    }

    private func closePanel() {
        if case .article(let current) = panel { markRead(current) }
        withAnimation(.easeInOut(duration: 0.25)) { panel = nil }
    }

    private func markRead(_ article: ArticleInfo) {
        guard article.isRead != true else { return }
        Task { try? await appDB.markRead(article.articleID) }
    }

    /// "Mark these read" on the Since card: exactly the stories that arrived since you last looked.
    private func markNewRead() {
        let ids = split.new.map(\.articleID)
        Task { try? await appDB.markRead(ids: ids) }
    }

    /// A section handed over by the popover (a bar tap, a ⌘-click): the board itself for Overview
    /// and All, the brief, or a list.
    private func select(_ section: String) {
        switch section {
        case "overview", "all":
            if panel != nil { closePanel() }
        case "digest":
            show(.brief)
        default:
            show(.list(section))
        }
    }

    /// A story in the brief: the matching article in the slide-over when the list has it, else the
    /// outlet's page (the popover does the same), else a search.
    private func openDigestStory(_ story: DigestStory) {
        if let matched = model.articles.first(where: { $0.articleID == story.id }) ?? model.articles.first(where: {
            ($0.title ?? "").localizedCaseInsensitiveContains(String(story.headline.prefix(20)))
        }) {
            open(matched)
            return
        }
        let query = story.headline.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? story.headline
        if let url = URL(string: "https://www.google.com/search?q=\(query)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// `PULSEFEED_DEBUG_OPEN=window,story` opens the newest story in the slide-over once the list
    /// has loaded, so the reader can be screenshotted without a mouse.
    private func openDebugStoryIfRequested() {
        guard !debugStoryOpened, DebugOpen.wants("story"), let first = split.new.first ?? model.articles.first else { return }
        debugStoryOpened = true
        open(first)
    }

    // MARK: - Observations

    private func observeStats() async {
        do {
            for try await s in DeckStats.observation().values(in: appDB.dbPool) {
                stats = s
            }
        } catch {
            // cancelled
        }
    }

    private func observeNewSince() async {
        do {
            for try await n in AppDatabase.newSinceObservation(since: lastLooked).values(in: appDB.dbPool) {
                newSinceCount = n
            }
        } catch {
            // cancelled
        }
    }

    private func observeBreakingCount() async {
        do {
            for try await n in AppDatabase.breakingUnreadCountObservation().values(in: appDB.dbPool) {
                breakingCount = n
            }
        } catch {
            // cancelled
        }
    }
}
