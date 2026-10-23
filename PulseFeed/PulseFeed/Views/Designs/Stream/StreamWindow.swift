import SwiftUI
import AppKit
import GRDB

/// Stream main window (min 1100×720): no sidebar. A white 52pt toolbar carries the title, the
/// segmented chips, search, a grid/list toggle and the settings gear; the stream fills the left as
/// two independent columns of cards — a hero card for the lead with its picture at 16:9 of the
/// column, 120pt-band hero cards for 3-source clusters, a story card with a 64pt thumbnail (on AC)
/// for everything else — split by the coral divider (list mode groups everything into 34pt rows);
/// a 260pt rail holds five market cards, Today's Brief, unread by category and the Starred/Saved
/// counters. A story opens as a 520pt card centred over the dimmed stream while the rail stays live.
struct StreamWindow: View {
    enum ViewMode { case grid, list }

    let appDB: AppDatabase
    @Environment(FeedEngine.self) private var engine
    @Environment(\.designTokens) private var tokens
    @ObservedObject private var power = PowerMonitor.shared
    @State private var model: FeedListModel
    @State private var counts: UnreadCountsModel
    @State private var selectedTag = "all"
    @State private var viewMode: ViewMode = .grid
    @State private var selectedArticle: ArticleInfo?
    @State private var webViewURL: URL?
    @State private var lastLooked: Date? = LastLookedStore.read()
    @State private var isVisible = false
    @State private var starredCount = 0
    @State private var savedCount = 0
    @State private var articleTotal = 0

    init(appDB: AppDatabase) {
        self.appDB = appDB
        _model = State(initialValue: FeedListModel(appDB: appDB))
        _counts = State(initialValue: UnreadCountsModel(appDB: appDB))
    }

    /// The rail's bars: the categories that are switched on, in registry order.
    private var railCategories: [(tag: String, label: String, short: String)] {
        NewsCategory.top(counts.visibleCategories, counts: counts.byCategory, limit: 6).map { ($0.id, $0.label, $0.short) }
    }

    /// The rail's market subtitles, keyed by engine id.
    private static let marketSubtitles: [String: String] = [
        "bitcoin": "Bitcoin", "mag7": "Mag Seven", "spy": "S&P 500", "gold": "per oz", "dxy": "Dollar index",
    ]

    private var observedCategory: String? {
        (selectedTag == "all" || selectedTag == "digest") ? nil : selectedTag
    }

