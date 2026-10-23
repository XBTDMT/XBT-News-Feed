import GRDB
import Foundation

struct AppDatabase: Sendable {
    let dbPool: DatabasePool

    init(path: String) throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true)
        var config = Configuration()
        config.prepareDatabase { db in
            // WAL mode with synchronous=NORMAL only fsyncs on checkpoints, not every commit
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
        }
        dbPool = try DatabasePool(path: path, configuration: config)
        try Self.migrator.migrate(dbPool)
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        // GRDB's eraseDatabaseOnSchemaChange wipes the whole database when it sees an unknown
        // migration or a schema difference. On 2026-09-07 a bundle carrying v7 ran, then the
        // installed pre-v7 app relaunched and erased 13,000 stories and every read mark. It is a
        // developer convenience, never on by default; PULSEFEED_ERASE_ON_SCHEMA_CHANGE=1 opts in.
        if ProcessInfo.processInfo.environment["PULSEFEED_ERASE_ON_SCHEMA_CHANGE"] == "1" {
            migrator.eraseDatabaseOnSchemaChange = true
        }

        // -- v1_initial: Complete baseline schema + all seed feeds --
        migrator.registerMigration("v1_initial") { db in
            // -- FEEDS --
            try db.execute(sql: """
                CREATE TABLE feed (
                    id TEXT PRIMARY KEY,
                    title TEXT NOT NULL,
                    url TEXT NOT NULL UNIQUE,
                    homePageURL TEXT,
                    category TEXT NOT NULL DEFAULT 'general',
                    type TEXT NOT NULL DEFAULT 'rss',
                    pollInterval INTEGER NOT NULL DEFAULT 300,
                    isEnabled INTEGER NOT NULL DEFAULT 1,
                    etag TEXT,
                    lastModified TEXT,
                    contentHash TEXT,
                    faviconURL TEXT,
                    faviconData BLOB,
                    lastFetchedAt TEXT,
                    lastFetchError TEXT,
                    consecutiveErrors INTEGER NOT NULL DEFAULT 0,
                    conditionalGetResetAt TEXT,
                    createdAt TEXT NOT NULL DEFAULT (datetime('now')),
                    updatedAt TEXT NOT NULL DEFAULT (datetime('now'))
                )
                """)
            try db.execute(sql: "CREATE INDEX feed_category ON feed(category)")
            try db.execute(sql: "CREATE INDEX feed_isEnabled ON feed(isEnabled)")
            try db.execute(sql: "CREATE INDEX feed_lastFetchedAt ON feed(lastFetchedAt)")

            // -- ARTICLES --
            try db.execute(sql: """
                CREATE TABLE article (
                    articleID TEXT PRIMARY KEY,
                    feedID TEXT NOT NULL REFERENCES feed(id) ON DELETE CASCADE,
                    uniqueID TEXT NOT NULL,
                    title TEXT,
                    url TEXT,
                    externalURL TEXT,
                    contentHTML TEXT,
                    contentText TEXT,
                    summary TEXT,
                    imageURL TEXT,
                    thumbnailPath TEXT,
                    author TEXT,
                    datePublished TEXT,
                    dateArrived TEXT NOT NULL DEFAULT (datetime('now')),
                    relevanceScore REAL,
                    priority TEXT DEFAULT 'fyi',
                    topics TEXT,
                    searchRowID INTEGER,
                    UNIQUE(feedID, uniqueID)
                )
                """)
            try db.execute(sql: "CREATE INDEX article_feedID ON article(feedID)")
            try db.execute(sql: "CREATE INDEX article_dateArrived ON article(dateArrived)")
            try db.execute(sql: "CREATE INDEX article_relevanceScore ON article(relevanceScore)")
            try db.execute(sql: "CREATE INDEX article_url ON article(url)")

            // -- ARTICLE STATUS (NNW pattern: separate from content) --
            try db.execute(sql: """
                CREATE TABLE articleStatus (
                    articleID TEXT PRIMARY KEY REFERENCES article(articleID) ON DELETE CASCADE,
                    isRead INTEGER NOT NULL DEFAULT 0,
                    isStarred INTEGER NOT NULL DEFAULT 0,
                    isSaved INTEGER NOT NULL DEFAULT 0,
                    isNotified INTEGER NOT NULL DEFAULT 0,
                    dateRead TEXT,
                    dateStarred TEXT
                )
                """)
            try db.execute(sql: "CREATE INDEX articleStatus_isRead ON articleStatus(isRead)")
            try db.execute(sql: "CREATE INDEX articleStatus_isStarred ON articleStatus(isStarred)")
            try db.execute(sql: "CREATE INDEX articleStatus_isNotified ON articleStatus(isNotified)")

            // -- PRICE ALERTS --
            try db.execute(sql: """
                CREATE TABLE priceAlert (
                    id TEXT PRIMARY KEY,
                    asset TEXT NOT NULL,
                    targetPrice REAL NOT NULL,
                    direction TEXT NOT NULL,
                    isEnabled INTEGER NOT NULL DEFAULT 1,
                    isTriggered INTEGER NOT NULL DEFAULT 0,
                    triggeredAt TEXT,
                    createdAt TEXT NOT NULL DEFAULT (datetime('now'))
                )
                """)
            try db.execute(sql: "CREATE INDEX priceAlert_asset ON priceAlert(asset)")
            try db.execute(sql: "CREATE INDEX priceAlert_isEnabled ON priceAlert(isEnabled)")

            // -- USER INTERESTS --
            try db.execute(sql: """
                CREATE TABLE userInterest (
                    id TEXT PRIMARY KEY,
                    keyword TEXT NOT NULL UNIQUE,
                    weight REAL NOT NULL DEFAULT 1.0,
                    category TEXT,
                    createdAt TEXT NOT NULL DEFAULT (datetime('now'))
                )
                """)

            // -- SEED: All RSS feeds --
            try db.execute(sql: """
                INSERT INTO feed (id, title, url, homePageURL, category, type, pollInterval) VALUES
                    ('feed-coindesk', 'CoinDesk', 'https://www.coindesk.com/arc/outboundfeeds/rss/', 'https://www.coindesk.com', 'crypto', 'rss', 300),
                    ('feed-techcrunch', 'TechCrunch', 'https://techcrunch.com/feed/', 'https://techcrunch.com', 'tech', 'rss', 300),
                    ('feed-bbc-world', 'BBC World', 'https://feeds.bbci.co.uk/news/world/rss.xml', 'https://www.bbc.com/news', 'world', 'rss', 300),
                    ('feed-arxiv-ai', 'arXiv cs.AI', 'https://rss.arxiv.org/rss/cs.AI', 'https://arxiv.org', 'tech', 'rss', 1800),
                    ('feed-cointelegraph', 'CoinTelegraph', 'https://cointelegraph.com/rss', 'https://cointelegraph.com', 'crypto', 'rss', 300),
                    ('feed-arstechnica', 'Ars Technica', 'https://feeds.arstechnica.com/arstechnica/index', 'https://arstechnica.com', 'tech', 'rss', 300),
                    ('feed-theverge', 'The Verge', 'https://www.theverge.com/rss/index.xml', 'https://www.theverge.com', 'tech', 'rss', 300),
                    ('feed-wired', 'Wired', 'https://www.wired.com/feed/rss', 'https://www.wired.com', 'tech', 'rss', 600),
                    ('feed-aljazeera', 'Al Jazeera', 'https://www.aljazeera.com/xml/rss/all.xml', 'https://www.aljazeera.com', 'world', 'rss', 300),
                    ('feed-guardian', 'The Guardian', 'https://www.theguardian.com/world/rss', 'https://www.theguardian.com', 'world', 'rss', 300),
                    ('feed-npr', 'NPR News', 'https://feeds.npr.org/1001/rss.xml', 'https://www.npr.org', 'world', 'rss', 300),
                    ('feed-ft', 'Financial Times', 'https://www.ft.com/rss/home', 'https://www.ft.com', 'finance', 'rss', 300),
                    ('feed-f1-news-motorsport', 'Motorsport.com F1', 'https://www.motorsport.com/rss/f1/news/', 'https://www.motorsport.com/f1/', 'f1', 'rss', 600),
                    ('feed-f1-news-autosport', 'Autosport F1', 'https://www.autosport.com/rss/f1/news/', 'https://www.autosport.com', 'f1', 'rss', 600),
                    ('feed-f1-news-racefans', 'RaceFans', 'https://www.racefans.net/feed/', 'https://www.racefans.net', 'f1', 'rss', 600)
                """)

            // The seed rows below are joined from pieces so the private-only ones (ESPN's site API,
            // Binance's stream, the owner's interest keywords) stay out of the public flavour. The private
            // flavour runs byte for byte the SQL it always ran (MigrationSeedTests pins its SHA-256).
            let feedInsert = "INSERT INTO feed (id, title, url, homePageURL, category, type, pollInterval) VALUES\n"
            func rows(_ rows: [String]) -> String { rows.map { "    " + $0 }.joined(separator: ",\n") }

            // -- SEED: JSON API feeds --
            var jsonFeeds = [
                "('feed-hackernews', 'Hacker News', 'https://hacker-news.firebaseio.com/v0/topstories.json', 'https://news.ycombinator.com', 'tech', 'json_api', 180)",
            ]
            jsonFeeds += [
                "('feed-f1-schedule', 'F1 Schedule', 'https://api.jolpi.ca/ergast/f1/current.json', 'https://www.formula1.com', 'f1', 'json_api', 3600)",
                "('feed-f1-results', 'F1 Results', 'https://api.jolpi.ca/ergast/f1/current/last/results.json', 'https://www.formula1.com', 'f1', 'json_api', 1800)",
                "('feed-coingecko', 'CoinGecko Prices', 'https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum,solana,ripple&vs_currencies=usd&include_24hr_change=true', 'https://www.coingecko.com', 'crypto', 'json_api', 120)",
            ]
            try db.execute(sql: feedInsert + rows(jsonFeeds))

            // -- SEED: WebSocket feeds --
            var socketFeeds: [String] = []
            socketFeeds.append(
                "('feed-coincap-ws', 'CoinCap Prices', 'wss://ws.coincap.io/prices?assets=bitcoin,ethereum,solana', NULL, 'crypto', 'websocket', 0)")
            try db.execute(sql: feedInsert + rows(socketFeeds))

            // -- SEED: User interests (the owner's; a public install starts with none) --
        }

        // -- v2_mma_feeds: UFC/MMA RSS news feeds --
        migrator.registerMigration("v2_mma_feeds") { db in
            try db.execute(sql: """
                INSERT OR IGNORE INTO feed (id, title, url, homePageURL, category, type, pollInterval) VALUES
                    ('feed-ufc-espn-mma', 'ESPN MMA', 'https://www.espn.com/espn/rss/mma/news', 'https://www.espn.com/mma/', 'sports', 'rss', 600),
                    ('feed-ufc-mmafighting', 'MMA Fighting', 'https://www.mmafighting.com/rss/current.xml', 'https://www.mmafighting.com', 'sports', 'rss', 600),
                    ('feed-ufc-sherdog', 'Sherdog MMA', 'https://www.sherdog.com/rss/news.xml', 'https://www.sherdog.com', 'sports', 'rss', 600),
                    ('feed-ufc-bloodyelbow', 'Bloody Elbow', 'https://bloodyelbow.com/feed', 'https://bloodyelbow.com', 'sports', 'rss', 600)
                """)
        }

        // -- v3_clusters_search_sources: story clustering, feed health, full-text search, source audit --
        migrator.registerMigration("v3_clusters_search_sources") { db in
            // Story clustering: secondaries point at their primary.
            try db.execute(sql: "ALTER TABLE article ADD COLUMN clusterID TEXT")
            try db.execute(sql: "CREATE INDEX article_clusterID ON article(clusterID)")

            // Feed health: when did this feed last produce an article.
            try db.execute(sql: "ALTER TABLE feed ADD COLUMN lastArticleAt TEXT")
            try db.execute(sql: """
                UPDATE feed SET lastArticleAt =
                    (SELECT MAX(dateArrived) FROM article WHERE article.feedID = feed.id)
                """)

            // Full-text search over title/summary/contentText (external-content FTS5, kept in
            // sync by triggers). The update trigger fires only for the indexed columns so score
            // and status writes do not re-tokenise the article.
            try db.execute(sql: """
                CREATE VIRTUAL TABLE articleSearch USING fts5(
                    title, summary, contentText,
                    content='article', content_rowid='rowid',
                    tokenize='porter unicode61'
                )
                """)
            try db.execute(sql: """
                CREATE TRIGGER article_search_ai AFTER INSERT ON article BEGIN
                    INSERT INTO articleSearch(rowid, title, summary, contentText)
                    VALUES (new.rowid, new.title, new.summary, new.contentText);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER article_search_ad AFTER DELETE ON article BEGIN
                    INSERT INTO articleSearch(articleSearch, rowid, title, summary, contentText)
                    VALUES ('delete', old.rowid, old.title, old.summary, old.contentText);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER article_search_au AFTER UPDATE OF title, summary, contentText ON article BEGIN
                    INSERT INTO articleSearch(articleSearch, rowid, title, summary, contentText)
                    VALUES ('delete', old.rowid, old.title, old.summary, old.contentText);
                    INSERT INTO articleSearch(rowid, title, summary, contentText)
                    VALUES (new.rowid, new.title, new.summary, new.contentText);
                END
                """)
            try db.execute(sql: "INSERT INTO articleSearch(articleSearch) VALUES ('rebuild')")

            // -- Source audit (2026-09-05, every URL fetched and verified) --
            // Hacker News: one RSS request pre-filtered to 50+ points replaces 31 JSON calls per poll.
            try db.execute(sql: """
                UPDATE feed SET type = 'rss', title = 'Hacker News (50+ points)',
                    url = 'https://hnrss.org/frontpage?points=50&count=50', pollInterval = 900,
                    etag = NULL, lastModified = NULL, contentHash = NULL,
                    lastFetchError = NULL, consecutiveErrors = 0, updatedAt = datetime('now')
                WHERE id = 'feed-hackernews'
                """)
            // MMA Fighting: permanent 301 to the Atom index; skip the redirect.
            try db.execute(sql: """
                UPDATE feed SET url = 'https://www.mmafighting.com/rss/index.xml',
                    etag = NULL, lastModified = NULL, contentHash = NULL, updatedAt = datetime('now')
                WHERE id = 'feed-ufc-mmafighting'
                """)
            // FT: the markets feed carries twice the items of the home feed.
            try db.execute(sql: """
                UPDATE feed SET title = 'FT Markets', url = 'https://www.ft.com/markets?format=rss',
                    etag = NULL, lastModified = NULL, contentHash = NULL, updatedAt = datetime('now')
                WHERE id = 'feed-ft'
                """)
            // CoinCap v3 requires an API key; Binance + CoinGecko cover the same coins.
            try db.execute(sql: "DELETE FROM feed WHERE id = 'feed-coincap-ws'")
            // CoinGecko: include ethereum so battery mode (no WebSocket) still has an ETH price.
            try db.execute(sql: """
                UPDATE feed SET url = 'https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&ids=bitcoin,ethereum,solana,ripple&sparkline=true',
                    updatedAt = datetime('now')
                WHERE id = 'feed-coingecko'
                """)

            // New sources. Poll intervals are deliberately long (10 to 30 min) to keep battery ticks light.
            try db.execute(sql: """
                INSERT OR IGNORE INTO feed (id, title, url, homePageURL, category, type, pollInterval) VALUES
                    ('feed-theblock', 'The Block', 'https://www.theblock.co/rss.xml', 'https://www.theblock.co', 'crypto', 'rss', 600),
                    ('feed-decrypt', 'Decrypt', 'https://decrypt.co/feed', 'https://decrypt.co', 'crypto', 'rss', 600),
                    ('feed-cnbc-top', 'CNBC Top News', 'https://www.cnbc.com/id/100003114/device/rss/rss.html', 'https://www.cnbc.com', 'finance', 'rss', 600),
                    ('feed-marketwatch-top', 'MarketWatch', 'https://feeds.content.dowjones.io/public/rss/mw_topstories', 'https://www.marketwatch.com', 'finance', 'rss', 600),
                    ('feed-bloomberg-markets', 'Bloomberg Markets', 'https://feeds.bloomberg.com/markets/news.rss', 'https://www.bloomberg.com/markets', 'finance', 'rss', 600),
                    ('feed-iupana', 'iupana (LatAm fintech)', 'https://iupana.com/feed/', 'https://iupana.com', 'finance', 'rss', 1800),
                    ('feed-openai-news', 'OpenAI News', 'https://openai.com/news/rss.xml', 'https://openai.com/news', 'tech', 'rss', 1800),
                    ('feed-simonwillison', 'Simon Willison', 'https://simonwillison.net/atom/everything/', 'https://simonwillison.net', 'tech', 'rss', 900),
                    ('feed-404media', '404 Media', 'https://www.404media.co/rss/', 'https://www.404media.co', 'tech', 'rss', 900),
                    ('feed-dw', 'DW News', 'https://rss.dw.com/xml/rss-en-all', 'https://www.dw.com', 'world', 'rss', 600),
                    ('feed-france24-americas', 'France 24 Americas', 'https://www.france24.com/en/americas/rss', 'https://www.france24.com/en/americas/', 'world', 'rss', 900),
                    ('feed-restofworld', 'Rest of World', 'https://restofworld.org/feed/latest/', 'https://restofworld.org', 'world', 'rss', 1800),
                    ('feed-espn-nba-rss', 'ESPN NBA', 'https://www.espn.com/espn/rss/nba/news', 'https://www.espn.com/nba/', 'sports', 'rss', 600),
                    ('feed-lakers-ssr', 'Silver Screen and Roll', 'https://www.silverscreenandroll.com/rss/index.xml', 'https://www.silverscreenandroll.com', 'sports', 'rss', 900),
                    ('feed-lakersnation', 'Lakers Nation', 'https://lakersnation.com/feed/', 'https://lakersnation.com', 'sports', 'rss', 900),
                    ('feed-ufc-com', 'UFC.com', 'https://www.ufc.com/rss/news', 'https://www.ufc.com', 'sports', 'rss', 900),
                    ('feed-mmamania', 'MMA Mania', 'https://www.mmamania.com/rss/index.xml', 'https://www.mmamania.com', 'sports', 'rss', 900),
                    ('feed-therace-f1', 'The Race F1', 'https://www.the-race.com/category/formula-1/rss/', 'https://www.the-race.com/formula-1/', 'f1', 'rss', 900),
                    ('feed-bbc-f1', 'BBC Sport F1', 'https://feeds.bbci.co.uk/sport/formula1/rss.xml', 'https://www.bbc.com/sport/formula1', 'f1', 'rss', 900)
                """)
        }

        migrator.registerMigration("v4_categories_and_sources") { db in
            // -- Source audit 2026-09-06 (every URL fetched and verified) --
            // hnrss.org answers HTTP 502; Hacker News' own RSS (top 30) is the reliable feed.
            try db.execute(sql: """
                UPDATE feed SET title = 'Hacker News', url = 'https://news.ycombinator.com/rss', pollInterval = 900,
                    etag = NULL, lastModified = NULL, contentHash = NULL,
                    lastFetchError = NULL, consecutiveErrors = 0, updatedAt = datetime('now')
                WHERE id = 'feed-hackernews'
                """)
            // Bloody Elbow: /feed answers 403; /feed/ (trailing slash) is the live feed.
            try db.execute(sql: """
                UPDATE feed SET url = 'https://bloodyelbow.com/feed/',
                    etag = NULL, lastModified = NULL, contentHash = NULL,
                    lastFetchError = NULL, consecutiveErrors = 0, updatedAt = datetime('now')
                WHERE id = 'feed-ufc-bloodyelbow'
                """)
            // AI gets its own category (the owner follows AI and gadgets separately).
            try db.execute(sql: """
                UPDATE feed SET category = 'ai', updatedAt = datetime('now')
                WHERE id IN ('feed-arxiv-ai', 'feed-openai-news', 'feed-simonwillison')
                """)

            // New sources for the owner's interests (ON) and general-audience categories (OFF by default).
            // Heavy archives (Hugging Face, Import AI) poll hourly; the rest 10–30 min.
            try db.execute(sql: """
                INSERT OR IGNORE INTO feed (id, title, url, homePageURL, category, type, pollInterval, isEnabled) VALUES
                    ('feed-deepmind', 'Google DeepMind', 'https://deepmind.google/blog/rss.xml', 'https://deepmind.google/blog', 'ai', 'rss', 1800, 1),
                    ('feed-hf-blog', 'Hugging Face Blog', 'https://huggingface.co/blog/feed.xml', 'https://huggingface.co/blog', 'ai', 'rss', 3600, 1),
                    ('feed-verge-ai', 'The Verge AI', 'https://www.theverge.com/rss/ai-artificial-intelligence/index.xml', 'https://www.theverge.com/ai-artificial-intelligence', 'ai', 'rss', 900, 1),
                    ('feed-importai', 'Import AI', 'https://importai.substack.com/feed', 'https://importai.substack.com', 'ai', 'rss', 3600, 1),
                    ('feed-techcrunch-ai', 'TechCrunch AI', 'https://techcrunch.com/category/artificial-intelligence/feed/', 'https://techcrunch.com/category/artificial-intelligence/', 'ai', 'rss', 900, 1),
                    ('feed-guardian-football', 'Guardian Football', 'https://www.theguardian.com/football/rss', 'https://www.theguardian.com/football', 'sports', 'rss', 900, 1),
                    ('feed-bbc-football', 'BBC Sport Football', 'https://feeds.bbci.co.uk/sport/football/rss.xml', 'https://www.bbc.com/sport/football', 'sports', 'rss', 900, 1),
                    ('feed-espn-soccer', 'ESPN Soccer', 'https://www.espn.com/espn/rss/soccer/news', 'https://www.espn.com/soccer/', 'sports', 'rss', 900, 1),
                    ('feed-tpg', 'The Points Guy', 'https://thepointsguy.com/feed/', 'https://thepointsguy.com', 'travel', 'rss', 1800, 1),
                    ('feed-omaat', 'One Mile at a Time', 'https://onemileatatime.com/feed/', 'https://onemileatatime.com', 'travel', 'rss', 1800, 1),
                    ('feed-skift', 'Skift', 'https://skift.com/feed/', 'https://skift.com', 'travel', 'rss', 1800, 1),
                    ('feed-pitchfork', 'Pitchfork', 'https://pitchfork.com/feed/feed-news/rss', 'https://pitchfork.com/news/', 'music', 'rss', 900, 1),
                    ('feed-mixmag', 'Mixmag', 'https://mixmag.net/rss.xml', 'https://mixmag.net', 'music', 'rss', 1800, 1),
                    ('feed-djmag', 'DJ Mag', 'https://djmag.com/rss.xml', 'https://djmag.com', 'music', 'rss', 1800, 1),
                    ('feed-consequence', 'Consequence', 'https://consequence.net/feed/', 'https://consequence.net', 'music', 'rss', 900, 1),
                    ('feed-nme', 'NME', 'https://www.nme.com/feed', 'https://www.nme.com', 'music', 'rss', 900, 1),
                    ('feed-billboard', 'Billboard', 'https://www.billboard.com/feed/', 'https://www.billboard.com', 'music', 'rss', 1800, 1),
                    ('feed-motor1', 'Motor1', 'https://www.motor1.com/rss/news/all/', 'https://www.motor1.com', 'motors', 'rss', 900, 1),
                    ('feed-carscoops', 'Carscoops', 'https://www.carscoops.com/feed/', 'https://www.carscoops.com', 'motors', 'rss', 900, 1),
                    ('feed-autocar', 'Autocar', 'https://www.autocar.co.uk/rss', 'https://www.autocar.co.uk', 'motors', 'rss', 1800, 1),
                    ('feed-roadandtrack', 'Road & Track', 'https://www.roadandtrack.com/rss/all.xml/', 'https://www.roadandtrack.com', 'motors', 'rss', 900, 1),
                    ('feed-jalopnik', 'Jalopnik', 'https://jalopnik.com/rss', 'https://jalopnik.com', 'motors', 'rss', 900, 1),
                    ('feed-rideapart', 'RideApart', 'https://www.rideapart.com/rss/news/all/', 'https://www.rideapart.com', 'motors', 'rss', 1800, 1),
                    ('feed-engadget', 'Engadget', 'https://www.engadget.com/rss.xml', 'https://www.engadget.com', 'tech', 'rss', 600, 1),
                    ('feed-9to5mac', '9to5Mac', 'https://9to5mac.com/feed/', 'https://9to5mac.com', 'tech', 'rss', 900, 1),
                    ('feed-macrumors', 'MacRumors', 'https://feeds.macrumors.com/MacRumors-All', 'https://www.macrumors.com', 'tech', 'rss', 900, 1),
                    ('feed-gizmodo', 'Gizmodo', 'https://gizmodo.com/rss', 'https://gizmodo.com', 'tech', 'rss', 900, 1),
                    ('feed-politico', 'Politico', 'https://rss.politico.com/politics-news.xml', 'https://www.politico.com', 'politics', 'rss', 900, 0),
                    ('feed-bbc-politics', 'BBC Politics', 'https://feeds.bbci.co.uk/news/politics/rss.xml', 'https://www.bbc.com/news/politics', 'politics', 'rss', 900, 0),
                    ('feed-nature', 'Nature', 'https://www.nature.com/nature.rss', 'https://www.nature.com', 'science', 'rss', 3600, 0),
                    ('feed-nasa', 'NASA', 'https://www.nasa.gov/feed/', 'https://www.nasa.gov', 'science', 'rss', 1800, 0),
                    ('feed-sciencedaily', 'ScienceDaily', 'https://www.sciencedaily.com/rss/top/science.xml', 'https://www.sciencedaily.com', 'science', 'rss', 1800, 0),
                    ('feed-statnews', 'STAT', 'https://www.statnews.com/feed/', 'https://www.statnews.com', 'health', 'rss', 1800, 0),
                    ('feed-nyt-health', 'NYT Health', 'https://rss.nytimes.com/services/xml/rss/nyt/Health.xml', 'https://www.nytimes.com/section/health', 'health', 'rss', 1800, 0),
                    ('feed-ign', 'IGN', 'https://feeds.feedburner.com/ign/all', 'https://www.ign.com', 'gaming', 'rss', 900, 0),
                    ('feed-eurogamer', 'Eurogamer', 'https://www.eurogamer.net/feed', 'https://www.eurogamer.net', 'gaming', 'rss', 900, 0),
                    ('feed-variety', 'Variety', 'https://variety.com/feed/', 'https://variety.com', 'entertainment', 'rss', 900, 0),
                    ('feed-thr', 'The Hollywood Reporter', 'https://www.hollywoodreporter.com/feed/', 'https://www.hollywoodreporter.com', 'entertainment', 'rss', 900, 0)
                """)
        }

        migrator.registerMigration("v5_source_fixes") { db in
            // arXiv cs.AI lists 100–200 papers a day and drowned the AI category (5,288 of 7,486 rows
            // on 2026-09-06). Kept, but off unless ticked.
            try db.execute(sql: "UPDATE feed SET isEnabled = 0, updatedAt = datetime('now') WHERE id = 'feed-arxiv-ai'")
            // DJ Mag's /rss.xml does not parse in FeedKit; /feed is the same site's standard feed.
            try db.execute(sql: """
                UPDATE feed SET url = 'https://djmag.com/feed',
                    etag = NULL, lastModified = NULL, contentHash = NULL,
                    lastFetchError = NULL, consecutiveErrors = 0, updatedAt = datetime('now')
                WHERE id = 'feed-djmag'
                """)
            // Autocar failed only because the request had no browser-shaped User-Agent (now set on the session).
            try db.execute(sql: """
                UPDATE feed SET lastFetchError = NULL, consecutiveErrors = 0, lastFetchedAt = NULL, updatedAt = datetime('now')
                WHERE id = 'feed-autocar'
                """)
        }

        migrator.registerMigration("v6_drop_autocar") { db in
            // Well-formed XML, but it redefines the RSS content namespace as a Microsoft ingestion
            // schema and FeedKit refuses it. Motor1, Carscoops, Road & Track and Jalopnik cover cars.
            try db.execute(sql: "DELETE FROM feed WHERE id = 'feed-autocar'")
        }

        migrator.registerMigration("v7_djmag_retry") { db in
            // DJ Mag's feed stamps items in BST, which FeedKit could not decode; the fetcher now
            // rewrites named zones on its retry. Clear the six-hour backoff so it is fetched at once.
            try db.execute(sql: "UPDATE feed SET consecutiveErrors = 0, lastFetchError = NULL WHERE id = 'feed-djmag'")
            // Offline errors no longer count (FetchErrorKind); forgive the ones recorded before that.
            try db.execute(sql: "UPDATE feed SET consecutiveErrors = 0, lastFetchError = NULL WHERE lastFetchError LIKE '%Internet connection%' OR lastFetchError LIKE '%network connection%'")
        }

        migrator.registerMigration("v8_old_news_read") { db in
            // Back catalogues ingested as "new" (OpenAI News alone brought 1,160 posts back to 2015):
            // anything published more than two days ago and never starred or saved is read and told.
            try db.execute(sql: """
                UPDATE articleStatus SET isRead = 1, isNotified = 1, dateRead = datetime('now')
                WHERE isRead = 0 AND (isStarred = 0 OR isStarred IS NULL) AND (isSaved = 0 OR isSaved IS NULL)
                  AND articleID IN (SELECT articleID FROM article WHERE datePublished IS NOT NULL AND datePublished < datetime('now', '-2 days'))
                """)
        }

        migrator.registerMigration("v9_engagement") { db in
            // The learning week: what was shown, opened, dwelt on, starred, saved, dismissed. Local only.
            try db.execute(sql: """
                CREATE TABLE engagement (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    at TEXT NOT NULL DEFAULT (datetime('now')),
                    event TEXT NOT NULL,
                    articleID TEXT NOT NULL REFERENCES article(articleID) ON DELETE CASCADE,
                    value REAL
                )
                """)
            try db.execute(sql: "CREATE INDEX engagement_at ON engagement(at)")
            try db.execute(sql: "CREATE INDEX engagement_article ON engagement(articleID, event)")
        }

        migrator.registerMigration("v10_feed_topic") { db in
            // The catalog's finer topic under the chip-level category (Sports → nba, ufc, soccer).
            // Chips, counts and toggles keep reading `category`; NULL means a source the catalog does not file.
            try db.execute(sql: "ALTER TABLE feed ADD COLUMN topic TEXT")
        }

        migrator.registerMigration("v11_catalog_added") { db in
            // 1 = a catalog addition nobody has chosen yet: a category tick leaves it off (setCategoryEnabled).
            // Choosing it sets it back to 0: setTopicEnabled(true), updateFeedEnabled(true), addSource /
            // importFeeds, or ticking a category with no chosen catalog source (it is chosen whole).
            try db.execute(sql: "ALTER TABLE feed ADD COLUMN catalogAdded INTEGER NOT NULL DEFAULT 0")
        }

        migrator.registerMigration("v12_market_data_out") { db in
            // Prices follow the person's chosen instruments now (spec D10), fetched by the engine; the
            // price-only rows (two in the private build, one in the public) leave the source list. A row with stories is never dropped.
            try db.execute(sql: """
                DELETE FROM feed WHERE id IN ('feed-coingecko', 'feed-binance-ws')
                   AND NOT EXISTS (SELECT 1 FROM article WHERE article.feedID = feed.id)
                """)
        }

        return migrator
    }
}

