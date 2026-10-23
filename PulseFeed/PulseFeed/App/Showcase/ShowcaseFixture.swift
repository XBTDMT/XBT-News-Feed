import Foundation

/// The fictional news day `make showcase` draws (the public README's pictures): eight invented outlets on
/// reserved `.example` hosts, about forty stories across Tech, AI, Markets, Sports, World and Travel from the
/// last six hours, three stories carried by several outlets, one breaking story, a recap and a daily brief.
/// No outlet, company, team, place or person in it is real. It is written through the app's own write paths
/// (`addFeed`, `insertArticles`, `applyFeedRefresh`, `toggleStarred`, `markSaved`), so the designs read it
/// exactly as they read a real install.
enum ShowcaseFixture {
    struct Outlet: Sendable {
        let title: String
        let host: String
        let category: String

        var feedURL: String { "https://\(host)/feed.xml" }
        var feedID: String { Feed.makeID(url: feedURL) }
    }

    /// One story: minutes before `now`, and for a copy the cluster it joins (the key of its primary).
    struct Story: Sendable {
        let outlet: Int
        let minutesAgo: Int
        let title: String
        let summary: String
        var priority: String = "fyi"
        var score: Double = 2.5
        var clusterKey: String? = nil
        var copyOf: String? = nil
        var starred = false
        var saved = false
        /// A picture drawn in code (`ShowcasePictures`), for the designs that show one.
        var picture: String? = nil
    }