    private var policy: ImagePolicy { ImageGate.policy(for: power.tier) }
    private var detailOpen: Bool { selectedArticle != nil || webViewURL != nil }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            HStack(alignment: .top, spacing: 16) {
                streamPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                rail
                    .frame(width: 260)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .padding(16)
        }
        .background(tokens.canvas)
        .frame(minWidth: AppDesign.stream.mainWindowMinSize.width, minHeight: AppDesign.stream.mainWindowMinSize.height)
        .task(id: observedCategory) { await model.observe(category: observedCategory) }
        .task { await counts.observe() }
        .task { await observeCounters() }
        .task { await observeArticleTotal() }
        .task(id: isVisible) {
            guard isVisible else { return }
            await model.tickWhileVisible()
        }
        .task(id: model.searchText) { await model.runSearch(model.searchText) }
        .onAppear {
            isVisible = true
            lastLooked = LastLookedStore.read()
        }
        .onDisappear { isVisible = false }
        .background {
            // The sheet's toolbar has no refresh or mark-all-read glyphs; the shortcuts stay.
            Button("") { engine.refreshAll() }
                .keyboardShortcut("r", modifiers: .command)
                .hidden()
            Button("", action: markAllRead)
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .hidden()
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 14) {
            Text(AppInfo.displayName).padding(.leading, 62)
                .font(tokens.font(14, weight: .heavy))
                .tracking(-0.14)
                .lineLimit(1)
                .fixedSize()
            StreamChipRow(selected: $selectedTag, style: .segmented, enabled: counts.enabledCategories)
                .frame(maxWidth: 640)
            Spacer(minLength: 8)
            searchField
                .frame(width: 190)
            viewToggle
            Button {
                MenuActions.shared.openSettings(nil)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(tokens.secondaryText)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(tokens.card)
        .overlay(alignment: .bottom) { Rectangle().fill(tokens.cardBorder).frame(height: 1) }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(StreamPalette.faint)
            TextField(
                articleTotal > 0 ? "Search \(articleTotal.formatted()) articles" : "Search articles",
                text: $model.searchText
            )
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
        .frame(height: 30)
        .background(tokens.canvas, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// Grid (cards in two columns) or list (34pt rows), the sheet's bordered two-cell toggle.
    private var viewToggle: some View {
        HStack(spacing: 0) {
            toggleCell("square.grid.2x2", mode: .grid, help: "Cards")
            toggleCell("line.3.horizontal", mode: .list, help: "List")
        }
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(tokens.cardBorder, lineWidth: 1))
    }

    private func toggleCell(_ symbol: String, mode: ViewMode, help: String) -> some View {
        let isOn = viewMode == mode
        return Button {
            viewMode = mode
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isOn ? Color.white : tokens.secondaryText)
                .frame(width: 29, height: 24)
                .background(isOn ? StreamPalette.scrim : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Stream pane and detail overlay

    private var streamPane: some View {
        ZStack {
            listContent
            if detailOpen {
                StreamPalette.scrim.opacity(0.22)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: closeDetail)
                    .transition(.opacity)
                StreamDetailCard(
                    article: selectedArticle, webURL: webViewURL, appDB: appDB, tick: model.tick, onClose: closeDetail)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: tokens.radius, style: .continuous))
        .animation(.easeInOut(duration: 0.2), value: detailOpen)
    }

    @ViewBuilder
    private var listContent: some View {
        if selectedTag == "digest" {
            ScrollView(showsIndicators: false) {
                BriefCard(digest: engine.dailyDigest, mode: .full, onStory: openStory,
                          onGenerate: { engine.refreshDigest() },
                          onClear: { Task { await engine.markBriefRead() } })
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .streamCard()
            }
        } else if model.displayed.isEmpty && model.webSearchResults.isEmpty && !model.isSearchingWeb {
            StreamEmptyState(title: emptyTitle, message: emptyMessage)
        } else {
            let split = model.partition(lastLooked: lastLooked)
            let cardsAllowed = viewMode == .grid && selectedTag != "starred" && selectedTag != "saved"
                && model.searchText.isEmpty
            let heroID = cardsAllowed ? StreamLayout.hero(in: model.displayed)?.articleID : nil
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    section(split.new, heroID: heroID, cardsAllowed: cardsAllowed, dimmed: false)
                    if model.searchText.isEmpty, !split.new.isEmpty, !split.seen.isEmpty {
                        StreamSinceDivider(newCount: split.newCount, lastLooked: lastLooked, spacing: 10, onMarkRead: {
                            markRead(split.new)
                        })
                    }
                    section(split.seen, heroID: heroID, cardsAllowed: cardsAllowed, dimmed: true)
                    StreamWebResults(model: model, onOpen: { url in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedArticle = nil
                            webViewURL = url
                        }
                    })
                }
                .padding(.bottom, 8)
            }
        }
    }

    /// Two independent columns (stories alternate left, right) of hero and story cards; or, when
    /// cards are off, one row group.
    @ViewBuilder
    private func section(_ articles: [ArticleInfo], heroID: String?, cardsAllowed: Bool, dimmed: Bool) -> some View {
        if articles.isEmpty {
            EmptyView()
        } else if !cardsAllowed {
            StreamRowGroup(articles: articles, appDB: appDB, dimmed: dimmed, tick: model.tick, onOpen: select)
        } else {
            let left = articles.enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
            let right = articles.enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
            HStack(alignment: .top, spacing: 12) {
                column(left, heroID: heroID, dimmed: dimmed)
                column(right, heroID: heroID, dimmed: dimmed)
            }
        }
    }