// MARK: - Article Operations

extension AppDatabase {
    /// Insert new articles with status rows (batch, ignores duplicates).
    /// Returns array of article IDs that were actually inserted (not duplicates).
    @discardableResult
    /// `readIfPublishedBefore`: a story published before this date is a feed's back catalogue,
    /// not news — it arrives already read and told, so it never counts as new or joins a recap.
    func insertArticles(_ articles: [Article], readIfPublishedBefore cutoff: Date? = nil) async throws -> [String] {
        try await dbPool.write { db in
            var insertedIDs: [String] = []
            for article in articles {
                // Check if article already exists
                let exists = try Row.fetchOne(
                    db, sql: "SELECT 1 FROM article WHERE articleID = ?",
                    arguments: [article.articleID]) != nil
                if !exists {
                    try article.insert(db)
                    let old = cutoff.map { article.isOldNews(before: $0) } ?? false
                    let status = ArticleStatus(
                        articleID: article.articleID,
                        isRead: old, isStarred: false,
                        isSaved: false, isNotified: old,
                        dateRead: old ? Date().sqliteString : nil)
                    try status.insert(db, onConflict: .ignore)
                    insertedIDs.append(article.articleID)
                }
            }
            return insertedIDs
        }
    }

    func markRead(_ articleID: String) async throws {
        try await dbPool.write { db in
            try db.execute(
                sql: """
                    UPDATE articleStatus SET isRead = 1, dateRead = datetime('now')
                    WHERE articleID = ?
                    """, arguments: [articleID])
        }
    }

