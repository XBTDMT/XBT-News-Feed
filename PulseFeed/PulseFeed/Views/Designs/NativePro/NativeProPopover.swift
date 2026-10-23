import SwiftUI
import AppKit
import GRDB
import Sparkle

/// Native Pro (R1-NativePro-B): "Today" header, markets strip, chips with unread counts, the list
/// with the since-you-last-looked divider and coverage chips, and the live status footer. Every
/// measurement here is the sheet's: a white surface, 14pt insets, 6pt between the header pieces.
struct NativeProPopover: View {
    let appDB: AppDatabase
    let updater: SPUStandardUpdaterController
    @Environment(FeedEngine.self) private var engine
    @State private var model: FeedListModel
    @State private var recapCardShown = false
    @State private var counts: UnreadCountsModel
    @State private var selectedCategory: String? = nil
    @State private var lastLooked: Date? = LastLookedStore.read()
    @State private var isVisible = false
    /// Whether the price credit fits in the header's free space (it then sits right above the strip);
    /// when it does not, the strip carries it under its columns instead.
    @State private var creditInHeader = true
    /// Every article in the database (the search placeholder).
    @State private var totalArticles = 0

    /// The sheet's horizontal inset for every popover element.
    private static let inset: CGFloat = 14

    init(appDB: AppDatabase, updater: SPUStandardUpdaterController) {
        self.appDB = appDB
        self.updater = updater
        _model = State(initialValue: FeedListModel(appDB: appDB))
        _counts = State(initialValue: UnreadCountsModel(appDB: appDB))
    }

