import SwiftUI
import AppKit
import Sparkle

/// Deck (R2-Deck-B): "XBTDMT Feed" header, a two-column grid of tiles (Breaking, Markets, Brief,
/// Unread) and a row of three small ones (Starred, Saved, Search). A tap expands a tile in place —
/// full width, with its row-mates as header-only strips beneath it — one at a time; ⌘-click opens
/// the window on that section. Capped at 400×600 and scrolls inside.
struct DeckPopover: View {
    let appDB: AppDatabase
    let updater: SPUStandardUpdaterController
    @Environment(FeedEngine.self) private var engine
    @ObservedObject private var power = PowerMonitor.shared
    @State private var model: FeedListModel
    @State private var recapCardShown = false
    @State private var counts: UnreadCountsModel
    @State private var expanded: DeckTileID?
    @State private var breakingCount = 0
    @State private var stats = DeckStats()
    @State private var lastLooked: Date? = LastLookedStore.read()
    @State private var isVisible = false

    private static let topRow: [DeckTileID] = [.breaking, .markets]
    private static let middleRow: [DeckTileID] = [.brief, .unread]
    private static let bottomRow: [DeckTileID] = [.starred, .saved, .search]

    init(appDB: AppDatabase, updater: SPUStandardUpdaterController) {
        self.appDB = appDB
        self.updater = updater
        _model = State(initialValue: FeedListModel(appDB: appDB))
        _counts = State(initialValue: UnreadCountsModel(appDB: appDB))
    }

    private var context: DeckTileContext {
        DeckTileContext(
            appDB: appDB, expanded: $expanded, openWindow: openWindow(section:),
            lastLooked: lastLooked, tick: model.tick)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)