    func markAllRead() async throws {
        try await dbPool.write { db in
            try db.execute(
                sql: """
                    UPDATE articleStatus SET isRead = 1, dateRead = datetime('now')
                    WHERE isRead = 0
                    """)
        }
    }

    func markAllRead(category: String) async throws {
        try await dbPool.write { db in
            try db.execute(
                sql: """
                    UPDATE articleStatus SET isRead = 1, dateRead = datetime('now')
                    WHERE isRead = 0
                    AND articleID IN (
                        SELECT article.articleID FROM article
                        JOIN feed ON feed.id = article.feedID
                        WHERE feed.category = ?
                    )
                    """, arguments: [category])
        }
    }

    func markSaved(_ articleID: String) async throws {
        try await dbPool.write { db in
            try db.execute(
                sql: """
                    UPDATE articleStatus SET isSaved = 1
                    WHERE articleID = ?
                    """, arguments: [articleID])
        }
    }

    /// Mark a batch of articles as notified in one transaction.
    func markNotified(ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        try await dbPool.write { db in
            let placeholders = ids.map { _ in "?" }.joined(separator: ",")
            try db.execute(
                sql: "UPDATE articleStatus SET isNotified = 1 WHERE articleID IN (\(placeholders))",
                arguments: StatementArguments(ids))
        }
    }