    var body: some View {
        let markets = MarketsModel.display(prices: engine.latestPrices, history: engine.priceHistory)
        let credit = markets.rows.isEmpty ? nil : markets.credit
        VStack(spacing: 0) {
            header(credit: credit)
                .padding(.horizontal, Self.inset)
                .padding(.top, 8)
                .padding(.bottom, 6)

            if !markets.rows.isEmpty {
                NativeProMarketsStrip(rows: markets.rows, credit: creditInHeader ? nil : credit)
                    .padding(.horizontal, Self.inset)
            }

            // FilterBar insets its chips by the sheet's 14 and pads 6 above and below; the sheet's
            // 48pt fade covers the chips that run off the right edge.
            FilterBar(selected: $selectedCategory, counts: counts.byCategory, total: counts.total,
                      enabledCategories: counts.enabledCategories)
                .overlay(alignment: .trailing) {
                    LinearGradient(
                        colors: [NativeProPalette.surface.opacity(0), NativeProPalette.surface],
                        startPoint: .leading, endPoint: UnitPoint(x: 0.7, y: 0.5))
                        .frame(width: 48)
                        .allowsHitTesting(false)
                }

            NativeProSearchField(
                text: $model.searchText,
                placeholder: NativeProSearchField.placeholder(totalArticles: totalArticles))
                .padding(.horizontal, Self.inset)
                .padding(.bottom, 6)

            NativeProRule()

            content

            NativeProRule()

            footer
                .padding(.horizontal, Self.inset)
                .padding(.vertical, 8)
        }
        .frame(width: AppDesign.nativePro.popoverSize.width, height: AppDesign.nativePro.popoverSize.height)
        .background(NativeProPalette.surface)
        .task(id: selectedCategory) { await model.observe(category: selectedCategory) }
        .task { await counts.observe() }
        .task(id: isVisible) {
            guard isVisible else { return }
            await refreshTotals()
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
    }

    // MARK: - Pieces

    /// "Today", the unread badge and "Updated …" at the left, the three glyphs at the right; the price
    /// credit rides on the Spacer between them (10pt, against the glyphs) whenever it fits there.
    private func header(credit: String?) -> some View {
        HStack(spacing: 10) {
            Text("Today")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(NativeProPalette.text)
            if counts.total > 0 {
                Text(counts.total > 999 ? "999+" : "\(counts.total)")
                    .font(.system(size: 11, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1)
                    .background(NativeProPalette.breaking, in: Capsule())
            }
            if let lastUpdated = model.lastUpdated {
                let _ = model.tick
                Text(Self.updatedText(lastUpdated))
                    .font(.system(size: 11))
                    .foregroundStyle(NativeProPalette.textTertiary)
                    .lineLimit(1)
            }
            MarketsCreditSlot(credit: credit, minLength: 8, color: NativeProPalette.textTertiary,
                              fits: $creditInHeader)
            Button {
                MainWindowController.shared.open(appDB: appDB, feedEngine: engine)
            } label: {
                headerGlyph("arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.plain)
            .help("Open in window")
            Button(action: { engine.refreshAll() }) {
                if engine.isRefreshing {
                    ProgressView().controlSize(.small).frame(width: 16, height: 16)
                } else {
                    headerGlyph("arrow.clockwise")
                }
            }
            .buttonStyle(.plain)
            .help("Refresh")
            .keyboardShortcut("r", modifiers: .command)
            Button(action: markAllRead) {
                headerGlyph("checkmark.circle")
            }
            .buttonStyle(.plain)
            .help("Mark all read")
            .keyboardShortcut("a", modifiers: [.command, .shift])
        }
    }

    /// The sheet's 16px header glyphs in #6E6E73.
    private func headerGlyph(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(NativeProPalette.textSecondary)
            .frame(width: 16, height: 16)
    }

    @ViewBuilder
    private var content: some View {
        if selectedCategory == "digest" {
            ScrollView {
                BriefCard(digest: engine.dailyDigest, mode: .full, onStory: openStory,
                          onGenerate: { engine.refreshDigest() },
                          onClear: { Task { await engine.markBriefRead() } })
                    .padding(.horizontal, Self.inset)
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
            .frame(maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    let split = model.partition(lastLooked: lastLooked)
                    if model.searchText.isEmpty, split.newCount > 0, let recap = engine.lastRecap {
                        RecapCard(summary: recap, newCount: split.newCount, onMarkRead: {
                            Task { try? await appDB.markRead(ids: split.new.map(\.articleID)) }
                        })
                        .onAppear { recapCardShown = true }
                        .padding(EdgeInsets(top: 8, leading: Self.inset, bottom: 6, trailing: Self.inset))
                    }
                    ForEach(split.new) { article in
                        row(article)
                        NativeProHairline()
                    }
                    if model.searchText.isEmpty, !split.new.isEmpty, !split.seen.isEmpty {
                        NativeProSinceDivider(newCount: split.newCount, lastLooked: lastLooked, inset: Self.inset)
                        NativeProRule()
                    }
                    ForEach(split.seen) { article in
                        row(article)
                        NativeProHairline()
                    }
                    webResults
                }
            }
            // The sheet fades the last row into the footer over 24pt.
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [NativeProPalette.surface.opacity(0), NativeProPalette.surface],
                    startPoint: .top, endPoint: .bottom)
                    .frame(height: 24)
                    .allowsHitTesting(false)
            }
        }
    }

    private func row(_ article: ArticleInfo) -> some View {
        NativeProArticleRow(
            article: article,
            appDB: appDB,
            onOpen: {
                if let urlString = article.url, let url = URL(string: urlString) {
                    NSWorkspace.shared.open(url)
                }
                Task { try? await appDB.markRead(article.articleID) }
            },
            onDismiss: {
                Task { try? await appDB.markRead(article.articleID) }
            },
            timeRefreshTick: model.tick
        )
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
            .padding(.horizontal, Self.inset)
            .padding(.vertical, 6)
            ForEach(model.webSearchResults) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                    Text(item.source).font(.system(size: 11)).foregroundStyle(NativeProPalette.textTertiary)
                }
                .padding(.horizontal, Self.inset)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    if let url = URL(string: item.url) { NSWorkspace.shared.open(url) }
                }
                NativeProHairline()
            }
        }
    }

    /// The sheet's footer: settings gear, tier dot, the status line, nothing at the right. The window
    /// opens from the header's expand glyph; ⌘⇧W still toggles the widget.
    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                SettingsWindowController.shared.open(appDB: appDB, updaterController: updater)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(NativeProPalette.textSecondary)
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .help("Settings")
            NativeProStatusLine()
            Spacer(minLength: 0)
        }
        .background {
            Button("") {
                HeadlineWidgetController.shared.toggle(appDB: appDB, feedEngine: engine)
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])
            .hidden()
        }
    }

    // MARK: - Actions

    private func markAllRead() {
        Task {
            if let cat = selectedCategory, cat != "starred", cat != "saved", cat != "digest" {
                try? await appDB.markAllRead(category: cat)
            } else if selectedCategory != "digest" {
                try? await appDB.markAllRead()
            }
        }
    }

    private func openStory(_ story: DigestStory) {
        if let matched = model.articles.first(where: { $0.articleID == story.id }),
           let urlString = matched.url, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        } else if let matched = model.articles.first(where: {
            ($0.title ?? "").localizedCaseInsensitiveContains(String(story.headline.prefix(20)))
        }), let urlString = matched.url, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        } else {
            let query = story.headline.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? story.headline
            if let url = URL(string: "https://www.google.com/search?q=\(query)") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// The one figure that only changes as feeds poll: total articles, for the search placeholder.
    private func refreshTotals() async {
        guard let total = try? await appDB.dbPool.read({ db in try Article.fetchCount(db) }) else { return }
        totalArticles = total
    }

    static func updatedText(_ date: Date) -> String {
        let rel = date.relativeTime
        return rel == "now" ? "Updated now" : "Updated \(rel) ago"
    }
}