    /// The clock every story is placed against. The views measure "12m ago" against the wall clock, so it
    /// is pinned once, to the minute, when a run first reads it; within a run every surface agrees.
    static let now: Date = {
        let t = Date().timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (t / 60).rounded(.down) * 60)
    }()

    /// "Since you last looked": the popover was last closed 50 minutes ago.
    static var lastLooked: Date { now.addingTimeInterval(-50 * 60) }

    static let outlets: [Outlet] = [
        Outlet(title: "Northwind Wire", host: "northwind.example", category: "world"),
        Outlet(title: "Meridian Courier", host: "meridiancourier.example", category: "world"),
        Outlet(title: "Voltmoor Ledger", host: "voltmoor.example", category: "tech"),
        Outlet(title: "Kiteline Review", host: "kiteline.example", category: "tech"),
        Outlet(title: "Neural Dispatch", host: "neuraldispatch.example", category: "ai"),
        Outlet(title: "Tickerline", host: "tickerline.example", category: "finance"),
        Outlet(title: "Quarterline Sports", host: "quarterline.example", category: "sports"),
        Outlet(title: "Upwind Travel", host: "upwind.example", category: "travel"),
    ]

    private static let northwind = 0, meridian = 1, voltmoor = 2, kiteline = 3, neural = 4, ticker = 5,
                       quarterline = 6, upwind = 7

    /// Primaries first within each cluster (a copy names its primary's key), newest arrivals anywhere.
    static let stories: [Story] = [
        // The breaking story, carried by five outlets.
        Story(outlet: neural, minutesAgo: 14,
              title: "Halcyon Labs releases Merrow-5, its largest open-weight model yet",
              summary: "Halcyon Labs has released Merrow-5, an open-weight model with a million-token context window. The lab says it runs on a single workstation and matches its closed rivals on reasoning tests.",
              priority: "breaking", score: 4.8, clusterKey: "atlas", picture: "merrow"),
        Story(outlet: kiteline, minutesAgo: 12, title: "Halcyon's Merrow-5 arrives with a million-token memory",
              summary: "Merrow-5 can read an entire codebase at once.", copyOf: "atlas"),
        Story(outlet: voltmoor, minutesAgo: 10, title: "Merrow-5 is out: what Halcyon's new model can and can't do",
              summary: "A first look at the new model.", copyOf: "atlas"),
        Story(outlet: northwind, minutesAgo: 9, title: "AI lab Halcyon launches Merrow-5 model",
              summary: "The model is free to download.", copyOf: "atlas"),
        Story(outlet: ticker, minutesAgo: 7, title: "Chipmakers rally after Halcyon unveils Merrow-5",
              summary: "Shares in workstation chipmakers rose.", copyOf: "atlas"),

        Story(outlet: ticker, minutesAgo: 20, title: "Stocks edge higher as tech leads a quiet session",
              summary: "Major indexes rose modestly in light trading, with technology shares doing most of the lifting ahead of Thursday's inflation figures.",
              score: 3.2, picture: "stocks"),
        Story(outlet: kiteline, minutesAgo: 25, title: "Foldable laptops get a second hinge, and finally a usable keyboard",
              summary: "The new two-hinge design folds flat into a tablet or stands up as a laptop with a full-size keyboard. Battery life is the open question.",
              score: 2.8, starred: true, picture: "laptops"),
        Story(outlet: northwind, minutesAgo: 30, title: "Northern ports reopen after a week of storm closures",
              summary: "Ferries and freight resumed at all six northern ports this morning after the storm warnings were lifted. Operators expect delays into the weekend.",
              score: 2.6, picture: "ports"),
        Story(outlet: upwind, minutesAgo: 35, title: "Night trains return: six new sleeper routes for the winter timetable",
              summary: "Six overnight services join the winter timetable, including the first sleeper to the lakes in fifteen years. Cabins go on sale next week.",
              score: 3.0, saved: true, picture: "trains"),
        Story(outlet: voltmoor, minutesAgo: 38, title: "Corvid Systems recalls 40,000 smart thermostats over a battery fault",
              summary: "Corvid Systems is recalling its T2 smart thermostat after reports of batteries swelling. Owners are asked to stop using the device and request a free replacement.",
              priority: "important", score: 3.6),
        Story(outlet: neural, minutesAgo: 40, title: "Small models are catching up: a 3B model passes a bar-style reasoning test",
              summary: "A three-billion-parameter model scored within four points of models fifty times its size on a new legal reasoning benchmark.",
              score: 3.1),
        Story(outlet: ticker, minutesAgo: 45, title: "Bitcoin climbs 2% as fund inflows pick up",
              summary: "Bitcoin rose for a third day as weekly fund inflows reached their highest level since the spring.",
              score: 3.0),

        // A world story carried by four outlets.
        Story(outlet: meridian, minutesAgo: 52, title: "Eleven coastal nations sign a pact to protect the Sorrel Sea fisheries",
              summary: "The agreement caps catches for ten years and closes two spawning grounds each spring. It is the first fisheries deal to include every country on the Sorrel coast.",
              priority: "important", score: 3.9, clusterKey: "sorrel", picture: "sorrel"),
        Story(outlet: northwind, minutesAgo: 49, title: "Sorrel Sea fisheries deal agreed after all-night talks",
              summary: "Negotiators finished just before dawn.", copyOf: "sorrel"),
        Story(outlet: upwind, minutesAgo: 46, title: "The Sorrel Sea pact will pause two ferry routes in spawning season",
              summary: "Two island ferries will run a reduced spring timetable.", copyOf: "sorrel"),
        Story(outlet: ticker, minutesAgo: 44, title: "Seafood stocks slip as the Sorrel Sea pact caps catches",
              summary: "Processors fell on the news.", copyOf: "sorrel"),

        Story(outlet: meridian, minutesAgo: 60, title: "Island nation of Kestria votes in a snap election",
              summary: "Polls close at eight tonight in Kestria's first snap election in two decades. A result is expected overnight.",
              score: 2.7),
        Story(outlet: kiteline, minutesAgo: 65, title: "A browser built around tabs that close themselves",
              summary: "Driftwood closes any tab you have not looked at for a day and keeps a searchable record of what it closed.",
              score: 2.2),
        Story(outlet: ticker, minutesAgo: 70, title: "Treasury yields slip ahead of Thursday's inflation report",
              summary: "Bond yields fell for a second session as traders added to bets on a rate cut before the year is out.",
              score: 2.9),
        Story(outlet: neural, minutesAgo: 80, title: "On-device assistants can now run all day on a laptop battery",
              summary: "Researchers trimmed an assistant model's power draw by two thirds, enough for a full working day away from a charger.",
              score: 2.8),
        Story(outlet: quarterline, minutesAgo: 85, title: "Comets guard Rafe Okonjo named finals MVP",
              summary: "Okonjo averaged 31 points across the seven-game series and scored the winning basket in overtime.",
              score: 3.3),

        // A sports story carried by three outlets.
        Story(outlet: quarterline, minutesAgo: 95, title: "Port Ellery Comets win Game 7 on a buzzer-beater",
              summary: "The Comets took the Ridgeback League title with a three-pointer at the overtime buzzer, ending a 31-year wait.",
              score: 3.7, clusterKey: "comets", picture: "comets"),
        Story(outlet: northwind, minutesAgo: 92, title: "Comets take the title in overtime thriller",
              summary: "A buzzer-beater settled Game 7.", copyOf: "comets"),
        Story(outlet: meridian, minutesAgo: 90, title: "Port Ellery celebrates the Comets' first title in 31 years",
              summary: "Crowds filled the waterfront.", copyOf: "comets"),

        Story(outlet: upwind, minutesAgo: 100, title: "Kestrel Air adds nonstop flights to five island capitals",
              summary: "The new routes start in March, with fares from the price of a train ticket for early bookers.",
              score: 2.6, picture: "island"),
        Story(outlet: northwind, minutesAgo: 105, title: "Aldmere opens the world's longest timber footbridge",
              summary: "The 820-metre bridge links the old town to the station across the river and took four years to build.",
              score: 2.3, picture: "bridge"),
        Story(outlet: voltmoor, minutesAgo: 110, title: "Quillon's new e-ink tablet lasts six weeks on a charge",
              summary: "The Quillon Slate 2 adds a colour screen and a stylus without giving up the battery life its readers love.",
              score: 2.5),
        Story(outlet: ticker, minutesAgo: 120, title: "Gold eases from its record as the dollar steadies",
              summary: "Gold slipped from Monday's high as the dollar found its footing ahead of the inflation data.",
              score: 2.4),
        Story(outlet: neural, minutesAgo: 125, title: "Halcyon's chief scientist on why Merrow-5 took two years",
              summary: "In an interview, Halcyon's research chief says most of the time went into testing, not training.",
              score: 2.9),
        Story(outlet: voltmoor, minutesAgo: 140, title: "Open-source maintainers get a paid support fund from twelve companies",
              summary: "The fund will pay maintainers of widely used libraries a monthly stipend, starting with forty projects.",
              score: 2.6, starred: true),
        Story(outlet: quarterline, minutesAgo: 150, title: "Rookie sets a single-season assists record for the Ridgeback League",
              summary: "The 20-year-old passed the record with three games to spare.",
              score: 2.2),
        Story(outlet: meridian, minutesAgo: 160, title: "Summit ends with a deal on cross-border rail tickets",
              summary: "One ticket will cover journeys across all nine countries from next summer.",
              score: 2.7),
        Story(outlet: ticker, minutesAgo: 165, title: "Kestrel Air shares jump on a record summer quarter",
              summary: "The airline carried more passengers than ever between June and August and raised its forecast.",
              score: 2.5),
        Story(outlet: upwind, minutesAgo: 170, title: "The quiet-carriage hotel: rooms with no screens at all",
              summary: "A small chain is betting that guests will pay more for a room with a record player and no television.",
              score: 2.1, saved: true),
        Story(outlet: quarterline, minutesAgo: 185, title: "Grand prix at Corrisand comes down to a rain-soaked final lap",
              summary: "The championship leader held on by four tenths of a second after a late downpour.",
              score: 2.8),
        Story(outlet: kiteline, minutesAgo: 190, title: "Review: the Pebblestone 3 earbuds fix the fit, not the battery",
              summary: "Comfortable for hours, quiet on a train, and flat by the end of a long-haul flight.",
              score: 2.0),
        Story(outlet: northwind, minutesAgo: 200, title: "Heatwave eases across the southern plains",
              summary: "Temperatures fell by ten degrees overnight and are expected to stay mild through the week.",
              score: 2.1, picture: "heat"),
        Story(outlet: ticker, minutesAgo: 210, title: "What a strong dollar means for your next trip abroad",
              summary: "Hotels and meals abroad are cheaper than a year ago; flights are not.",
              score: 2.2),
        Story(outlet: neural, minutesAgo: 220, title: "A new benchmark tests whether chatbots admit what they don't know",
              summary: "The test rewards models for saying \"I'm not sure\" instead of guessing.",
              score: 2.7),
        Story(outlet: voltmoor, minutesAgo: 240, title: "Satellite broadband reaches the last 2% of rural Brackenfold county",
              summary: "Every home in the county can now get a broadband connection, five years after the scheme began.",
              score: 2.0),
        Story(outlet: quarterline, minutesAgo: 250, title: "Fight night: the lightweight title stays in the family",
              summary: "The champion beat her cousin on a split decision in a rematch of last year's bout.",
              score: 2.3),
        Story(outlet: upwind, minutesAgo: 260, title: "Passport queues: the airports where e-gates now take 30 seconds",
              summary: "New gates at nine airports cut the wait at the border to under a minute at peak times.",
              score: 2.4),
        Story(outlet: meridian, minutesAgo: 270, title: "Archaeologists find a 2,000-year-old harbour under a car park",
              summary: "Timbers from the harbour wall survived in waterlogged clay beneath the town centre.",
              score: 2.2),
        // Published more than five hours ago: they arrive read, as an old story does.
        Story(outlet: neural, minutesAgo: 305, title: "The translation earpiece that handles six languages offline",
              summary: "It works without a connection and fits in a coin pocket.", score: 2.1),
        Story(outlet: kiteline, minutesAgo: 320, title: "Why every new phone camera now has a quiet shutter",
              summary: "A small change after years of complaints.", score: 1.8),
        Story(outlet: upwind, minutesAgo: 330, title: "A slow week on the Sorrel coast, by ferry and on foot",
              summary: "Seven days, four islands, one rucksack.", score: 2.0),
        Story(outlet: ticker, minutesAgo: 340, title: "Earnings week ahead: five reports worth watching",
              summary: "Two airlines, a chipmaker, a retailer and a bank.", score: 1.9),
        Story(outlet: quarterline, minutesAgo: 350, title: "Transfer window: three moves that could reshape the table",
              summary: "One striker, one keeper and a manager.", score: 1.7),
    ]

    /// Stories published before this arrive read (`insertArticles(readIfPublishedBefore:)`).
    static var oldNewsCutoff: Date { now.addingTimeInterval(-5 * 3600) }

    static func articleID(_ s: Story) -> String {
        Article.makeID(feedID: outlets[s.outlet].feedID, uniqueID: url(s))
    }

    static func url(_ s: Story) -> String {
        let slug = s.title.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
            .split(separator: "-").prefix(8).joined(separator: "-")
        return "https://\(outlets[s.outlet].host)/\(slug)"
    }

    /// Empties the database of every source it had (the migrations' seed rows: their names are real
    /// outlets), then writes the fixture. Only ever called on the throwaway database of a showcase run.
    static func install(in appDB: AppDatabase) async throws {
        // It deletes every source first: never on the live database, whatever the caller checked.
        precondition(appDB.dbPool.path != AppDatabase.defaultPath, "the showcase fixture never goes into the live database")
        for id in try await appDB.dbPool.read({ db in try String.fetchAll(db, sql: "SELECT id FROM feed") }) {
            try await appDB.deleteFeed(feedID: id)
        }
        for o in outlets {
            try await appDB.addFeed(title: o.title, url: o.feedURL, category: o.category)
        }

        var primaries: [String: String] = [:]
        for s in stories where s.clusterKey != nil { primaries[s.clusterKey!] = articleID(s) }
        let articles = stories.map { s -> Article in
            let arrived = now.addingTimeInterval(-Double(s.minutesAgo) * 60)
            return Article(
                articleID: articleID(s), feedID: outlets[s.outlet].feedID, uniqueID: url(s),
                title: s.title, url: url(s), contentText: s.summary, summary: s.summary,
                imageURL: s.picture.map(ShowcasePictures.url),
                author: nil, datePublished: arrived.addingTimeInterval(-120).sqliteString,
                dateArrived: arrived.sqliteString, relevanceScore: s.score, priority: s.priority,
                clusterID: s.copyOf.flatMap { primaries[$0] })
        }
        try await appDB.insertArticles(articles, readIfPublishedBefore: oldNewsCutoff)

        for s in stories where s.starred { try await appDB.toggleStarred(articleID(s)) }
        for s in stories where s.saved { try await appDB.markSaved(articleID(s)) }

        try await appDB.applyFeedRefresh(outlets.indices.map { i in
            FeedRefreshUpdate(feedID: outlets[i].feedID, outcome: .notModified,
                              insertedCount: stories.filter { $0.outlet == i }.count, adaptivePollInterval: nil)
        })
    }

    // MARK: - What the engine holds after a tick

    /// The stories the recap covered (its "Mark these read" set).
    static var recapIDs: [String] {
        stories.filter { $0.copyOf == nil && $0.minutesAgo <= 50 }.map(articleID)
    }

    static let recap = SummaryText(
        title: "What's new",
        subtitle: "Halcyon Labs releases Merrow-5 · Stocks edge higher · Night trains return",
        body: "Halcyon Labs released Merrow-5, its largest open-weight model, and five outlets are already covering it. "
            + "Stocks edged higher in a quiet, tech-led session, and Bitcoin climbed 2% on fresh fund inflows. "
            + "Corvid Systems is recalling 40,000 smart thermostats over a battery fault. "
            + "Night trains are back, with six new sleeper routes on the winter timetable.")

    static var digest: DailyDigest {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        func story(_ title: String, _ line: String, _ category: String) -> DigestStory {
            DigestStory(id: title, headline: title, oneLiner: line, category: category)
        }
        return DailyDigest(
            date: f.string(from: now), generatedAt: now.addingTimeInterval(-40 * 60),
            summary: "A big day for open AI models and a quiet one for markets. Halcyon's Merrow-5 leads the coverage, "
                + "eleven nations agreed to protect the Sorrel Sea, and Port Ellery is still celebrating its first title in 31 years.",
            topStories: [
                story("Halcyon Labs releases Merrow-5", "An open-weight model with a million-token memory, free to download.", "ai"),
                story("Sorrel Sea fisheries pact signed", "Catches capped for ten years; two spawning grounds close each spring.", "world"),
                story("Comets win Game 7 on a buzzer-beater", "Rafe Okonjo named finals MVP after a 31-point series.", "sports"),
                story("Corvid Systems recalls 40,000 thermostats", "Swelling batteries; owners get a free replacement.", "tech"),
                story("Six new sleeper routes this winter", "Including the first night train to the lakes in fifteen years.", "travel"),
            ],
            marketMood: "Calm and tech-led: stocks a little higher, Bitcoin up 2%, gold and the dollar soft.",
            whatToWatch: ["Thursday's inflation report", "Kestria's election result overnight",
                          "Merrow-5's first independent benchmarks"],
            isFallback: false)
    }

    static var topHeadlines: [String] {
        Array(stories.filter { $0.copyOf == nil }.sorted { $0.minutesAgo < $1.minutesAgo }.prefix(5).map(\.title))
    }

    /// The welcome flow's "Your feed, live" pane, for the sample draft's topics.
    static let headlines: [PreviewHeadline] = [
        PreviewHeadline(title: "Halcyon Labs releases Merrow-5, its largest open-weight model yet", source: "Neural Dispatch", topicLabel: "AI", date: now.addingTimeInterval(-14 * 60)),
        PreviewHeadline(title: "Stocks edge higher as tech leads a quiet session", source: "Tickerline", topicLabel: "Markets", date: now.addingTimeInterval(-20 * 60)),
        PreviewHeadline(title: "Foldable laptops get a second hinge, and finally a usable keyboard", source: "Kiteline Review", topicLabel: "Tech", date: now.addingTimeInterval(-25 * 60)),
        PreviewHeadline(title: "Night trains return: six new sleeper routes for the winter timetable", source: "Upwind Travel", topicLabel: "Travel", date: now.addingTimeInterval(-35 * 60)),
        PreviewHeadline(title: "Comets guard Rafe Okonjo named finals MVP", source: "Quarterline Sports", topicLabel: "Basketball", date: now.addingTimeInterval(-85 * 60)),
        PreviewHeadline(title: "Quillon's new e-ink tablet lasts six weeks on a charge", source: "Voltmoor Ledger", topicLabel: "Tech", date: now.addingTimeInterval(-110 * 60)),
        PreviewHeadline(title: "Kestrel Air adds nonstop flights to five island capitals", source: "Upwind Travel", topicLabel: "Travel", date: now.addingTimeInterval(-100 * 60)),
    ]

    /// The markets strip's five, with a day of history each (a gentle, deterministic walk ending at the price).
    static let prices: [PriceUpdate] = [
        price("bitcoin", 97_420, change: 2.1, wobble: 0.012),
        price("mag7", 412.80, change: 0.9, wobble: 0.004),
        price("spy", 588.15, change: 0.4, wobble: 0.002),
        price("gold", 2_684.30, change: -0.3, wobble: 0.002),
        price("dxy", 103.42, change: -0.2, wobble: 0.001),
    ]

    static let instruments = ["bitcoin", "mag7", "spy", "gold", "dxy"]

    private static func price(_ symbol: String, _ last: Double, change: Double, wobble: Double) -> PriceUpdate {
        let open = last / (1 + change / 100)
        let points = (0..<24).map { i -> Double in
            let t = Double(i) / 23
            return open + (last - open) * t + last * wobble * sin(Double(i) * 1.3) * (1 - t)
        }
        return PriceUpdate(symbol: symbol, price: last, high24h: points.max(), low24h: points.min(),
                           change24h: change, timestamp: now, sparklineData: points)
    }

    static var tickStats: TickStats {
        var s = TickStats(tier: .ac)
        s.feeds = outlets.count
        s.requests = 18
        s.bytes = 620_000
        s.inserted = 6
        s.duration = 2.4
        return s
    }
}