    /// Fetch ArticleInfo for a set of article IDs (for notification evaluation after insert)
    func fetchArticleInfos(articleIDs: [String]) async throws -> [ArticleInfo] {
        guard !articleIDs.isEmpty else { return [] }
        return try await dbPool.read { db in
            let placeholders = articleIDs.map { _ in "?" }.joined(separator: ",")
            let sql = ArticleInfo.selectSQL + " WHERE article.articleID IN (\(placeholders))"
            return try ArticleInfo.fetchAll(
                db, sql: sql, arguments: StatementArguments(articleIDs))
        }
    }

    /// Full-text search across every stored article (any read state, any age), primaries only,
    /// newest first. Returns [] for queries under two characters or with no indexable tokens.
    func searchArticles(query: String, limit: Int = 100) async throws -> [ArticleInfo] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, let pattern = FTS5Pattern(matchingAllPrefixesIn: trimmed) else { return [] }
        return try await dbPool.read { db in
            let sql = ArticleInfo.selectSQL + """
                 JOIN articleSearch ON articleSearch.rowid = article.rowid
                WHERE articleSearch MATCH ?
                  AND article.clusterID IS NULL AND feed.isEnabled = 1
                ORDER BY article.dateArrived DESC
                LIMIT ?
                """
            return try ArticleInfo.fetchAll(db, sql: sql, arguments: [pattern, limit])
        }
    }
}