    private func column(_ articles: [ArticleInfo], heroID: String?, dimmed: Bool) -> some View {
        LazyVStack(spacing: 10) {
            ForEach(articles) { article in
                if StreamLayout.isCard(article, heroID: heroID) {
                    let isLead = article.articleID == heroID
                    // The lead's picture is 16:9 of the column; cluster cards keep the sheet's 120pt band.
                    StreamHeroCard(
                        article: article, appDB: appDB, variant: .window,
                        showImage: isLead ? policy != .none : policy == .heroAndThumbnails,
                        isLead: isLead, bandHeight: isLead ? nil : 120, tick: model.tick,
                        onOpen: { select(article) })
                } else {
                    StreamStoryCard(
                        article: article, appDB: appDB, dimmed: dimmed, showThumbnail: policy == .heroAndThumbnails,
                        tick: model.tick, onOpen: { select(article) })
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Rail

    private var rail: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 8) {
                let markets = MarketsModel.display(prices: engine.latestPrices, history: engine.priceHistory)
                ForEach(markets.chosen, id: \.id) { entry in
                    if let quote = engine.latestPrices[entry.id] {
                        marketCard(
                            key: entry.id, label: entry.label, quote: quote,
                            history: engine.priceHistory[entry.id] ?? [])
                    }
                }
                // The price credit for the cards drawn above, 10pt, tucked under the last card.
                if let credit = markets.credit {
                    MarketsCredit(text: credit, font: tokens.font(10), color: StreamPalette.faint)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 4)
                        .padding(.top, -4)
                }
                briefCard
                unreadByCategory
                HStack(spacing: 8) {
                    counter(symbol: "star.fill", color: StreamPalette.star, count: starredCount, label: "Starred", tag: "starred")
                    counter(symbol: "bookmark.fill", color: tokens.accent, count: savedCount, label: "Saved", tag: "saved")
                }
            }
        }
    }

