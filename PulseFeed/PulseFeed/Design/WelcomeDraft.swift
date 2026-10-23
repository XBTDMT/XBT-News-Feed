import Foundation

/// A starter pack only ticks topics (spec §6, step 2).
struct WelcomePack: Identifiable, Sendable {
    let id: String
    let label: String
    let symbol: String
    let topics: [String]

    static let all: [WelcomePack] = [
        WelcomePack(id: "markets", label: "Markets desk", symbol: "chart.line.uptrend.xyaxis",
                    topics: ["markets", "economy", "crypto", "business", "personal-finance"]),
        WelcomePack(id: "sports", label: "Sports fan", symbol: "sportscourt", topics: ["nba", "nfl", "soccer", "f1", "ufc"]),
        WelcomePack(id: "tech", label: "Tech & AI", symbol: "cpu", topics: ["tech", "ai", "apple", "gadgets", "programming"]),
        WelcomePack(id: "world", label: "World desk", symbol: "globe",
                    topics: ["world", "us-news", "politics", "europe", "asia", "climate"]),
        WelcomePack(id: "culture", label: "Culture", symbol: "film", topics: ["music", "movies", "tv", "gaming", "books"]),
        WelcomePack(id: "life", label: "Life & home", symbol: "house", topics: ["travel", "food-drink", "home-diy", "outdoors", "pets"]),
    ]
}

/// The seven screens. Only Topics needs a choice; Sources to Look can be skipped (their draft values stand).
enum WelcomeStep: Int, CaseIterable, Sendable {
    case welcome, topics, sources, follow, alerts, look, done

    var next: WelcomeStep? { WelcomeStep(rawValue: rawValue + 1) }
    var previous: WelcomeStep? { WelcomeStep(rawValue: rawValue - 1) }
    var isSkippable: Bool { [.sources, .follow, .alerts, .look].contains(self) }

    func canAdvance(_ draft: WelcomeDraft) -> Bool {
        self == .topics ? !(draft.topics.isEmpty && draft.typedMatches.isEmpty) : true
    }
}

/// A site added in the Sources step, added at Finish.
struct AddedSite: Equatable, Sendable {
    var title: String
    var url: String
    var category: String
}

/// Every choice the flow makes, held in memory until Finish (`AppDatabase.applyWelcome`), so Back changes
/// nothing on disk and quitting halfway applies nothing.
struct WelcomeDraft: Equatable, Sendable {
    var topics: [String] = []
    /// What the Topics step's type-anything box added (topics, follows, searches).
    var typedMatches: [InterestMatch] = []
    /// Source on/off chosen in the Sources step, by URL; everything else follows `isOn`'s default.
    var sourceSwitches: [String: Bool] = [:]
    /// On a re-run ("Run the welcome again"), each source's state now, by URL: what the Sources step shows and
    /// Finish keeps unless switched. Empty on a fresh install.
    var current: [String: Bool] = [:]
    var addedSites: [AddedSite] = []
    /// Names picked or typed in the Follow step.
    var follows: [InterestMatch] = []
    var alertMode: AlertMode = .breakingAndRecap
    /// Seconds between recaps: 300, 900, 1800 or 3600 (0 = off, kept when already stored).
    var recapInterval: Int = 900
    var design: AppDesign = .deck
    var appearance: AppAppearance = .light
    var instruments: [String] = []
    var pricesInMenuBar = false
    var openAtLogin = false

    static let capsuleKey = "menubar_btc_capsule"

    /// Starts from what is stored, so "Run the welcome again" opens on today's settings.
    static func initial(_ d: UserDefaults) -> WelcomeDraft {
        var draft = WelcomeDraft()
        draft.alertMode = AlertMode.stored(d)
        draft.recapInterval = Int(d.object(forKey: SummaryComposer.intervalKey) as? Double ?? SummaryComposer.defaultInterval)
        draft.design = AppDesign.resolve(defaultsValue: d.string(forKey: AppDesign.defaultsKey), environmentValue: nil)
        draft.appearance = AppAppearance.resolve(d.string(forKey: AppAppearance.defaultsKey))
        draft.instruments = MarketInstrument.stored(d)
        draft.pricesInMenuBar = d.bool(forKey: capsuleKey)
        return draft
    }

    mutating func toggle(pack: WelcomePack) {
        if pack.topics.allSatisfy(topics.contains) {
            topics.removeAll { pack.topics.contains($0) }
        } else {
            for t in pack.topics where !topics.contains(t) { topics.append(t) }
        }
    }

    /// What a type-anything box added: a topic is ticked (so its sources, follows and preview show, as if
    /// picked by hand), a name joins the follows, a search waits for Finish.
    mutating func addTyped(_ matches: [InterestMatch]) {
        for m in matches {
            switch m {
            case .topic(let id): if !topics.contains(id) { topics.append(id) }
            case .follow: if !follows.contains(m) { follows.append(m) }
            case .newSearch: if !typedMatches.contains(m) { typedMatches.append(m) }
            }
        }
    }

    mutating func toggle(topic: String) {
        if let i = topics.firstIndex(of: topic) { topics.remove(at: i) } else { topics.append(topic) }
    }

