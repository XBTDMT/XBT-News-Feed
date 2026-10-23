import SwiftUI
import AppKit
import GRDB

/// Native Pro main window as the N2 "Inbox" window option draws it (chosen on 2026-09-07):
/// the popover at window size. No sidebar: a 56pt top bar with the markets strip beside the search
/// field (and refresh / mark read / settings glyphs), the popover's chip rail, then two panes — the
/// popover's own rows (dot, meta, title, snippet, thumbnail, coverage chips) with the recap card and
/// the since-you-last-looked divider in a 460pt list, and the reader in the rest — over the status
/// footer. Every piece is the popover's or a shared view; this file only composes them. The traffic
/// lights sit on the white top bar (`NativeProWindowChrome` hides the title bar).
struct NativeProWindow: View {
    let appDB: AppDatabase
    @Environment(FeedEngine.self) private var engine
    @State private var model: FeedListModel
    @State private var counts: UnreadCountsModel
    /// The chip rail's selection: nil is All, else a category id, "digest", "starred" or "saved".
    @State private var selectedCategory: String? = nil
    @State private var selectedArticle: ArticleInfo?
    @State private var webViewURL: URL?
    @State private var lastLooked: Date? = LastLookedStore.read()
    @State private var isVisible = false
    @State private var recapCardShown = false
    /// Every article in the database (the search placeholder).
    @State private var totalArticles = 0
    @State private var health = NativeProInboxLayout.HealthTally(total: 0, ok: 0, stale: 0, failing: 0)

    /// The popover's horizontal inset for rows, the recap card and the divider.
    private static let rowInset: CGFloat = 14
    /// The footer's "stale" colour (the sheet's #B25E00).
    private static let staleText = Color(light: "#B25E00", dark: "#FFB340")