    /// 50pt: label and subtitle, an 86×26 line sparkline, price and two-decimal change.
    private func marketCard(key: String, label: String, quote: PriceUpdate, history: [Double]) -> some View {
        let color = changeColor(quote.change24h)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(tokens.font(12.5, weight: .heavy)).lineLimit(1)
                Text(Self.marketSubtitles[key] ?? "")
                    .font(tokens.font(11))
                    .foregroundStyle(StreamPalette.faint)
                    .lineLimit(1)
            }
            .frame(width: 50, alignment: .leading)
            if history.count >= 2 {
                StreamSparkline(data: history)
                    .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    .frame(width: 86, height: 26)
            } else {
                Color.clear.frame(width: 86, height: 26)
            }
            VStack(alignment: .trailing, spacing: 1) {
                Text(PriceFormatting.price(quote.price, symbol: label))
                    .font(tokens.font(12.5, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                if let change = StreamText.change(quote.change24h, decimals: 2) {
                    Text(change)
                        .font(tokens.font(11, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(color)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
        .streamCard()
    }

    private func changeColor(_ pct: Double?) -> Color {
        guard let pct, !StreamText.isFlat(pct) else { return StreamPalette.faint }
        return pct >= 0 ? tokens.ok : tokens.breaking
    }

    /// Today's Brief as the rail draws it: sun, title and mood chip; the summary; the story count;
    /// then WHAT TO WATCH. Tapping opens the Brief tab.
    private var briefCard: some View {
        Button {
            selectedTag = "digest"
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "sun.max")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(tokens.accent)
                    Text("Today's Brief").font(tokens.font(13, weight: .heavy))
                    Spacer(minLength: 4)
                    if let mood = engine.dailyDigest?.marketMood { moodChip(mood) }
                }
                if let digest = engine.dailyDigest {
                    Text(digest.summary)
                        .font(tokens.font(12))
                        .foregroundStyle(StreamPalette.ink2)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(digest.topStories.count) stories · \(digest.isFallback ? "basic brief" : Self.briefAuthor)")
                        .font(tokens.font(11))
                        .foregroundStyle(StreamPalette.faint)
                    if !digest.whatToWatch.isEmpty {
                        Rectangle().fill(tokens.cardBorder).frame(height: 1)
                        Text("WHAT TO WATCH")
                            .font(tokens.font(11, weight: .heavy))
                            .tracking(0.88)
                            .foregroundStyle(tokens.secondaryText)
                        Text(digest.whatToWatch.joined(separator: " · "))
                            .font(tokens.font(12))
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Generating brief…").font(tokens.font(11)).foregroundStyle(StreamPalette.faint)
                    }
                    .task { engine.refreshDigest() }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .streamCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open Today's Brief")
    }

    /// The brief prefers Claude when a key exists (`preferOnDevice: false`), else the on-device model.
    private static var briefAuthor: String {
        (AIService.getAPIKey()?.isEmpty == false) ? "written by Claude" : "written on-device"
    }

    private func moodChip(_ mood: String) -> some View {
        let lower = mood.lowercased()
        let bullish = lower.contains("bull") || lower.contains("positive") || lower.contains("risk-on")
        let bearish = lower.contains("bear") || lower.contains("negative") || lower.contains("risk-off")
        let foreground: Color = bullish ? tokens.ok : (bearish ? tokens.breaking : StreamPalette.amberText)
        let fill: Color = bullish ? tokens.ok.opacity(0.16) : (bearish ? tokens.breaking.opacity(0.14) : StreamPalette.amberFill)
        return Text("Mood: " + lower)
            .font(tokens.font(11, weight: .heavy))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 19)
            .background(fill, in: Capsule())
    }

    /// A six-bar coral chart, 30pt tall, with the category and its count under each bar.
    private var unreadByCategory: some View {
        let categories = railCategories
        let values = categories.map { counts.count(for: $0.tag) }
        let maxCount = max(1, values.max() ?? 1)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Unread by category").font(tokens.font(12, weight: .heavy))
                Spacer()
                Text(counts.total.formatted()).font(tokens.font(12, weight: .heavy)).monospacedDigit()
            }
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(categories.enumerated()), id: \.element.tag) { index, item in
                    let n = values[index]
                    Button {
                        selectedTag = item.tag
                    } label: {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(tokens.accent.opacity(n == 0 ? 0.25 : 1))
                            .frame(height: max(4, 30 * CGFloat(n) / CGFloat(maxCount)))
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: 30, alignment: .bottom)
            HStack(alignment: .top, spacing: 6) {
                ForEach(Array(categories.enumerated()), id: \.element.tag) { index, item in
                    VStack(spacing: 0) {
                        Text(item.short)
                            .font(tokens.font(11))
                            .foregroundStyle(selectedTag == item.tag ? tokens.accent : tokens.secondaryText)
                        Text(CompactCount.format(values[index]))
                            .font(tokens.font(11, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(selectedTag == item.tag ? tokens.accent : tokens.secondaryText)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .streamCard()
    }

    private func counter(symbol: String, color: Color, count: Int, label: String, tag: String) -> some View {
        Button {
            selectedTag = tag
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(color)
                Text("\(count)").font(tokens.font(12, weight: .bold)).monospacedDigit()
                Text(label).font(tokens.font(12)).foregroundStyle(tokens.secondaryText)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .frame(maxWidth: .infinity)
            .streamCard()
            .overlay(
                RoundedRectangle(cornerRadius: tokens.radius, style: .continuous)
                    .stroke(selectedTag == tag ? tokens.accent : Color.clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty state copy

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

    // MARK: - Actions

    private func select(_ article: ArticleInfo) {
        withAnimation(.easeInOut(duration: 0.2)) {
            webViewURL = nil
            selectedArticle = article
        }
        Task { try? await appDB.markRead(article.articleID) }
    }

    private func closeDetail() {
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedArticle = nil
            webViewURL = nil
        }
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
        if let matched = model.articles.first(where: { $0.articleID == story.id }) ?? model.articles.first(where: {
            ($0.title ?? "").localizedCaseInsensitiveContains(String(story.headline.prefix(20)))
        }) {
            selectedTag = "all"
            select(matched)
        }
    }

    /// Live Starred and Saved counts for the rail (primaries only, like the lists).
    private func observeCounters() async {
        let observation = ValueObservation.tracking { db -> (starred: Int, saved: Int) in
            let base = """
                FROM articleStatus
                JOIN article ON article.articleID = articleStatus.articleID
                WHERE article.clusterID IS NULL AND
                """
            let starred = try Int.fetchOne(db, sql: "SELECT COUNT(*) " + base + " articleStatus.isStarred = 1") ?? 0
            let saved = try Int.fetchOne(db, sql: "SELECT COUNT(*) " + base + " articleStatus.isSaved = 1") ?? 0
            return (starred, saved)
        }
        do {
            for try await pair in observation.values(in: appDB.dbPool) {
                starredCount = pair.starred
                savedCount = pair.saved
            }
        } catch {
            // Observation cancelled
        }
    }

    /// The search field's placeholder counts every stored article ("Search 16,680 articles").
    private func observeArticleTotal() async {
        let observation = ValueObservation.tracking { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM article") ?? 0
        }
        do {
            for try await total in observation.values(in: appDB.dbPool) {
                articleTotal = total
            }
        } catch {
            // Observation cancelled
        }
    }
}

// MARK: - Detail card

/// The sheet's detail: a 520pt card centred over the dimmed stream. A 120pt image (or the slate
/// gradient) carries the priority pill and coverage chips and a white close circle; below, the
/// title in 22pt heavy, "Source · Category · 19m · Also in …", the Star / Save / Listen / Share row
/// with "Open in Browser", the summary in a violet box, then the article text. A web result shows
/// the reader under a short header instead.
struct StreamDetailCard: View {
    let article: ArticleInfo?
    let webURL: URL?
    let appDB: AppDatabase
    var tick = false
    let onClose: () -> Void
    @Environment(\.designTokens) private var tokens
    @State private var summary: String?
    @State private var isLoadingSummary = false
    @State private var fullText: String?
    @State private var isStarred = false
    @State private var isSaved = false
    @State private var isReaderMode = true
    @StateObject private var speech = SpeechManager()
    @AppStorage("speechRate") private var speechRate = 0.5

    private var url: URL? {
        if let article, let urlString = article.url { return URL(string: urlString) }
        return webURL
    }

    var body: some View {
        VStack(spacing: 0) {
            if let article {
                imageHeader(article)
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(article.title ?? "Untitled")
                            .font(tokens.font(22, weight: .heavy))
                            .tracking(-0.33)
                            .fixedSize(horizontal: false, vertical: true)
                        metaLine(article)
                        actions(article)
                        summaryBox
                        if let text = fullText ?? article.contentText, !text.isEmpty {
                            Text(text)
                                .font(tokens.font(13.5))
                                .foregroundStyle(StreamPalette.ink2)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.top, 14)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if let webURL {
                webHeader
                ReaderWebView(url: webURL, isReaderMode: $isReaderMode, theme: AppDesign.current.readerTheme)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 520)
        .frame(maxHeight: 640)
        .background(tokens.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(StreamPalette.scrim.opacity(0.06), lineWidth: 1))
        .shadow(color: StreamPalette.scrim.opacity(0.30), radius: 32, x: 0, y: 24)
        .task(id: article?.articleID) { await load() }
        .onDisappear { speech.stop() }
    }

    private func imageHeader(_ article: ArticleInfo) -> some View {
        Color.clear
            .frame(height: 120)
            .frame(maxWidth: .infinity)
            .overlay {
                if let imageURLString = article.imageURL, let imageURL = URL(string: imageURLString) {
                    AsyncImage(url: imageURL) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            StreamPalette.detailGradient
                        }
                    }
                } else {
                    StreamPalette.detailGradient
                }
            }
            .clipped()
            .overlay(alignment: .topLeading) {
                HStack(spacing: 6) {
                    StreamPriorityPill(priority: article.priority, size: .card)
                    StreamSourceChips(article: article, appDB: appDB, size: .card)
                }
                .padding(12)
            }
            .overlay(alignment: .topTrailing) { closeButton.padding(12) }
    }

    private var webHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe").font(.system(size: 11, weight: .bold)).foregroundStyle(tokens.secondaryText)
            Text("Web result").font(tokens.font(11, weight: .bold)).foregroundStyle(tokens.secondaryText)
            Spacer()
            closeButton
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .overlay(alignment: .bottom) { Rectangle().fill(tokens.cardBorder).frame(height: 1) }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(StreamPalette.scrim)
                .frame(width: 26, height: 26)
                .background(Color.white.opacity(0.9), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Close")
        .keyboardShortcut(.escape, modifiers: [])
    }

    private func metaLine(_ article: ArticleInfo) -> some View {
        HStack(spacing: 6) {
            Text(article.feedTitle)
                .font(tokens.font(12, weight: .bold))
                .foregroundStyle(StreamPalette.ink)
                .lineLimit(1)
            Text("· \(StreamText.category(article.feedCategory)) · \(article.dateArrived.relativeTime)")
                .font(tokens.font(12))
                .foregroundStyle(tokens.secondaryText)
                .lineLimit(1)
            let others = StreamText.others(article)
            if !others.isEmpty {
                Text("· Also in " + others.joined(separator: ", "))
                    .font(tokens.font(12))
                    .foregroundStyle(StreamPalette.faint)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private func actions(_ article: ArticleInfo) -> some View {
        HStack(spacing: 8) {
            actionButton(isStarred ? "star.fill" : "star", isStarred ? "Starred" : "Star", active: isStarred) {
                isStarred.toggle()
                Task { try? await appDB.toggleStarred(article.articleID) }
            }
            actionButton(isSaved ? "bookmark.fill" : "bookmark", isSaved ? "Saved" : "Save", active: isSaved) {
                isSaved.toggle()
                Task { try? await appDB.toggleSaved(article.articleID) }
            }
            actionButton(
                speech.isSpeaking ? "stop.fill" : "speaker.wave.2", speech.isSpeaking ? "Stop" : "Listen",
                active: speech.isSpeaking
            ) {
                if speech.isSpeaking {
                    speech.stop()
                } else {
                    let text = fullText ?? article.contentText ?? article.title ?? ""
                    if !text.isEmpty { speech.speak(text, rate: speechRate) }
                }
            }
            if let url {
                actionLabel("square.and.arrow.up", "Share", active: false)
                    .overlay { StreamSharePicker(url: url) }
            }
            Spacer(minLength: 0)
            if let url {
                Button("Open in Browser") { NSWorkspace.shared.open(url) }
                    .buttonStyle(.plain)
                    .font(tokens.font(12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 28)
                    .background(tokens.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private func actionButton(_ symbol: String, _ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            actionLabel(symbol, title, active: active)
        }
        .buttonStyle(.plain)
    }

    private func actionLabel(_ symbol: String, _ title: String, active: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(active ? tokens.accent : tokens.secondaryText)
            Text(title)
                .font(tokens.font(12, weight: active ? .bold : .regular))
                .foregroundStyle(active ? tokens.accent : StreamPalette.ink)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(active ? tokens.accent : tokens.cardBorder, lineWidth: 1))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var summaryBox: some View {
        if isLoadingSummary || (summary?.isEmpty == false) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(StreamPalette.summaryGlyph)
                    Text(AIGate.prefersOnDevice() ? "Summary · on-device" : "Summary · Claude")
                        .font(tokens.font(12, weight: .heavy))
                        .foregroundStyle(StreamPalette.summaryInk)
                }
                if isLoadingSummary {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Summarising…").font(tokens.font(12)).foregroundStyle(tokens.secondaryText)
                    }
                } else if let summary {
                    Text(summary)
                        .font(tokens.font(13.5))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(StreamPalette.summaryFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func load() async {
        speech.stop()
        summary = nil
        isLoadingSummary = false
        fullText = nil
        guard let article else { return }
        isStarred = article.isStarred ?? false
        isSaved = article.isSaved ?? false
        // ArticleInfo.contentText is a 400-char preview; the full Article record has the body.
        let text = try? await appDB.fetchArticles(ids: [article.articleID]).first?.contentText
        guard !Task.isCancelled else { return }
        fullText = text
        if let existing = article.summary, !existing.isEmpty {
            summary = existing
            return
        }
        isLoadingSummary = true
        let result = await AIGate.shared.enrichAndStore(articleID: article.articleID, appDB: appDB, userInitiated: true)
        guard !Task.isCancelled else { return }
        summary = result
        isLoadingSummary = false
    }
}

/// A transparent NSButton laid over the styled Share label so the sharing picker anchors to it.
private struct StreamSharePicker: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.title = ""
        button.isBordered = false
        button.isTransparent = true
        button.target = context.coordinator
        button.action = #selector(Coordinator.share(_:))
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.url = url
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    @MainActor
    final class Coordinator: NSObject {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        @objc func share(_ sender: NSButton) {
            let picker = NSSharingServicePicker(items: [url])
            picker.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }
}