    /// False when a sixth instrument is refused.
    @discardableResult
    mutating func setInstrument(_ id: String, on: Bool) -> Bool {
        if !on { instruments.removeAll { $0 == id }; return true }
        guard !instruments.contains(id) else { return true }
        guard instruments.count < MarketInstrument.maxChosen else { return false }
        instruments.append(id)
        return true
    }

    /// What a re-run's `current` should hold: the states of the sources of topics the install has on now
    /// (at least one enabled source). A topic that is off speaks for nothing, so ticking it on a re-run
    /// offers its sources as a fresh pick would.
    static func currentStates(_ states: [String: Bool], catalog: Catalog) -> [String: Bool] {
        let byTopic = Dictionary(grouping: catalog.sources, by: \.topic)
        var out: [String: Bool] = [:]
        for (_, sources) in byTopic where sources.contains(where: { states[$0.url] == true }) {
            for s in sources { if let on = states[s.url] { out[s.url] = on } }
        }
        return out
    }

    func isOn(_ source: CatalogSource) -> Bool {
        sourceSwitches[source.url] ?? current[source.url] ?? !(source.startsOff ?? false)
    }

    /// The outlets each picked topic would turn on, in the order picked: the person's region first, then
    /// global, then the rest, each by title. Only sources the flow may offer.
    func sources(catalog: Catalog, region: String) -> [(topic: CatalogTopic, sources: [CatalogSource])] {
        func rank(_ s: CatalogSource) -> Int { s.region == region ? 0 : s.region == "global" ? 1 : 2 }
        return topics.compactMap { id in
            guard let topic = catalog.topic(id) else { return nil }
            let offered = catalog.sources(topic: id).filter(\.isOffered)
                .sorted { (rank($0), $0.title) < (rank($1), $1.title) }
            return (topic, offered)
        }
    }

    /// The Topics step's live line.
    func counts(catalog: Catalog) -> (topics: Int, sources: Int, searches: Int) {
        let typedTopics = typedMatches.compactMap { if case .topic(let id) = $0 { return id } else { return nil } }
        let picked = Set(topics + typedTopics)
        let on = catalog.sources.filter { picked.contains($0.topic) && $0.isOffered && isOn($0) }.count
        let searches = typedMatches.filter { if case .newSearch = $0 { return true } else { return false } }.count
        return (picked.count, on + addedSites.count, searches)
    }

    /// Names to suggest in the Follow step: the picked topics' follows, in order, at most 24. A name several
    /// picked topics share (nvidia under Markets, Tech and AI) is one chip, under the first of them.
    func suggestedFollows(catalog: Catalog) -> [InterestMatch] {
        var out: [InterestMatch] = []
        var seen: Set<String> = []
        for id in topics {
            for name in catalog.topic(id)?.follows ?? [] where seen.insert(name.lowercased()).inserted {
                out.append(.follow(name: name, topicID: id))
                if out.count == 24 { return out }
            }
        }
        return out
    }

    /// Live NBA scores are worth offering (the balldontlie card, D13).
    var wantsLiveGames: Bool {
        topics.contains("nba") || (follows + typedMatches).contains { if case .follow(_, "nba"?) = $0 { return true } else { return false } }
    }

    /// A Money topic picked with no instruments chosen yet: offer the usual five.
    mutating func suggestInstrumentsIfEmpty(catalog: Catalog) {
        guard instruments.isEmpty, topics.contains(where: { catalog.topic($0)?.group == .money }) else { return }
        instruments = MarketInstrument.suggested
    }

    /// Topics first, then what was typed, then the follows; no repeats.
    func matchesToApply() -> [InterestMatch] {
        var out: [InterestMatch] = []
        for m in topics.map({ InterestMatch.topic(id: $0) }) + typedMatches + follows where !out.contains(m) { out.append(m) }
        return out
    }
}

/// What Finish does besides the database writes (`AppDatabase.applyWelcome`).
enum WelcomeFinish {
    enum Action: Hashable, Sendable {
        /// "It applies when you finish": the look changes now, not at the next launch.
        case applyAppearance(AppAppearance)
        /// Someone who skipped Alerts or never pressed "Allow notifications" would otherwise get no banner
        /// until the next launch asked (a fresh install never asks at launch).
        case askNotifications
        case openAtLogin
    }

    static func actions(_ draft: WelcomeDraft, notificationsUndecided: Bool) -> Set<Action> {
        var out: Set<Action> = [.applyAppearance(draft.appearance)]
        if notificationsUndecided, draft.alertMode != .quiet { out.insert(.askNotifications) }
        if draft.openAtLogin { out.insert(.openAtLogin) }
        return out
    }
}

/// Fixed words of the flow that tests pin.
enum WelcomeCopy {
    /// Spec §10 C1: what can break through as an alert, in the Alerts step.
    static let alertKinds = [
        "World events: a war breaking out, a ceasefire, a coup, a major death.",
        "A topic's own big news, while that topic is on: an exchange hack under Crypto, a model launch under AI, tour dates under Music.",
        "Anything major about a name you follow: a trade, a signing, a launch.",
    ]
}