// MARK: - Feed Operations

/// Outcome of one feed fetch, applied to the feed row in a single batched write.
enum FeedFetchOutcome: Sendable {
    case fetched(etag: String?, lastModified: String?, contentHash: String?, conditionalGetResetAt: String?)
    case notModified
    case failed(String)
    /// The Mac could not reach the network (see FetchErrorKind): remembered, never counted.
    case offline(String)
}

struct FeedRefreshUpdate: Sendable {
    let feedID: String
    let outcome: FeedFetchOutcome
    let insertedCount: Int
    let adaptivePollInterval: Int?
}

extension AppDatabase {
    /// SQL fragment: a feed's effective interval with exponential backoff on consecutive errors,
    /// `base * 2^min(errors, 5)`, capped at 6 hours. Must stay in step with PollScheduling.effectiveInterval.
    private static let effectiveIntervalSQL =
        "min(pollInterval * (1 << min(consecutiveErrors, \(PollScheduling.maxBackoffExponent))), \(PollScheduling.maxEffectiveInterval))"

    private static func typeList(_ types: [String]) -> String {
        types.map { "'\($0)'" }.joined(separator: ",")
    }

    /// Feeds due for a refresh, honouring each feed's own interval and its error backoff.
    func fetchDueFeeds(types: [String] = ["rss", "json_api"]) async throws -> [Feed] {
        try await dbPool.read { db in
            try Feed.fetchAll(db, sql: """
                SELECT * FROM feed
                WHERE isEnabled = 1 AND type IN (\(Self.typeList(types)))
                AND (lastFetchedAt IS NULL
                     OR lastFetchedAt < datetime('now', '-' || \(Self.effectiveIntervalSQL) || ' seconds'))
                """)
        }
    }