    init(appDB: AppDatabase) {
        self.appDB = appDB
        _model = State(initialValue: FeedListModel(appDB: appDB))
        _counts = State(initialValue: UnreadCountsModel(appDB: appDB))
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .frame(height: NativeProInboxLayout.topBarHeight)

            chipRail
                .frame(height: NativeProInboxLayout.chipRailHeight)

            NativeProRule()

            HSplitView {
                listColumn
                    .frame(minWidth: NativeProInboxLayout.listWidth,
                           idealWidth: NativeProInboxLayout.listWidth,
                           maxWidth: NativeProInboxLayout.listMaxWidth)
                reader
                    .frame(minWidth: NativeProInboxLayout.readerMinWidth, maxWidth: .infinity)
            }

            NativeProRule()

            footer
                .frame(height: NativeProInboxLayout.footerHeight)
        }
        .background(NativeProPalette.surface.ignoresSafeArea())
        .background(NativeProWindowChrome())
        // The top bar runs under the transparent title bar; its 92pt left inset clears the lights.
        .ignoresSafeArea(.container, edges: .top)
        .task(id: selectedCategory) {
            // The Brief chip keeps the whole list observed so its stories can be matched into the reader.
            let category = (selectedCategory == "digest") ? nil : selectedCategory
            await model.observe(category: category)
        }
        .task { await counts.observe() }
        .task { await observeFeedHealth() }
        .task(id: isVisible) {
            guard isVisible else { return }
            await refreshTotals()
            await model.tickWhileVisible()
        }
        .task(id: model.searchText) { await model.runSearch(model.searchText) }
        // `make showcase` only: the reader opens on the lead story instead of "Select a story" (not marked read).
        .onChange(of: model.articles.first?.articleID) { _, _ in
            if engine.isShowcase, selectedArticle == nil { selectedArticle = model.articles.first }
        }
        .onAppear {
            isVisible = true
            lastLooked = LastLookedStore.read()
        }
        .onDisappear {
            // The window is the popover at window size, so closing it counts as having looked.
            isVisible = false
            LastLookedStore.markLooked()
            if recapCardShown {
                recapCardShown = false
                Task { await engine.markRecapRead() }
            }
        }
        .frame(minWidth: AppDesign.nativePro.mainWindowMinSize.width, minHeight: AppDesign.nativePro.mainWindowMinSize.height)
    }

    // MARK: - Top bar

    /// Markets strip (the sheet's 640, giving way on narrow windows), the popover's search field
    /// taking the rest, then refresh, mark-all-read and settings glyphs. The price credit is an overlay
    /// on the bar itself, 2pt above its bottom edge at the search text's x, in the slack under the
    /// field: nothing moves, and it can never leave the bar.
    private var topBar: some View {
        let markets = MarketsModel.display(prices: engine.latestPrices, history: engine.priceHistory)
        let credit = markets.rows.isEmpty ? nil : markets.credit
        return GeometryReader { geo in
            HStack(spacing: NativeProInboxLayout.topBarGap) {
                if !markets.rows.isEmpty {
                    NativeProMarketsStrip(rows: markets.rows)
                        .frame(width: NativeProInboxLayout.stripWidth(barWidth: geo.size.width))
                }
                NativeProSearchField(
                    text: $model.searchText,
                    placeholder: NativeProSearchField.placeholder(totalArticles: totalArticles))
                    .frame(maxWidth: .infinity)
                Button(action: { engine.refreshAll() }) {
                    if engine.isRefreshing {
                        ProgressView().controlSize(.small)
                            .frame(width: NativeProInboxLayout.glyphWidth, height: NativeProInboxLayout.glyphWidth)
                    } else {
                        glyph("arrow.clockwise")
                    }
                }
                .buttonStyle(.plain)
                .help("Refresh")
                Button(action: markAllRead) {
                    glyph("checkmark.circle")
                }
                .buttonStyle(.plain)
                .help("Mark all read")
                Button {
                    MenuActions.shared.openSettings(nil)
                } label: {
                    glyph("gearshape")
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
            .padding(.leading, NativeProInboxLayout.lightsInset)
            .padding(.trailing, NativeProInboxLayout.inset)
            .frame(width: geo.size.width, height: geo.size.height)
            .overlay(alignment: .bottomLeading) {
                if let credit {
                    MarketsCredit(text: credit, font: .system(size: 10), color: NativeProPalette.textTertiary)
                        .fixedSize()
                        .padding(.leading, NativeProInboxLayout.creditLeading(barWidth: geo.size.width,
                                                                              hasStrip: !markets.rows.isEmpty))
                        .padding(.bottom, NativeProInboxLayout.creditBottomInset)
                }
            }
        }
    }

    /// The popover's 16px header glyphs in #6E6E73.
    private func glyph(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(NativeProPalette.textSecondary)
            .frame(width: NativeProInboxLayout.glyphWidth, height: NativeProInboxLayout.glyphWidth)
    }

    // MARK: - Chip rail

    /// The popover's chip rail: registry-driven, drag-ordered, disabled categories hidden. FilterBar
    /// insets its chips by 14; the sheet's rail is inset 16, so 2 more here. Chips that run off the
    /// right edge fade out, as in the popover.
    private var chipRail: some View {
        FilterBar(selected: $selectedCategory, counts: counts.byCategory, total: counts.total,
                  enabledCategories: counts.enabledCategories)
            .padding(.horizontal, NativeProInboxLayout.inset - 14)
            .overlay(alignment: .trailing) {
                LinearGradient(
                    colors: [NativeProPalette.surface.opacity(0), NativeProPalette.surface],
                    startPoint: .leading, endPoint: UnitPoint(x: 0.7, y: 0.5))
                    .frame(width: 48)
                    .allowsHitTesting(false)
            }
    }

    // MARK: - List

    @ViewBuilder
    private var listColumn: some View {
        Group {
            if selectedCategory == "digest" {
                ScrollView {
                    BriefCard(digest: engine.dailyDigest, mode: .full, onStory: openStory,
                          onGenerate: { engine.refreshDigest() },
                          onClear: { Task { await engine.markBriefRead() } })
                        .padding(.horizontal, Self.rowInset)
                        .padding(.vertical, 8)
                }
            } else if model.displayed.isEmpty && model.webSearchResults.isEmpty && !model.isSearchingWeb {
                ContentUnavailableView {
                    Label(model.searchText.isEmpty ? "No Articles" : "No Results", systemImage: "newspaper")
                } description: {
                    if engine.isRefreshing {
                        Text("Fetching feeds\u{2026}")
                    } else if model.searchText.count == 1 {
                        Text("Type at least 2 characters to search")
                    } else if !model.searchText.isEmpty {
                        Text("No articles match \"\(model.searchText)\"")
                    } else {
                        Text("Press \u{2318}R to refresh")
                    }
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        let split = model.partition(lastLooked: lastLooked)
                        if model.searchText.isEmpty, split.newCount > 0, let recap = engine.lastRecap {
                            RecapCard(summary: recap, newCount: split.newCount, onMarkRead: {
                                Task { try? await appDB.markRead(ids: split.new.map(\.articleID)) }
                            })
                            .onAppear { recapCardShown = true }
                            .padding(EdgeInsets(top: 10, leading: Self.rowInset, bottom: 4, trailing: Self.rowInset))
                        }
                        ForEach(split.new) { article in
                            row(article)
                            NativeProHairline()
                        }
                        if model.searchText.isEmpty, !split.new.isEmpty, !split.seen.isEmpty {
                            NativeProSinceDivider(newCount: split.newCount, lastLooked: lastLooked, inset: Self.rowInset)
                            NativeProRule()
                        }
                        ForEach(split.seen) { article in
                            row(article)
                            NativeProHairline()
                        }
                        webResults
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NativeProPalette.surface)
    }

    /// The popover row; here a tap selects the story into the reader instead of opening the browser
    /// (the row's context menu still offers Open in Browser). The selected row sits on #EAF2FF.
    private func row(_ article: ArticleInfo) -> some View {
        NativeProArticleRow(
            article: article,
            appDB: appDB,
            onOpen: { select(article) },
            onDismiss: {
                Task { try? await appDB.markRead(article.articleID) }
            },
            timeRefreshTick: model.tick
        )
        .background(selectedArticle?.articleID == article.articleID ? NativeProPalette.selectedRow : Color.clear)
    }

    @ViewBuilder
    private var webResults: some View {
        if model.isSearchingWeb {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Searching the web\u{2026}").font(.system(size: 11)).foregroundStyle(NativeProPalette.textTertiary)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
        }
        if !model.webSearchResults.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: "globe").font(.system(size: 10, weight: .semibold))
                Text("Web Results").font(.system(size: 11, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(NativeProPalette.textTertiary)
            .padding(.horizontal, Self.rowInset)
            .padding(.vertical, 6)
            ForEach(model.webSearchResults) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                    Text(item.source).font(.system(size: 11)).foregroundStyle(NativeProPalette.textTertiary)
                }
                .padding(.horizontal, Self.rowInset)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    // Web results open in the reader pane, in reader mode.
                    selectedArticle = nil
                    if let url = URL(string: item.url) { webViewURL = url }
                }
                NativeProHairline()
            }
        }
    }

    // MARK: - Reader

    /// The existing reader in a column capped at the sheet's 760, centred in whatever the pane has.
    @ViewBuilder
    private var reader: some View {
        Group {
            if let url = webViewURL {
                ReaderWebView(url: url, isReaderMode: .constant(true), theme: AppDesign.current.readerTheme)
            } else if let article = selectedArticle {
                ArticleDetailView(article: article, appDB: appDB)
                    .frame(maxWidth: NativeProInboxLayout.readerColumnMaxWidth)
            } else {
                ContentUnavailableView("Select a story", systemImage: "newspaper")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NativeProPalette.surface)
    }

    // MARK: - Footer

    /// The status footer (tier glyph, dot, "AC · polled 2m ago · …") and, at the right, the feed
    /// health tally: "69 sources · 66 ok · 2 stale · 1 failing".
    private var footer: some View {
        HStack(spacing: 8) {
            StatusFooterView()
            Spacer(minLength: 8)
            healthText
                .font(.system(size: 11))
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.horizontal, Self.rowInset)
    }

    private var healthText: Text {
        guard health.total > 0 else { return Text("") }
        let dot = Text(" · ").foregroundStyle(NativeProPalette.textSecondary)
        var text = Text("\(health.total) source\(health.total == 1 ? "" : "s")").foregroundStyle(NativeProPalette.textSecondary)
            + dot + Text("\(health.ok) ok").foregroundStyle(NativeProPalette.up)
        if health.stale > 0 {
            text = text + dot + Text("\(health.stale) stale").foregroundStyle(Self.staleText)
        }
        if health.failing > 0 {
            text = text + dot + Text("\(health.failing) failing").foregroundStyle(NativeProPalette.down)
        }
        return text
    }

    // MARK: - Actions

    private func select(_ article: ArticleInfo) {
        webViewURL = nil
        selectedArticle = article
        Task { try? await appDB.markRead(article.articleID) }
    }

    /// Mark the selected category read (All marks everything; Brief, Starred and Saved are not lists to clear).
    private func markAllRead() {
        Task {
            if let cat = selectedCategory, cat != "starred", cat != "saved", cat != "digest" {
                try? await appDB.markAllRead(category: cat)
            } else if selectedCategory == nil {
                try? await appDB.markAllRead()
            }
        }
    }

    /// A brief story opens in the reader: the matching article when the list has it, else a web
    /// search for its headline in reader mode.
    private func openStory(_ story: DigestStory) {
        if let matched = model.articles.first(where: { $0.articleID == story.id }) ?? model.articles.first(where: {
            ($0.title ?? "").localizedCaseInsensitiveContains(String(story.headline.prefix(20)))
        }) {
            select(matched)
        } else {
            let query = story.headline.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? story.headline
            if let url = URL(string: "https://www.google.com/search?q=\(query)") {
                selectedArticle = nil
                webViewURL = url
            }
        }
    }

    // MARK: - Observation

    /// The one figure that only changes as feeds poll: total articles, for the search placeholder.
    private func refreshTotals() async {
        guard let total = try? await appDB.dbPool.read({ db in try Article.fetchCount(db) }) else { return }
        totalArticles = total
    }

    /// Health of every enabled feed, live, tallied for the footer.
    private func observeFeedHealth() async {
        let observation = ValueObservation.tracking { db -> NativeProInboxLayout.HealthTally in
            let feeds = try Feed.filter(Column("isEnabled") == true).fetchAll(db)
            return NativeProInboxLayout.HealthTally(healths: feeds.map { $0.health() })
        }
        do {
            for try await tally in observation.values(in: appDB.dbPool) {
                health = tally
            }
        } catch {
            // Observation cancelled
        }
    }
}