            ScrollView {
                VStack(spacing: DeckLayout.gap) {
                    if unreadNewCount > 0, let recap = engine.lastRecap {
                        RecapCard(summary: recap, newCount: unreadNewCount)
                        .onAppear { recapCardShown = true }
                    }
                    gridRow(Self.topRow)
                    gridRow(Self.middleRow)
                    gridRow(Self.bottomRow)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
            }

            footer
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 12)
        }
        .background(DeckPalette.canvas)
        .frame(width: AppDesign.deck.popoverSize.width, height: AppDesign.deck.popoverSize.height)
        .task { await model.observe(category: nil) }
        .task { await counts.observe() }
        .task { await observeBreakingCount() }
        .task { await observeStats() }
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
            expanded = nil
            LastLookedStore.markLooked()
            if recapCardShown {
                recapCardShown = false
                Task { await engine.markRecapRead() }
            }
        }
    }

    // MARK: - Derived

    /// Unread breaking stories first, then important; the observation is newest-first already.
    private var breakingStories: [ArticleInfo] {
        let unread = model.articles.filter { $0.isRead != true }
        return unread.filter { $0.priority == "breaking" } + unread.filter { $0.priority == "important" }
    }

    private var unreadNewCount: Int {
        SinceLastLooked.partition(
            model.articles.filter { $0.isRead != true }, arrival: { $0.arrivalDate }, lastLooked: lastLooked
        ).newCount
    }

    // MARK: - Grid

    /// One grid row: side by side while nothing in it is expanded; otherwise the expanded tile full
    /// width with its row-mates as strips beneath it (`DeckLayout.rowLayout`).
    @ViewBuilder
    private func gridRow(_ ids: [DeckTileID]) -> some View {
        let layout = DeckLayout.rowLayout(ids, expanded: expanded)
        if let expandedID = layout.expanded {
            VStack(spacing: DeckLayout.gap) {
                tile(expandedID, strip: false)
                HStack(spacing: DeckLayout.gap) {
                    ForEach(layout.strips, id: \.self) { id in tile(id, strip: true) }
                }
            }
        } else {
            HStack(alignment: .top, spacing: DeckLayout.gap) {
                ForEach(ids, id: \.self) { id in tile(id, strip: false) }
            }
        }
    }

    @ViewBuilder
    private func tile(_ id: DeckTileID, strip: Bool) -> some View {
        switch id {
        case .breaking:
            DeckBreakingTile(stories: breakingStories, breakingCount: breakingCount, ctx: context, strip: strip)
        case .markets:
            let markets = MarketsModel.display(prices: engine.latestPrices, history: engine.priceHistory)
            DeckMarketsTile(rows: markets.rows, providers: markets.providers, tier: power.tier, ctx: context, strip: strip)
        case .brief:
            DeckBriefTile(
                digest: engine.dailyDigest, ctx: context, onStory: openStory,
                onGenerate: { engine.refreshDigest() },
                onClear: { Task { await engine.markBriefRead() } }, strip: strip)
        case .unread:
            DeckUnreadTile(
                byCategory: counts.byCategory, total: counts.total, newCount: unreadNewCount, ctx: context, strip: strip,
                categories: DeckLayout.visible(counts.enabledCategories))
        case .starred:
            if strip {
                DeckSmallStrip(id: .starred, symbol: "star.fill", symbolColor: DeckPalette.gold,
                               primary: "\(stats.starred)", secondary: "Starred", ctx: context)
            } else if expanded == .starred {
                DeckListTile(id: .starred, symbol: "star.fill", symbolColor: DeckPalette.gold, title: "Starred",
                             count: stats.starred, ctx: context)
            } else {
                DeckSmallTile(id: .starred, symbol: "star.fill", symbolColor: DeckPalette.gold,
                              primary: "\(stats.starred)", secondary: "Starred", ctx: context)
            }
        case .saved:
            if strip {
                DeckSmallStrip(id: .saved, symbol: "bookmark.fill", symbolColor: DeckPalette.accent,
                               primary: "\(stats.saved)", secondary: "Saved", ctx: context)
            } else if expanded == .saved {
                DeckListTile(id: .saved, symbol: "bookmark.fill", symbolColor: DeckPalette.accent, title: "Saved",
                             count: stats.saved, ctx: context)
            } else {
                DeckSmallTile(id: .saved, symbol: "bookmark.fill", symbolColor: DeckPalette.accent,
                              primary: "\(stats.saved)", secondary: "Saved", ctx: context)
            }
        case .search:
            if strip {
                DeckSmallStrip(id: .search, symbol: "magnifyingglass", symbolColor: DeckPalette.text,
                               primary: stats.total.formatted(), secondary: "Search", ctx: context)
            } else if expanded == .search {
                DeckSearchTile(model: model, total: stats.total, ctx: context)
            } else {
                DeckSmallTile(id: .search, symbol: "magnifyingglass", symbolColor: DeckPalette.text,
                              primary: "Search", secondary: stats.total.formatted(), primaryIsValue: false, ctx: context)
            }
        }
    }

    // MARK: - Header and footer

    /// "XBTDMT Feed  (23)  Updated 2m … ⤢ ↻ ✓ ⚙" — four 14pt glyphs in the sheet's grey.
    private var header: some View {
        HStack(spacing: 8) {
            Text(AppInfo.shortName).font(.system(size: 15, weight: .bold)).foregroundStyle(DeckPalette.text)
            if counts.total > 0 {
                Text(counts.total > 999 ? CompactCount.format(counts.total) : "\(counts.total)")
                    .font(.system(size: 11, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1)
                    .background(DeckPalette.red, in: Capsule())
            }
            if let lastUpdated = model.lastUpdated {
                let _ = model.tick
                Text(Self.updatedText(lastUpdated))
                    .font(.system(size: 11))
                    .foregroundStyle(DeckPalette.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            HStack(spacing: 10) {
                headerGlyph("arrow.up.left.and.arrow.down.right", help: "Open in window") {
                    openWindow(section: "overview")
                }
                Button(action: { engine.refreshAll() }) {
                    if engine.isRefreshing {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DeckPalette.secondary)
                    }
                }
                .buttonStyle(.plain)
                .frame(width: 16, height: 16)
                .help("Refresh")
                .keyboardShortcut("r", modifiers: .command)
                headerGlyph("checkmark.circle", help: "Mark all read") {
                    Task { try? await appDB.markAllRead() }
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                headerGlyph("gearshape", help: "Settings") {
                    SettingsWindowController.shared.open(appDB: appDB, updaterController: updater)
                }
            }
        }
        .frame(height: 22)
    }

    private func headerGlyph(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DeckPalette.secondary)
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// Two 16pt lines: the hint and the source count, then the live status line (idea ③).
    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tap a tile to expand · \u{2318}-click opens the window")
                    .font(.system(size: 11))
                    .foregroundStyle(DeckPalette.tertiary)
                    .lineLimit(1)
                Spacer()
                if stats.feeds > 0 {
                    Text("\(stats.feeds) sources")
                        .font(.system(size: 11))
                        .foregroundStyle(DeckPalette.tertiary)
                }
            }
            .frame(height: 16)
            DeckStatusLine()
                .frame(height: 16)
        }
        .background {
            Button("") {
                HeadlineWidgetController.shared.toggle(appDB: appDB, feedEngine: engine)
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])
            .hidden()
        }
    }

    // MARK: - Observations

    private func observeBreakingCount() async {
        do {
            for try await n in AppDatabase.breakingUnreadCountObservation().values(in: appDB.dbPool) {
                breakingCount = n
            }
        } catch {
            // cancelled
        }
    }

    private func observeStats() async {
        do {
            for try await s in DeckStats.observation().values(in: appDB.dbPool) {
                stats = s
            }
        } catch {
            // cancelled
        }
    }

    // MARK: - Actions

    private func openWindow(section: String) {
        DeckNavigation.shared.request(section)
        MainWindowController.shared.open(appDB: appDB, feedEngine: engine)
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

    /// "Updated 2m" (the sheet drops "ago"); "Updated now" inside the first minute.
    static func updatedText(_ date: Date) -> String {
        let rel = date.relativeTime
        return rel == "now" ? "Updated now" : "Updated \(rel)"
    }
}

/// Idea ③ as the sheet draws it: a 6pt tier dot then "AC · polled 2m ago · next in 3m · 18 requests,
/// 0.6 MB" in 11pt tabular grey, refreshed every 30 s. No tier glyph (no sheet draws one).
struct DeckStatusLine: View {
    @Environment(FeedEngine.self) private var engine
    @ObservedObject private var power = PowerMonitor.shared
    @State private var now = Date()

    var body: some View {
        HStack(spacing: 6) {
            DeckDot(color: dotColor)
            Text(line)
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(DeckPalette.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                now = Date()
            }
        }
    }

    private var line: String {
        StatusLine.format(
            tier: power.tier, now: now, lastTickAt: engine.lastTickAt, nextTickAt: engine.nextTickAt,
            requests: engine.lastTickStats?.requests, bytes: engine.lastTickStats?.bytes)
    }

    private var dotColor: Color {
        switch power.tier {
        case .ac: return DeckPalette.green
        case .battery: return DeckPalette.gold
        case .critical: return DeckPalette.red
        }
    }
}