    /// Every enabled polling feed (manual refresh).
    func fetchAllEnabledPollingFeeds(types: [String] = ["rss", "json_api"]) async throws -> [Feed] {
        try await dbPool.read { db in
            try Feed.fetchAll(db, sql: """
                SELECT * FROM feed WHERE isEnabled = 1 AND type IN (\(Self.typeList(types)))
                """)
        }
    }

    /// Seconds until the soonest polling feed is due (negative when something is already overdue).
    /// nil when there is no enabled polling feed.
    func soonestDueIn(types: [String] = ["rss", "json_api"]) async throws -> TimeInterval? {
        try await dbPool.read { db in
            try Double.fetchOne(db, sql: """
                SELECT MIN(
                    CASE WHEN lastFetchedAt IS NULL THEN 0
                    ELSE (strftime('%s', lastFetchedAt) + \(Self.effectiveIntervalSQL)) - strftime('%s', 'now')
                    END
                ) FROM feed
                WHERE isEnabled = 1 AND type IN (\(Self.typeList(types)))
                """)
        }
    }

    /// Apply every feed's fetch bookkeeping for one tick in a single transaction.
    func applyFeedRefresh(_ updates: [FeedRefreshUpdate]) async throws {
        guard !updates.isEmpty else { return }
        try await dbPool.write { db in
            for u in updates {
                switch u.outcome {
                case .fetched(let etag, let lastModified, let contentHash, let resetAt):
                    try db.execute(
                        sql: """
                            UPDATE feed SET lastFetchedAt = datetime('now'),
                                etag = ?, lastModified = ?, contentHash = ?, conditionalGetResetAt = ?,
                                lastFetchError = NULL, consecutiveErrors = 0, updatedAt = datetime('now')
                            WHERE id = ?
                            """,
                        arguments: [etag, lastModified, contentHash, resetAt, u.feedID])
                case .notModified:
                    try db.execute(
                        sql: """
                            UPDATE feed SET lastFetchedAt = datetime('now'),
                                lastFetchError = NULL, consecutiveErrors = 0, updatedAt = datetime('now')
                            WHERE id = ?
                            """, arguments: [u.feedID])
                case .failed(let message):
                    try db.execute(
                        sql: """
                            UPDATE feed SET lastFetchedAt = datetime('now'),
                                lastFetchError = ?, consecutiveErrors = consecutiveErrors + 1,
                                updatedAt = datetime('now')
                            WHERE id = ?
                            """, arguments: [message, u.feedID])
                case .offline(let message):
                    try db.execute(
                        sql: """
                            UPDATE feed SET lastFetchError = ?, updatedAt = datetime('now')
                            WHERE id = ?
                            """, arguments: [message, u.feedID])
                }
                if u.insertedCount > 0 {
                    try db.execute(
                        sql: "UPDATE feed SET lastArticleAt = datetime('now') WHERE id = ?",
                        arguments: [u.feedID])
                }
                if let interval = u.adaptivePollInterval {
                    try db.execute(
                        sql: "UPDATE feed SET pollInterval = ? WHERE id = ? AND pollInterval != ?",
                        arguments: [interval, u.feedID, interval])
                }
            }
        }
    }
}

// MARK: - Upsert (for ESPN live score updates)

extension AppDatabase {
    /// Insert new articles or update existing ones. Returns IDs of newly inserted articles only.
    @discardableResult
    func upsertArticles(_ articles: [Article]) async throws -> [String] {
        try await dbPool.write { db in
            var newIDs: [String] = []
            for article in articles {
                let exists = try Row.fetchOne(
                    db, sql: "SELECT 1 FROM article WHERE articleID = ?",
                    arguments: [article.articleID]) != nil
                if exists {
                    try db.execute(
                        sql: """
                            UPDATE article SET title = ?, url = ?, contentText = ?, summary = ?, priority = ?
                            WHERE articleID = ?
                            """,
                        arguments: [
                            article.title, article.url, article.contentText,
                            article.summary, article.priority, article.articleID,
                        ])
                } else {
                    try article.insert(db)
                    try ArticleStatus(
                        articleID: article.articleID,
                        isRead: false, isStarred: false,
                        isSaved: false, isNotified: false
                    ).insert(db, onConflict: .ignore)
                    newIDs.append(article.articleID)
                }
            }
            return newIDs
        }
    }

    /// Update a feed's poll interval (used for ESPN adaptive polling)
    func updateFeedPollInterval(feedID: String, pollInterval: Int) async throws {
        try await dbPool.write { db in
            try db.execute(
                sql: "UPDATE feed SET pollInterval = ?, updatedAt = datetime('now') WHERE id = ?",
                arguments: [pollInterval, feedID])
        }
    }
}

// MARK: - Price Alert Operations

extension AppDatabase {
    func fetchEnabledPriceAlerts() async throws -> [PriceAlert] {
        try await dbPool.read { db in
            try PriceAlert.fetchAll(
                db,
                sql: "SELECT * FROM priceAlert WHERE isEnabled = 1 AND isTriggered = 0")
        }
    }

    /// Reactive view of the enabled, untriggered alerts so the WebSocket stream never hits SQLite.
    static func enabledPriceAlertsObservation() -> ValueObservation<ValueReducers.Fetch<[PriceAlert]>> {
        ValueObservation.tracking { db in
            try PriceAlert.fetchAll(
                db, sql: "SELECT * FROM priceAlert WHERE isEnabled = 1 AND isTriggered = 0")
        }
    }

