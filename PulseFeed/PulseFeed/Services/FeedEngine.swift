@preconcurrency import Foundation
import AppKit
import UserNotifications
import Combine
import Network
import GRDB

/// One line of instrumentation per tick, so the cost of a poll is a measured number.
struct TickStats: Sendable {
    let tier: PowerTier
    var feeds = 0
    var requests = 0
    var bytes = 0
    var inserted = 0
    var upserted = 0
    var clustered = 0
    var dropped = 0
    var enriched = 0
    var notified = 0
    var writes = 0
    var duration: TimeInterval = 0
}

@MainActor
@Observable
final class FeedEngine {
    let appDB: AppDatabase

    /// One configured session for every feed/JSON fetch (was declared and never used).
    nonisolated static let feedSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = false   // fail fast offline; the network monitor re-ticks on reconnect
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.httpMaximumConnectionsPerHost = 4
        // A browser-shaped User-Agent: some publishers (Autocar) answer a bare CFNetwork UA with an
        // HTML challenge page instead of the feed.
        config.httpAdditionalHeaders = [
            "User-Agent": "PulseFeed/1.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Safari/605.1.15",
        ]
        return URLSession(configuration: config)
    }()

    private let rssFetcher = RSSFetcher(session: FeedEngine.feedSession)
    private let jsonFetcher = JSONFetcher(session: FeedEngine.feedSession)
    private let aiService = AIService()
    private let notificationService = NotificationService()

    /// Stories the social-image backfill already looked at this run (a miss is not retried).
    private var imageBackfillTried: Set<String> = []
    let rateLimiter = RateLimiter()
    let webSocketManager = WebSocketManager()
    let digestService = DigestService()

    private var started = false
    private var tickInProgress = false
    private var feedScheduler: NSBackgroundActivityScheduler?
    private var webSocketTask: Task<Void, Never>?
    private var alertsTask: Task<Void, Never>?
    private var sleepObserver: Any?
    private var wakeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var lastTier: PowerTier?
    private var pathMonitor: NWPathMonitor?
    private var networkWasAvailable = true
    private var cachedAlerts: [PriceAlert] = []
    private var lastCryptoFetch = Date.distantPast
    private var lastQuotesFetch = Date.distantPast
    /// Each coin's price 24 h ago, from the last CoinGecko answer, so a stream that sends only prices
    /// (Gemini) can still show the day's change.
    private(set) var cryptoOpen24h: [String: Double] = [:]
    /// Idea: urgent alerts are capped; overflow rides the summary.
    private var urgencyBudget = UrgencyBudget(perHour: UrgencyRules.stored().perHour, perDay: UrgencyRules.stored().perDay)
    private var lastPriceUIUpdate = Date.distantPast

    private(set) var isRefreshing = false
    private(set) var latestPrices: [String: PriceUpdate] = [:]
    private(set) var topHeadlines: [String] = []
    private(set) var priceHistory: [String: [Double]] = [:]
    private(set) var dailyDigest: DailyDigest?
    private(set) var nextTickAt: Date?
    private(set) var lastTickStats: TickStats?
    /// When the last tick finished (idea ③ status footer: "polled 2m ago").
    private(set) var lastTickAt: Date?
    /// The most recent recap notification (also the popover's recap card).
    private(set) var lastRecap: SummaryText? = {
        guard let body = UserDefaults.standard.string(forKey: SummaryComposer.lastTextKey) else { return nil }
        let subtitle = UserDefaults.standard.string(forKey: SummaryComposer.lastSubtitleKey) ?? ""
        return SummaryText(title: "What's new", subtitle: subtitle, body: body)
    }()
    /// The stories that recap covered; emptied once the recap has been read.
    private(set) var lastRecapIDs: [String] = SummaryComposer.loadLastIDs()

    /// Reading the recap (closing the popover with its card shown, or tapping the banner) reads the
    /// stories it covered and their copies from other outlets. Later arrivals stay unread.
    func markRecapRead() async {
        let ids = lastRecapIDs
        guard !ids.isEmpty, !isShowcase else { return }
        try? await appDB.markReadIncludingCluster(ids: ids)
        lastRecapIDs = []
        SummaryComposer.saveLastIDs([])
        print("PulseFeed: [Recap] read: \(ids.count) stories marked read")
    }

    /// Clearing the brief: "I have read this, I am caught up." Everything unread in an enabled feed
    /// goes read whenever it arrived — before the brief's window, inside it, or in the hours behind
    /// it while the brief sat cached — and then every surface that reports unread is reset with it:
    /// the recap's pending IDs are dropped so it cannot re-assert its own stories, and the
    /// since-you-last-looked watermark moves to now so the divider and the menu bar count agree.
    /// Anything less leaves one of them still claiming there is something to read.
    @discardableResult
    func markBriefRead() async -> Int {
        guard !isShowcase else { return 0 }
        let count = (try? await appDB.markAllUnreadReadInEnabledFeeds()) ?? 0
        lastRecapIDs = []
        SummaryComposer.saveLastIDs([])
        LastLookedStore.markLooked()
        print("PulseFeed: [Brief] cleared: \(count) stories marked read")
        return count
    }

    init(appDB: AppDatabase) {
        self.appDB = appDB
    }

    // MARK: - Showcase

    /// True on the engine `make showcase` draws from: never started, its state set once by `showcase(…)`.
    /// Nothing a view triggers then fetches, generates a brief or marks a story read, so every surface
    /// draws the same fictional state.
    private(set) var isShowcase = false

    /// The state a real tick would leave behind, from `ShowcaseFixture`.
    func showcase(prices: [PriceUpdate], recap: SummaryText, recapIDs: [String], digest: DailyDigest,
                  headlines: [String], lastTickAt: Date, nextTickAt: Date, stats: TickStats) {
        isShowcase = true
        for p in prices {
            latestPrices[p.symbol] = p
            priceHistory[p.symbol] = p.sparklineData
        }
        lastRecap = recap
        lastRecapIDs = recapIDs
        dailyDigest = digest
        topHeadlines = headlines
        self.lastTickAt = lastTickAt
        self.nextTickAt = nextTickAt
        lastTickStats = stats
    }

    // MARK: - Lifecycle

    /// Called once from the app delegate at launch (not from a view, so polling never waits for
    /// the popover to be opened).
    func start() {
        guard !started else { return }
        started = true
        lastTier = PowerMonitor.shared.tier
        print("PulseFeed: [Engine] start (tier \(PowerMonitor.shared.tier))")

        Task { await updateTopHeadlines() }
        refreshDigest()
        startAlertsObservation()
        startWebSockets()
        observeSleepWake()
        observePower()
        startNetworkMonitor()

        Task.detached { [appDB] in
            if let cleaned = try? await appDB.cleanupOldArticles(), cleaned > 0 {
                print("PulseFeed: [Engine] cleaned up \(cleaned) old articles")
            }
            let window = UserDefaults.standard.object(forKey: "unread_window_days") as? Int ?? 2
            if window > 0, let aged = try? await appDB.markReadOlderThan(days: window), aged > 0 {
                print("PulseFeed: [Engine] unread window \(window)d: marked \(aged) older stories read")
            }
        }

        Task { [weak self] in
            await self?.tick()
            await self?.scheduleNextTick()
        }
    }

    func stop() {
        feedScheduler?.invalidate()
        feedScheduler = nil
        cancellables.removeAll()
        webSocketTask?.cancel()
        webSocketTask = nil
        alertsTask?.cancel()
        alertsTask = nil
        pathMonitor?.cancel()
        pathMonitor = nil
        Task { await webSocketManager.stop() }
        removeSleepWakeObservers()
        started = false
    }

    /// Manual refresh — bypasses poll intervals, fetches every enabled polling feed.
    func refreshAll() {
        Task { [weak self] in
            await self?.tick(forceAll: true)
            await self?.scheduleNextTick()
        }
    }

    /// Wake / network-regained: poll now if anything is due, then re-arm.
    func tickNow(reason: String) {
        print("PulseFeed: [Engine] tick now (\(reason))")
        Task { [weak self] in
            await self?.tick()
            await self?.scheduleNextTick()
        }
    }

    // MARK: - Scheduling

    /// AC: fire when the soonest feed is due (60s floor). Battery: every 5 minutes.
    /// Critical: every 30 minutes. Re-armed after every tick so the interval tracks the feeds.
    private func scheduleNextTick() async {
        feedScheduler?.invalidate()
        guard started else { return }

        let tier = PowerMonitor.shared.tier
        let feedsDue = try? await appDB.soonestDueIn(types: Self.pollTypes(for: tier))
        let pricesDue = MarketsSchedule.secondsUntilDue(
            tier: tier, now: Date(), lastCrypto: lastCryptoFetch, lastQuotes: lastQuotesFetch, instruments: wantedInstruments())
        let soonest = [feedsDue, pricesDue].compactMap { $0 }.min()
        let delay = PollScheduling.nextTickDelay(tier: tier, soonestDueIn: soonest)

        // One-shot: `interval` is "the suggested interval between scheduling and invoking" (SDK header),
        // and we re-arm after every tick so the cadence follows the feeds. The system may fire up to
        // `tolerance` early or late; an early fire just finds nothing due and re-arms.
        let scheduler = NSBackgroundActivityScheduler(identifier: "com.pulsefeed.rss-polling")
        scheduler.repeats = false
        scheduler.interval = delay
        scheduler.tolerance = PollScheduling.tolerance(tier: tier, delay: delay)
        scheduler.qualityOfService = .utility

        nonisolated(unsafe) let schedulerRef = scheduler
        scheduler.schedule { [weak self] completion in
            if schedulerRef.shouldDefer {
                completion(.deferred)
                return
            }
            Task { @MainActor in
                guard let self else { completion(.finished); return }
                await self.tick()
                completion(.finished)
                await self.scheduleNextTick()
            }
        }
        feedScheduler = scheduler
        nextTickAt = Date().addingTimeInterval(delay)
        print("PulseFeed: [Sched] \(Date().sqliteString) next tick in \(Int(delay))s (tier \(tier), soonest due in \(soonest.map { Int($0) } ?? -1)s)")
    }

    /// Critical battery: news only (prices keep one CoinGecko call: `fetchMarketsIfDue`).
    private static func pollTypes(for tier: PowerTier) -> [String] {
        tier == .critical ? ["rss"] : ["rss", "json_api"]
    }

    // MARK: - Polling Tick

    private func tick(forceAll: Bool = false) async {
        guard !isShowcase else { return }
        guard !tickInProgress else {
            print("PulseFeed: [Tick] skipped, a tick is already running")
            return
        }
        tickInProgress = true
        isRefreshing = true
        defer {
            tickInProgress = false
            isRefreshing = false
        }

        let startedAt = Date()
        let tier = PowerMonitor.shared.tier
        var stats = TickStats(tier: tier)

        var feeds: [Feed]
        do {
            feeds = forceAll
                ? try await appDB.fetchAllEnabledPollingFeeds(types: Self.pollTypes(for: tier))
                : try await appDB.fetchDueFeeds(types: Self.pollTypes(for: tier))
        } catch {
            print("PulseFeed: [Tick] ERROR fetching feeds: \(error)")
            return
        }
        guard !feeds.isEmpty else {
            print("PulseFeed: [Tick] \(Date().sqliteString) nothing due")
            await fetchMarketsIfDue(tier: tier, stats: &stats)
            return
        }
        stats.feeds = feeds.count

        // Dedup index: built ONCE per tick from a slim projection, shared by every feed.
        let candidates = (try? await appDB.fetchDedupCandidates()) ?? []
        let index = DedupIndex(candidates: candidates)
        let knownByFeed = Dictionary(grouping: candidates, by: \.feedID)
            .mapValues { Set($0.map(\.uniqueID)) }

        let rss = rssFetcher
        let json = jsonFetcher
        var results: [FeedRefreshResult] = []
        await withTaskGroup(of: FeedRefreshResult.self) { group in
            for feed in feeds {
                let known = knownByFeed[feed.id] ?? []
                group.addTask {
                    await Self.refreshFeed(feed, rss: rss, json: json, index: index, knownUniqueIDs: known)
                }
            }
            for await result in group { results.append(result) }
        }

        // Cluster cross-feed copies that arrived in this same tick, then ONE insert transaction.
        let toInsert = DedupIndex.clusterAmong(results.flatMap(\.toInsert))
        let toUpsert = results.flatMap(\.toUpsert)
        var insertedIDs: [String] = []
        var upsertedNewIDs: [String] = []
        if !toInsert.isEmpty {
            insertedIDs = (try? await appDB.insertArticles(toInsert, readIfPublishedBefore: Self.oldNewsCutoff())) ?? []
            stats.writes += 1
        }
        if !toUpsert.isEmpty {
            upsertedNewIDs = (try? await appDB.upsertArticles(toUpsert)) ?? []
            stats.writes += 1
        }
        let newIDs = Set(insertedIDs + upsertedNewIDs)
        let newArticles = (toInsert + toUpsert).filter { newIDs.contains($0.articleID) }
        let insertedByFeed = Dictionary(grouping: newArticles, by: \.feedID).mapValues(\.count)

        // ONE transaction for every feed's bookkeeping (was one write per feed).
        let updates = results.map { r in
            FeedRefreshUpdate(
                feedID: r.feedID, outcome: r.outcome,
                insertedCount: insertedByFeed[r.feedID] ?? 0,
                adaptivePollInterval: r.adaptivePollInterval)
        }
        try? await appDB.applyFeedRefresh(updates)
        stats.writes += 1

        for r in results {
            stats.requests += r.requests
            stats.bytes += r.bytes
            stats.dropped += r.dropped
            stats.clustered += r.clustered
            if case .failed(let message) = r.outcome {
                print("PulseFeed: [Feed] \(r.feedID) ERROR: \(message)")
            }
        }
        stats.inserted = insertedIDs.count
        stats.upserted = upsertedNewIDs.count

        // Primaries to (re)evaluate: brand-new primaries, plus existing primaries that just
        // gained another source (their relevance and notification eligibility changed).
        let newPrimaryIDs = newArticles.filter { $0.clusterID == nil }.map(\.articleID)
        let affectedPrimaryIDs = newArticles.compactMap(\.clusterID)
        let evalIDs = Array(Set(newPrimaryIDs).union(affectedPrimaryIDs))

        if !evalIDs.isEmpty {
            stats.enriched = await runAIPipeline(articleIDs: evalIDs, tier: tier)
            stats.notified = await evaluateNotifications(articleIDs: evalIDs)
        }
        // The recap is on a clock, not on this tick's arrivals.
        if tier != .critical || true {
            if await sendSummaryIfDue(settings: NotificationSettings.fromDefaults(), rules: UrgencyRules.stored()) { stats.notified += 1 }
            stats.writes += 2
            await updateTopHeadlines()
            if tier != .critical { refreshDigest() }
        }

        await fetchMarketsIfDue(tier: tier, stats: &stats)
        await webSocketManager.configure(cryptoStreamSpec())
        if tier == .ac { await backfillImages(limit: 8, stats: &stats) }

        stats.duration = Date().timeIntervalSince(startedAt)
        lastTickStats = stats
        lastTickAt = Date()
        // The brief takes ~30 s with Claude; start it after the first tick so it is ready before anyone looks.
        if dailyDigest == nil, tier != .critical { refreshDigest() }
        print(
            "PulseFeed: [Tick] \(Date().sqliteString) tier=\(tier) feeds=\(stats.feeds) requests=\(stats.requests) bytes=\(stats.bytes) "
            + "inserted=\(stats.inserted) upserted=\(stats.upserted) clustered=\(stats.clustered) dropped=\(stats.dropped) "
            + "enriched=\(stats.enriched) notified=\(stats.notified) writes=\(stats.writes) "
            + "duration=\(String(format: "%.1f", stats.duration))s")
    }

    /// Stories published before this are a feed's back catalogue: the unread window, so "new"
    /// and "still unread" mean the same thing (Settings › General › Unread window).
    static func oldNewsCutoff(now: Date = Date()) -> Date {
        let days = UserDefaults.standard.object(forKey: "unread_window_days") as? Int ?? 2
        return now.addingTimeInterval(-Double(max(days, 1)) * 86400)
    }

    /// Stream's hero cards need pictures and many feeds send none: on AC, read the social card
    /// (og:image / twitter:image) from the article page for a few recent image-less stories per
    /// tick. Reads at most 200 KB per page; a miss is remembered for the run and not retried.
    private func backfillImages(limit: Int, stats: inout TickStats) async {
        let since = Date().addingTimeInterval(-24 * 3600)
        guard let candidates = try? await appDB.fetchImageless(since: since, excluding: imageBackfillTried, limit: limit),
              !candidates.isEmpty else { return }
        var found = 0
        for article in candidates {
            imageBackfillTried.insert(article.articleID)
            guard let urlString = article.url, let url = URL(string: urlString) else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            guard let html = await Self.fetchHead(request, maxBytes: 200_000) else { continue }
            stats.requests += 1
            stats.bytes += html.utf8.count
            if let image = ImageExtraction.socialImageURL(inHTML: html, base: url) {
                try? await appDB.updateImageURL(articleID: article.articleID, url: image)
                stats.writes += 1
                found += 1
            }
        }
        print("PulseFeed: [Images] backfilled \(found) of \(candidates.count) image-less stories")
    }

    /// The start of a page as text (enough for <head>), reading no more than `maxBytes`.
    private static func fetchHead(_ request: URLRequest, maxBytes: Int) async -> String? {
        do {
            let (bytes, response) = try await feedSession.bytes(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            var data = Data()
            data.reserveCapacity(min(maxBytes, 65_536))
            for try await byte in bytes {
                data.append(byte)
                if data.count >= maxBytes { break }
            }
            return String(decoding: data, as: UTF8.self)
        } catch {
            return nil
        }
    }

    /// PULSEFEED_DEBUG_OPEN=urgent: post the newest unread story as an urgent alert so the
    /// time-sensitive banner and its icon can be checked without waiting for real news.
    func debugPostUrgentSample() async {
        guard let article = try? await appDB.fetchUnnotifiedSince(Date().addingTimeInterval(-7 * 86400), limit: 1).first else {
            print("PulseFeed: [Urgent] debug sample: no unread story to use")
            return
        }
        await notificationService.postUrgent(article, reason: "debug sample")
    }

    /// The chosen instruments, plus any coin with an active price alert (alerts still need its price).
    private func wantedInstruments() -> [String] {
        let alertCoins = cachedAlerts.map(\.asset).filter { CryptoQuotes.coinGeckoIDs.contains($0) }
        var seen = Set<String>()
        return (MarketInstrument.stored(.standard) + alertCoins).filter { seen.insert($0).inserted }
    }

    /// Prices for what the person chose, from the provider each job uses (spec D10, D12): coins from
    /// CoinGecko every 2 minutes on every tier, everything else on the quote intervals, never on critical.
    private func fetchMarketsIfDue(tier: PowerTier, stats: inout TickStats) async {
        let instruments = wantedInstruments()
        let now = Date()
        let due = MarketsSchedule.due(tier: tier, now: now, lastCrypto: lastCryptoFetch, lastQuotes: lastQuotesFetch, instruments: instruments)
        if due.crypto {
            lastCryptoFetch = now
            let ids = instruments.filter { CryptoQuotes.coinGeckoIDs.contains($0) }
            if let url = CryptoQuotes.url(ids: ids) {
                stats.requests += 1
                if let (data, _) = try? await Self.feedSession.data(from: url), let updates = try? CryptoQuotes.parse(data) {
                    stats.bytes += data.count
                    for u in updates { if let c = u.change24h, c > -100 { cryptoOpen24h[u.symbol] = u.price / (1 + c / 100) } }
                    applyPriceUpdates(updates)
                    await checkPriceAlerts(updates: updates)
                    await evaluateMarketShocks(updates)
                } else {
                    print("PulseFeed: [Markets] coin prices failed")
                }
            }
        }
        if due.quotes {
            lastQuotesFetch = now
            let source = DataProviders.stored(.standard).effective(keys: .standard).quotes
            let r = await QuoteFetcher(session: Self.feedSession).fetch(instruments: instruments, source: source, keys: .standard, now: now)
            stats.requests += r.requests
            applyPriceUpdates(r.updates)
            await evaluateMarketShocks(r.updates)
        }
    }

    /// Market-shock alerts for the chosen instruments (MarketShock), under the urgent budget and quiet hours.
    /// Every decision and the stored latch are settled before the first await: the stream and both tick
    /// paths call this on the main actor and may interleave at a post, so a decision made after an await
    /// could alert the same move twice or overwrite another's latch.
    private func evaluateMarketShocks(_ updates: [PriceUpdate]) async {
        let d = UserDefaults.standard
        let chosen = MarketInstrument.stored(d)
        let rules = UrgencyRules.stored(d)
        let enabled = MarketShock.isEnabled(d)
        let allowsUrgent = AlertMode.stored(d).allowsUrgent
        let settings = NotificationSettings.fromDefaults(d)
        let quotes = DataProviders.stored(d).effective(keys: .standard).quotes
        var latched = MarketShock.loadLatched(d)
        let before = latched
        var posts: [(PriceUpdate, Double)] = []
        for u in updates {
            let quiet = settings.quietHoursEnabled && settings.isInQuietHours()
            let r = MarketShock.step(instrument: u.symbol, change24h: u.change24h, chosen: chosen, rules: rules,
                                     enabled: enabled, allowsUrgent: allowsUrgent && !quiet, latched: latched)
            latched = r.latched
            guard r.alert, let change = u.change24h else { continue }
            guard urgencyBudget.admit(at: Date()) else {
                print("PulseFeed: [Shock] budget exhausted; \(u.symbol) \(change)% not alerted")
                continue
            }
            posts.append((u, change))
        }
        if latched != before { MarketShock.saveLatched(latched, d) }
        for (u, change) in posts {
            await notificationService.postMarketShock(
                label: MarketInstrument.label(u.symbol, quotes: quotes), change: change, price: u.price,
                rolling24h: MarketShock.isRolling24h(u.symbol, quotes: quotes),
                key: "\(u.symbol):\(change >= 0 ? "up" : "down"):\(Int(Date().timeIntervalSince1970))")
        }
    }

    private func applyPriceUpdates(_ updates: [PriceUpdate]) {
        for update in updates {
            latestPrices[update.symbol] = update
            if !update.sparklineData.isEmpty {
                priceHistory[update.symbol] = update.sparklineData
            } else {
                recordPricePoint(update.symbol, price: update.price)
            }
        }
    }

    // MARK: - Per-Feed Refresh (static for Sendable task group; no DB writes here)

    private static func refreshFeed(
        _ feed: Feed, rss: RSSFetcher, json: JSONFetcher,
        index: DedupIndex, knownUniqueIDs: Set<String>
    ) async -> FeedRefreshResult {
        var result = FeedRefreshResult(feedID: feed.id, outcome: .notModified)
        do {
            switch feed.type {
            case "rss":
                let r = try await rss.fetch(feed: feed)
                result.requests = 1
                result.bytes = r.bytes
                result.outcome = r.wasNotModified
                    ? .notModified
                    : .fetched(etag: r.etag, lastModified: r.lastModified,
                               contentHash: r.contentHash, conditionalGetResetAt: r.conditionalGetResetAt)
                if !r.articles.isEmpty {
                    let applied = index.apply(r.articles)
                    result.toInsert = applied.toInsert
                    result.dropped = applied.dropped
                    result.clustered = applied.clustered
                    print("PulseFeed: [Feed] \(feed.id): \(r.articles.count) parsed → \(applied.toInsert.count) to insert (\(applied.clustered) clustered, \(applied.dropped) dropped)")
                }
            case "json_api":
                let r = try await json.fetch(feed: feed, knownUniqueIDs: knownUniqueIDs)
                result.requests = r.requests
                result.bytes = r.bytes
                result.outcome = .notModified   // JSON feeds carry no conditional-GET headers; this just touches the row
                result.priceUpdates = r.priceUpdates
                result.adaptivePollInterval = r.adaptivePollInterval
                if r.shouldUpsert {
                    result.toUpsert = r.articles
                } else if !r.articles.isEmpty {
                    let applied = index.apply(r.articles)
                    result.toInsert = applied.toInsert
                    result.dropped = applied.dropped
                    result.clustered = applied.clustered
                }
            default:
                result.requests = 0
            }
        } catch {
            result.outcome = FetchErrorKind.classify(error) == .transient
                ? .offline(error.localizedDescription)
                : .failed(error.localizedDescription)
        }
        return result
    }

    // MARK: - Top Headlines

    func updateTopHeadlines() async {
        if let titles = try? await appDB.fetchTopUnreadTitles(limit: 5) {
            topHeadlines = titles
        }
    }

    // MARK: - Price History

    private func recordPricePoint(_ symbol: String, price: Double) {
        var history = priceHistory[symbol] ?? []
        history.append(price)
        if history.count > 50 {
            history.removeFirst(history.count - 50)
        }
        priceHistory[symbol] = history
    }

    // MARK: - Daily Digest

    func refreshDigest() {
        guard !isShowcase else { return }
        Task {
            let digest = await digestService.getOrGenerateDigest(appDB: appDB)
            dailyDigest = digest
        }
    }

    // MARK: - WebSocket

    /// The stream for the chosen coins from the install's stream provider; nil when no coin is chosen.
    private func cryptoStreamSpec() -> (any CryptoStreamSpec)? {
        CryptoStreams.spec(source: DataProviders.stored(.standard).effective(keys: .standard).cryptoStream,
                           coins: wantedInstruments())
    }

    private func startWebSockets() {
        webSocketTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.webSocketManager.start()
            await self.webSocketManager.configure(self.cryptoStreamSpec())
            await self.webSocketManager.connectIfAppropriate()

            for await raw in stream {
                let update = raw.withChange(fromOpen: self.cryptoOpen24h[raw.symbol])
                guard !Task.isCancelled else { break }
                // Throttle UI + alert checks to ~1/sec; alerts come from the in-memory cache.
                let now = Date()
                if now.timeIntervalSince(self.lastPriceUIUpdate) >= 1.0 {
                    if self.latestPrices[update.symbol] == nil {
                        print("PulseFeed: [WS] first live price \(update.symbol)=\(update.price) change=\(update.change24h.map { String(format: "%.2f%%", $0) } ?? "n/a")")
                    }
                    self.latestPrices[update.symbol] = update
                    self.recordPricePoint(update.symbol, price: update.price)
                    self.lastPriceUIUpdate = now
                    await self.checkPriceAlerts(updates: [update])
                    await self.evaluateMarketShocks([update])
                }
            }
        }
    }

    // MARK: - Price Alerts (cached, reactive)

    private func startAlertsObservation() {
        alertsTask = Task { [weak self, appDB] in
            do {
                for try await alerts in AppDatabase.enabledPriceAlertsObservation().values(in: appDB.dbPool) {
                    guard let self else { return }
                    self.cachedAlerts = alerts
                }
            } catch {
                // Observation cancelled
            }
        }
    }

    private func checkPriceAlerts(updates: [PriceUpdate]) async {
        guard !cachedAlerts.isEmpty, AlertMode.stored(.standard).allowsPriceAlerts else { return }
        let settings = NotificationSettings.fromDefaults()

        for update in updates {
            let triggered = cachedAlerts.filter { alert in
                guard alert.asset == update.symbol else { return false }
                switch alert.direction {
                case "above": return update.price >= alert.targetPrice
                case "below": return update.price <= alert.targetPrice
                default: return false
                }
            }
            guard !triggered.isEmpty else { continue }
            // Drop locally first so a burst of ticks cannot fire the same alert twice
            // before the observation catches up.
            let triggeredIDs = Set(triggered.map(\.id))
            cachedAlerts.removeAll { triggeredIDs.contains($0.id) }

            for alert in triggered {
                try? await appDB.triggerPriceAlert(id: alert.id)

                if settings.isCategoryEnabled("crypto") {
                    let direction = alert.direction == "above" ? "above" : "below"
                    let content = UNMutableNotificationContent()
                    content.title = "Price Alert"
                    content.subtitle =
                        "\(alert.asset.capitalized) is \(direction) $\(String(format: "%.2f", alert.targetPrice))"
                    content.body =
                        "Current price: $\(String(format: "%.2f", update.price))"
                    content.categoryIdentifier = "PRICE_ALERT"
                    content.threadIdentifier = "crypto"
                    content.sound = .default

                    let request = UNNotificationRequest(
                        identifier: "price-\(alert.id)",
                        content: content, trigger: nil)
                    try? await UNUserNotificationCenter.current().add(request)
                }
            }
        }
    }

    // MARK: - AI Pipeline

    /// Tier 1 keyword scoring (plus a bonus per extra source), then Tier 2 model enrichment
    /// through the gate for the candidates the tier allows. Returns the number enriched.
    private func runAIPipeline(articleIDs: [String], tier: PowerTier) async -> Int {
        guard AIGate.isEnabled() else { return 0 }
        guard let articles = try? await appDB.fetchArticles(ids: articleIDs), !articles.isEmpty else { return 0 }
        let infos = (try? await appDB.fetchArticleInfos(articleIDs: articleIDs)) ?? []
        let sourceCounts = Dictionary(uniqueKeysWithValues: infos.map { ($0.articleID, $0.sourceCount) })
        let interests = (try? await appDB.fetchAllInterests()) ?? []

        var scores: [(articleID: String, score: Double)] = []
        var candidates: [(article: Article, bonus: Double)] = []

        for article in articles {
            let sources = sourceCounts[article.articleID] ?? 1
            let bonus = min(Double(sources - 1) * PulseFeedConstants.multiSourceBonusPerSource, 4.5)
            let score = min(aiService.keywordRelevance(article: article, interests: interests) + bonus, 10)
            scores.append((article.articleID, score))

            let alreadyEnriched = !(article.summary ?? "").isEmpty
            let isBreaking = article.priority == "breaking"
            let multiSource = sources >= 2
            let eligible: Bool
            switch tier {
            case .ac: eligible = score > 3.0 || multiSource
            case .battery: eligible = score > 5.0 || multiSource || isBreaking
            case .critical: eligible = false
            }
            if eligible && !alreadyEnriched {
                candidates.append((article, bonus))
            }
        }

        try? await appDB.updateKeywordScores(scores)

        guard !candidates.isEmpty else { return 0 }
        var enrichments: [(articleID: String, enrichment: AIEnrichment, relevance: Double)] = []
        for (article, bonus) in candidates.prefix(PulseFeedConstants.maxEnrichmentsPerTick) {
            if let e = await AIGate.shared.enrich(article: article, userInitiated: false) {
                enrichments.append((article.articleID, e, min(e.relevance + bonus, 10)))
            }
        }
        if !enrichments.isEmpty {
            try? await appDB.updateAIEnrichments(enrichments)
        }
        return enrichments.count
    }

    // MARK: - Notification Evaluation

    /// Urgent stories get their own alert now; everything else waits for the recap. Returns the number
    /// of notifications posted (urgent alerts plus the recap, if one went out). Urgent alerts are
    /// marked notified at once; recap stories are marked when the recap is sent.
    private func evaluateNotifications(articleIDs: [String]) async -> Int {
        // Recap only / Quiet: nothing is alerted on its own; the stories stay un-notified, so the recap carries them.
        guard AlertMode.stored(.standard).allowsUrgent else { return 0 }
        let settings = NotificationSettings.fromDefaults()
        let rules = UrgencyRules.stored()
        var posted = 0

        if let articles = try? await appDB.fetchArticleInfos(articleIDs: articleIDs) {
            var notifiedIDs: [String] = []
            for article in articles where article.isNotified != true {
                guard settings.isCategoryEnabled(article.feedCategory) else { continue }
                if settings.quietHoursEnabled && settings.isInQuietHours() { continue }
                let tier = Self.tier(for: article, rules: rules)
                guard tier == .urgent else { continue }
                guard urgencyBudget.admit(at: Date()) else {
                    print("PulseFeed: [Urgent] budget exhausted; \(article.title ?? "") rides the recap")
                    continue
                }
                let reason = Self.reason(for: article, rules: rules)
                await notificationService.postUrgent(article, reason: reason)
                notifiedIDs.append(article.articleID)
                posted += 1
            }
            try? await appDB.markNotified(ids: notifiedIDs)
        }

        return posted
    }

    /// Keyword floor OR the model's "breaking" vote (the enrichment prompt carries the install's AIProfile).
    /// A vetoed pattern demotes one tier either way.
    static func tier(for article: ArticleInfo, rules: UrgencyRules) -> UrgencyTier {
        let title = article.title ?? ""
        var tier = UrgencyClassifier.keywordTier(title: title, category: article.feedCategory, topic: article.feedTopic, rules: rules)
        let vetoed = rules.neverUrgent.contains { UrgencyClassifier.matches(" " + title.lowercased() + " ", $0) }
        if article.priority == "breaking" && !vetoed { tier = max(tier, .urgent) }
        if article.priority == "important" { tier = max(tier, .headline) }
        return tier
    }

    /// The banner's reason, as the tier decided it: an urgent pattern first, then a followed name, each
    /// shown without its chip scope.
    static func reason(for article: ArticleInfo, rules: UrgencyRules) -> String {
        let t = " " + (article.title ?? "").lowercased() + " "
        let title = article.title ?? ""
        func bare(_ s: String) -> String? { UrgencyClassifier.inScope(s, category: article.feedCategory, topic: article.feedTopic) }
        for p in rules.urgentPatterns {
            if let b = bare(p), UrgencyClassifier.matches(t, b) { return b.replacingOccurrences(of: "&", with: " + ").capitalized }
        }
        for f in rules.followed {
            if let b = bare(f), UrgencyClassifier.containsName(title, b) { return b.capitalized }
        }
        return "Breaking"
    }

    /// Every `summary_interval` seconds: unread stories that arrived since the last recap and were not
    /// alerted urgently, as one notification. Nothing new means nothing sent. On critical battery, a
    /// plain list instead of a model call.
    private func sendSummaryIfDue(settings: NotificationSettings, rules: UrgencyRules) async -> Bool {
        let d = UserDefaults.standard
        guard AlertMode.stored(d).allowsRecap else { return false }
        let interval = d.object(forKey: SummaryComposer.intervalKey) as? Double ?? SummaryComposer.defaultInterval
        let lastSent = d.object(forKey: SummaryComposer.lastSentKey) as? Date
        let force = DebugOpen.wants("summary") && lastSent == nil
        guard force || SummaryComposer.isDue(lastSentAt: lastSent, now: Date(), interval: interval) else { return false }
        if settings.quietHoursEnabled && settings.isInQuietHours() { return false }

        let since = lastSent ?? Date().addingTimeInterval(-interval)
        guard let pending = try? await appDB.fetchUnnotifiedSince(since, limit: 60) else { return false }
        let eligible = pending.filter { settings.isCategoryEnabled($0.feedCategory) }
        guard !eligible.isEmpty else {
            d.set(Date(), forKey: SummaryComposer.lastSentKey)   // nothing new: wait a full interval again
            return false
        }

        let headlines = eligible.filter { Self.tier(for: $0, rules: rules) >= .headline }.compactMap(\.title)
        let others = eligible.filter { Self.tier(for: $0, rules: rules) < .headline }.compactMap(\.title)
        var summary = SummaryComposer.plainSummary(headlines: headlines, others: others)
        if PowerMonitor.shared.tier != .critical, AIGate.isEnabled() {
            let prompt = SummaryComposer.prompt(headlines: headlines, others: others)
            if let text = await AIGate.shared.generateText(
                system: prompt.system, user: prompt.user, maxTokens: 260, kind: "recap", preferOnDevice: true),
               let recap = SummaryComposer.parseRecap(text) {
                // The model writes the body; the lead line is ours, so the always-visible middle
                // line names real headlines whichever way the recap was produced.
                summary = SummaryText(
                    title: SummaryComposer.title(count: eligible.count),
                    subtitle: SummaryComposer.subtitle(headlines: headlines, others: others),
                    body: recap)
            } else {
                print("PulseFeed: [Recap] model answer unusable; sending the plain list")
            }
        }
        guard let summary else { return false }

        let ids = eligible.map(\.articleID)
        await notificationService.postSummary(summary, storyIDs: ids)
        try? await appDB.markNotified(ids: ids)
        d.set(Date(), forKey: SummaryComposer.lastSentKey)
        d.set(summary.body, forKey: SummaryComposer.lastTextKey)
        d.set(summary.subtitle, forKey: SummaryComposer.lastSubtitleKey)
        SummaryComposer.saveLastIDs(ids, in: d)
        lastRecap = summary
        lastRecapIDs = ids
        print("PulseFeed: [Recap] sent: \(eligible.count) stories (\(headlines.count) headlines)")
        return true
    }

    // MARK: - Power / Sleep / Network

    private func observePower() {
        PowerMonitor.shared.objectWillChange
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let tier = PowerMonitor.shared.tier
                guard tier != self.lastTier else { return }
                print("PulseFeed: [Power] tier \(self.lastTier?.description ?? "?") → \(tier)")
                self.lastTier = tier
                Task { [weak self] in
                    guard let self else { return }
                    await self.webSocketManager.connectIfAppropriate()
                    await self.scheduleNextTick()
                }
            }
            .store(in: &cancellables)
    }

    private func observeSleepWake() {
        let ws = NSWorkspace.shared.notificationCenter
        sleepObserver = ws.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.webSocketManager.handleSleep() }
        }
        wakeObserver = ws.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.webSocketManager.handleWake() }
            self.tickNow(reason: "wake")
        }
    }

    private func removeSleepWakeObservers() {
        let ws = NSWorkspace.shared.notificationCenter
        if let obs = sleepObserver { ws.removeObserver(obs) }
        if let obs = wakeObserver { ws.removeObserver(obs) }
    }

    /// When the network comes back after an outage, poll right away instead of waiting out the
    /// backoff the offline failures produced.
    private func startNetworkMonitor() {
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                let regained = available && !self.networkWasAvailable
                self.networkWasAvailable = available
                if regained { self.tickNow(reason: "network regained") }
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.pulsefeed.engine-network"))
    }
}

// MARK: - Feed Refresh Result

private struct FeedRefreshResult: Sendable {
    let feedID: String
    var outcome: FeedFetchOutcome
    var toInsert: [Article] = []
    var toUpsert: [Article] = []
    var dropped = 0
    var clustered = 0
    var priceUpdates: [PriceUpdate] = []
    var adaptivePollInterval: Int? = nil
    var requests = 0
    var bytes = 0
}