    func triggerPriceAlert(id: String) async throws {
        try await dbPool.write { db in
            try db.execute(
                sql: """
                    UPDATE priceAlert SET isTriggered = 1, triggeredAt = datetime('now')
                    WHERE id = ?
                    """, arguments: [id])
        }
    }
}

// MARK: - Star/Save Operations

extension AppDatabase {
    func toggleStarred(_ articleID: String) async throws {
        try await dbPool.write { db in
            let wasStarred = try Bool.fetchOne(db, sql: "SELECT isStarred FROM articleStatus WHERE articleID = ?", arguments: [articleID]) ?? false
            if !wasStarred { try db.execute(sql: "INSERT INTO engagement (event, articleID) VALUES ('starred', ?)", arguments: [articleID]) }
            try db.execute(
                sql: """
                    UPDATE articleStatus SET
                        isStarred = CASE WHEN isStarred = 1 THEN 0 ELSE 1 END,
                        dateStarred = CASE WHEN isStarred = 0 THEN datetime('now') ELSE NULL END
                    WHERE articleID = ?
                    """, arguments: [articleID])
        }
    }

    func toggleSaved(_ articleID: String) async throws {
        try await dbPool.write { db in
            let wasSaved = try Bool.fetchOne(db, sql: "SELECT isSaved FROM articleStatus WHERE articleID = ?", arguments: [articleID]) ?? false
            if !wasSaved { try db.execute(sql: "INSERT INTO engagement (event, articleID) VALUES ('saved', ?)", arguments: [articleID]) }
            try db.execute(
                sql: """
                    UPDATE articleStatus SET
                        isSaved = CASE WHEN isSaved = 1 THEN 0 ELSE 1 END
                    WHERE articleID = ?
                    """, arguments: [articleID])
        }
    }
}

// MARK: - Feed Management

extension AppDatabase {
    func fetchAllFeeds() async throws -> [Feed] {
        try await dbPool.read { db in
            try Feed.fetchAll(db, sql: "SELECT * FROM feed ORDER BY category, title")
        }
    }

    /// Switching one source on is choosing it (`catalogAdded` cleared), so a category re-tick keeps it.
    func updateFeedEnabled(feedID: String, isEnabled: Bool) async throws {
        try await dbPool.write { db in
            try db.execute(
                sql: isEnabled
                    ? "UPDATE feed SET isEnabled = 1, catalogAdded = 0, updatedAt = datetime('now') WHERE id = ?"
                    : "UPDATE feed SET isEnabled = 0, updatedAt = datetime('now') WHERE id = ?",
                arguments: [feedID])
        }
    }

    func addFeed(title: String, url: String, category: String, type: String = "rss", pollInterval: Int = 300) async throws {
        let id = Feed.makeID(url: url)
        try await dbPool.write { db in
            try db.execute(
                sql: """
                    INSERT OR IGNORE INTO feed (id, title, url, category, type, pollInterval)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [id, title, url, category, type, pollInterval])
        }
    }

    func deleteFeed(feedID: String) async throws {
        try await dbPool.write { db in
            // CASCADE will delete articles and articleStatus
            try db.execute(sql: "DELETE FROM feed WHERE id = ?", arguments: [feedID])
        }
    }
}

// MARK: - Interest Management

extension AppDatabase {
    func addInterest(keyword: String, weight: Double, category: String?) async throws {
        let id = "int-\(keyword.lowercased().replacingOccurrences(of: " ", with: "-"))"
        try await dbPool.write { db in
            try db.execute(
                sql: """
                    INSERT OR IGNORE INTO userInterest (id, keyword, weight, category)
                    VALUES (?, ?, ?, ?)
                    """,
                arguments: [id, keyword, weight, category])
        }
    }

    func removeInterest(id: String) async throws {
        try await dbPool.write { db in
            try db.execute(sql: "DELETE FROM userInterest WHERE id = ?", arguments: [id])
        }
    }

    func updateInterestWeight(id: String, weight: Double) async throws {
        try await dbPool.write { db in
            try db.execute(
                sql: "UPDATE userInterest SET weight = ? WHERE id = ?",
                arguments: [weight, id])
        }
    }
}

// MARK: - Retention Cleanup

extension AppDatabase {
    /// Delete articles older than retentionDays, keeping starred and min per feed.
    /// Returns number of articles deleted.
    @discardableResult
    func cleanupOldArticles(retentionDays: Int = 90, minPerFeed: Int = 10) async throws -> Int {
        try await dbPool.write { db in
            // Find articles eligible for deletion:
            // - older than retention period
            // - not starred
            // - not in the newest `minPerFeed` per feed
            let deleted = try Int.fetchOne(db, sql: """
                WITH keep_per_feed AS (
                    SELECT articleID FROM (
                        SELECT articleID, feedID,
                               ROW_NUMBER() OVER (PARTITION BY feedID ORDER BY dateArrived DESC) AS rn
                        FROM article
                    ) WHERE rn <= ?
                ),
                starred AS (
                    SELECT articleID FROM articleStatus WHERE isStarred = 1
                )
                SELECT COUNT(*) FROM article
                WHERE dateArrived < datetime('now', '-' || ? || ' days')
                  AND articleID NOT IN (SELECT articleID FROM keep_per_feed)
                  AND articleID NOT IN (SELECT articleID FROM starred)
                """, arguments: [minPerFeed, retentionDays]) ?? 0

            try db.execute(sql: """
                WITH keep_per_feed AS (
                    SELECT articleID FROM (
                        SELECT articleID, feedID,
                               ROW_NUMBER() OVER (PARTITION BY feedID ORDER BY dateArrived DESC) AS rn
                        FROM article
                    ) WHERE rn <= ?
                ),
                starred AS (
                    SELECT articleID FROM articleStatus WHERE isStarred = 1
                )
                DELETE FROM article
                WHERE dateArrived < datetime('now', '-' || ? || ' days')
                  AND articleID NOT IN (SELECT articleID FROM keep_per_feed)
                  AND articleID NOT IN (SELECT articleID FROM starred)
                """, arguments: [minPerFeed, retentionDays])

            // Clean orphaned articleStatus records
            try db.execute(sql: """
                DELETE FROM articleStatus
                WHERE articleID NOT IN (SELECT articleID FROM article)
                """)

            // Promote secondaries whose primary was pruned, so they become visible again.
            try db.execute(sql: """
                UPDATE article SET clusterID = NULL
                WHERE clusterID IS NOT NULL
                  AND NOT EXISTS (SELECT 1 FROM article p WHERE p.articleID = article.clusterID)
                """)

            return deleted
        }
    }
}

// MARK: - Database Stats

extension AppDatabase {
    struct DatabaseStats: Sendable {
        let totalArticles: Int
        let unreadCount: Int
        let starredCount: Int
        let articlesByCategory: [(category: String, count: Int)]
        let oldestArticleDate: String?
        let feedCount: Int
        let dbFileSizeBytes: Int64
    }

    func fetchDatabaseStats() async throws -> DatabaseStats {
        // Get file size outside the DB read (db.path is internal in GRDB)
        let dbFileSize: Int64
        if let attrs = try? FileManager.default.attributesOfItem(atPath: Self.defaultPath),
            let size = attrs[.size] as? Int64
        {
            dbFileSize = size
        } else {
            dbFileSize = 0
        }

        return try await dbPool.read { db in
            let total = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM article") ?? 0
            let unread = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM articleStatus WHERE isRead = 0
                """) ?? 0
            let starred = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM articleStatus WHERE isStarred = 1
                """) ?? 0
            let oldest = try String.fetchOne(db, sql: """
                SELECT MIN(dateArrived) FROM article
                """)
            let feedCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM feed") ?? 0

            let catRows = try Row.fetchAll(db, sql: """
                SELECT feed.category, COUNT(*) as cnt
                FROM article JOIN feed ON feed.id = article.feedID
                GROUP BY feed.category ORDER BY cnt DESC
                """)
            let byCategory = catRows.map { row in
                (category: row["category"] as String, count: row["cnt"] as Int)
            }

            return DatabaseStats(
                totalArticles: total, unreadCount: unread, starredCount: starred,
                articlesByCategory: byCategory, oldestArticleDate: oldest,
                feedCount: feedCount, dbFileSizeBytes: dbFileSize)
        }
    }

    /// Fetch feeds with their error/health status for the debug viewer
    func fetchFeedStatuses() async throws -> [Feed] {
        try await dbPool.read { db in
            try Feed.fetchAll(db, sql: "SELECT * FROM feed ORDER BY consecutiveErrors DESC, title")
        }
    }
}

// MARK: - Unread Count Observation

extension AppDatabase {
    /// ValueObservation for unread count — reactive, updates SwiftUI automatically
    static func unreadCountObservation() -> ValueObservation<ValueReducers.Fetch<Int>> {
        ValueObservation.tracking { db -> Int in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM articleStatus WHERE isRead = 0") ?? 0
        }
    }
}

// MARK: - AI Pipeline Operations

extension AppDatabase {
    /// Fetch all user interests for keyword scoring
    func fetchAllInterests() async throws -> [UserInterest] {
        try await dbPool.read { db in
            try UserInterest.fetchAll(db)
        }
    }

    /// Dedup candidates for the lookback window: a slim projection (no contentHTML, 500 chars of
    /// text) instead of full Article rows, loaded once per tick.
    func fetchDedupCandidates(days: Int = PulseFeedConstants.dedupLookbackDays) async throws -> [DedupCandidate] {
        try await dbPool.read { db in
            try DedupCandidate.fetchAll(db, sql: """
                SELECT articleID, feedID, uniqueID, url, title,
                       substr(contentText, 1, 500) AS contentPrefix, clusterID, dateArrived
                FROM article
                WHERE dateArrived > datetime('now', '-\(days) days')
                """)
        }
    }

    /// Update keyword scores for a batch of articles (Tier 1 — local scoring). Never overwrites
    /// an article that already carries a model-assigned score (it has a summary).
    func updateKeywordScores(_ scores: [(articleID: String, score: Double)]) async throws {
        guard !scores.isEmpty else { return }
        try await dbPool.write { db in
            for (articleID, score) in scores {
                try db.execute(
                    sql: """
                        UPDATE article SET relevanceScore = ?
                        WHERE articleID = ? AND (summary IS NULL OR summary = '')
                        """, arguments: [score, articleID])
            }
        }
    }

    /// Store a batch of model enrichments in one transaction.
    func updateAIEnrichments(_ items: [(articleID: String, enrichment: AIEnrichment, relevance: Double)]) async throws {
        guard !items.isEmpty else { return }
        try await dbPool.write { db in
            for item in items {
                try db.execute(
                    sql: """
                        UPDATE article SET summary = ?, relevanceScore = ?, priority = ?, topics = ?
                        WHERE articleID = ?
                        """,
                    arguments: [
                        item.enrichment.tldr, item.relevance, item.enrichment.priority,
                        item.enrichment.topics.joined(separator: ","), item.articleID,
                    ])
            }
        }
    }

    /// Update article with full AI enrichment (Tier 2 — Claude Haiku results)
    func updateAIEnrichment(
        articleID: String, summary: String, relevanceScore: Double,
        priority: String, topics: String
    ) async throws {
        try await dbPool.write { db in
            try db.execute(
                sql: """
                    UPDATE article SET summary = ?, relevanceScore = ?, priority = ?, topics = ?
                    WHERE articleID = ?
                    """, arguments: [summary, relevanceScore, priority, topics, articleID])
        }
    }

    /// Fetch full Article records by IDs (for AI enrichment after insert)
    func fetchArticles(ids: [String]) async throws -> [Article] {
        guard !ids.isEmpty else { return [] }
        return try await dbPool.read { db in
            let placeholders = ids.map { _ in "?" }.joined(separator: ",")
            return try Article.fetchAll(
                db,
                sql: "SELECT * FROM article WHERE articleID IN (\(placeholders))",
                arguments: StatementArguments(ids))
        }
    }
}

// MARK: - Recent Articles for Digest

extension AppDatabase {
    /// Recent primaries (cluster secondaries excluded) for the daily brief.
    func fetchRecentArticleInfos(hours: Int, limit: Int) async throws -> [ArticleInfo] {
        try await dbPool.read { db in
            let sql = ArticleInfo.selectSQL + """
                 WHERE feed.isEnabled = 1 AND article.clusterID IS NULL
                   AND article.dateArrived > datetime('now', ?)
                ORDER BY article.dateArrived DESC
                LIMIT ?
                """
            return try ArticleInfo.fetchAll(db, sql: sql, arguments: ["-\(hours) hours", limit])
        }
    }
}

// MARK: - Top Headlines

extension AppDatabase {
    func fetchTopUnreadTitles(limit: Int = 5) async throws -> [String] {
        try await dbPool.read { db in
            let sql = """
                SELECT article.title FROM article
                JOIN articleStatus ON articleStatus.articleID = article.articleID
                WHERE (articleStatus.isRead = 0 OR articleStatus.isRead IS NULL)
                AND article.title IS NOT NULL AND article.clusterID IS NULL
                ORDER BY article.dateArrived DESC
                LIMIT ?
                """
            return try String.fetchAll(db, sql: sql, arguments: [limit])
        }
    }
}

// MARK: - Database Path

extension AppDatabase {
    /// Environment keys that run the binary as a tool and quit. Such a run opens a throwaway database,
    /// never the live one: opening applies migrations (a 2026-10-22 `make check-catalog` run migrated
    /// the live store this way).
    static let toolRunKeys = ["PULSEFEED_CHECK_CATALOG", "PULSEFEED_DEBUG_EXPORT_ICON", "PULSEFEED_DEBUG_INTERESTS",
                              "PULSEFEED_DEBUG_WELCOME", "PULSEFEED_RENDER_SHOWCASE"]

    /// The database a launch opens: the live one, or a fresh temporary one for a tool run.
    static func launchPath(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        guard toolRunKeys.contains(where: { !(environment[$0] ?? "").isEmpty }) else { return defaultPath }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("PulseFeed-tool-\(UUID().uuidString)/pulsefeed.sqlite").path
    }

    static var defaultPath: String {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("PulseFeed", isDirectory: true)
            .appendingPathComponent("pulsefeed.sqlite")
            .path
    }
}
