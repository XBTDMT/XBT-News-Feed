import Foundation

/// Three tiers. `urgent` interrupts now (its own notification); `headline` leads the next summary
/// without interrupting; `summary` is rolled into the 15-minute recap.
enum UrgencyTier: Int, Comparable, Sendable {
    case summary = 0, headline = 1, urgent = 2
    static func < (a: UrgencyTier, b: UrgencyTier) -> Bool { a.rawValue < b.rawValue }
}

/// The install's rules, editable as text in Settings › Notifications. A pattern is a lowercase substring;
/// "a&b" means both must appear. Followed entities interrupt when paired with an event word.
struct UrgencyRules: Sendable, Equatable {
    var urgentPatterns: [String]
    var headlinePatterns: [String]
    var followed: [String]
    var neverUrgent: [String]
    /// Daily move, percent, for SPY / MAG7.
    var spyThreshold: Double
    /// 24 h move, percent, for BTC / ETH / SOL / XRP.
    var btcThreshold: Double
    var perHour: Int
    var perDay: Int

    static let defaultsKey = "urgency_rules"

    /// The three-axis rule (magnitude × time-sensitivity × relevance) as keyword floors. The model
    /// refines these; the keyword layer alone runs on critical battery.
    /// A new user's rules. An install already in use keeps its own stored text (`SettingsFreeze`), so
    /// changing these never changes what such an install interrupts for. A line "<category or topic>:
    /// <pattern>" applies only to stories from that chip-level category or catalog topic.
    static let defaults = UrgencyRules(
        urgentPatterns: [
            "ceasefire", "peace deal", "invasion", "invades", "declares war", "war breaks out", "coup ",
            "assassinat", "martial law", "nuclear strike",
            "crypto: exchange hack", "crypto: hacked&exchange", "crypto: insolven&exchange", "crypto: halts withdrawals",
            "crypto: all-time high&bitcoin", "crypto: etf approv",
            "finance: circuit breaker", "finance: emergency rate",
            "ai: gpt-&releas", "ai: gpt-&launch", "ai: claude&releas", "ai: claude&launch", "ai: gemini&releas",
            "ai: gemini&launch", "ai: frontier model", "ai: new model&anthropic", "ai: new model&openai",
            "music: tour dates", "music: announces&tour", "music: world tour",
        ],
        headlinePatterns: [
            "retire", "blockbuster", "dies at", "dead at", "passes away", "resigns", "steps down",
            "record high", "record low", "all-time high", "wins championship", "wins title", "sacked", "fired",
        ],
        followed: [],
        neverUrgent: ["rumor", "rumour", "report:", "reportedly", "opinion", "preview", "power rankings", "recap"],
        spyThreshold: 2.5,
        btcThreshold: 7.0,
        perHour: 3,
        perDay: 10)

    /// Event words that make a followed-entity story urgent (a trade, a signing, a launch, tour dates).
    static let eventWords = [
        "trade", "traded", "acquire", "sign", "signs", "signing", "waive", "release", "releases", "launch",
        "launches", "unveil", "announce", "announces", "tour", "dates", "fired", "hired", "retire", "injur",
        "out for", "suspend", "recall", "reveal",
    ]

    var asText: String {
        """
        # Urgent — its own alert, right away (one per line; "a&b" means both must appear; "crypto: …" only for that category or topic)
        \(urgentPatterns.joined(separator: "\n"))

        # Followed — anything major about these interrupts (trade, signing, launch, tour dates…)
        \(followed.joined(separator: "\n"))

        # Headline — leads the next summary, no interrupt
        \(headlinePatterns.joined(separator: "\n"))

        # Never urgent — demotes a match one tier
        \(neverUrgent.joined(separator: "\n"))

        # Markets
        spy move % = \(Self.number(spyThreshold))
        btc move % = \(Self.number(btcThreshold))
        alerts per hour = \(perHour)
        alerts per day = \(perDay)
        """
    }

    static func parse(_ text: String) -> UrgencyRules {
        var r = defaults
        r.urgentPatterns = []; r.followed = []; r.headlinePatterns = []; r.neverUrgent = []
        var section = ""
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("#") {
                let h = line.lowercased()
                section = h.contains("urgent") && !h.contains("never") ? "urgent"
                    : h.contains("followed") ? "followed"
                    : h.contains("headline") ? "headline"
                    : h.contains("never") ? "never"
                    : h.contains("market") ? "markets" : ""
                continue
            }
            let value = line.lowercased()
            switch section {
            case "urgent": r.urgentPatterns.append(value)
            case "followed": r.followed.append(value)
            case "headline": r.headlinePatterns.append(value)
            case "never": r.neverUrgent.append(value)
            case "markets":
                let parts = value.split(separator: "=").map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2 else { continue }
                if parts[0].hasPrefix("spy"), let v = Double(parts[1]) { r.spyThreshold = v }
                if parts[0].hasPrefix("btc"), let v = Double(parts[1]) { r.btcThreshold = v }
                if parts[0].hasPrefix("alerts per hour"), let v = Int(parts[1]) { r.perHour = v }
                if parts[0].hasPrefix("alerts per day"), let v = Int(parts[1]) { r.perDay = v }
            default: continue
            }
        }
        if r.urgentPatterns.isEmpty && r.followed.isEmpty && r.headlinePatterns.isEmpty { return defaults }
        return r
    }

    /// The followed names without their chip scope ("sports: heat" → "heat"), for the AI prompt and the
    /// live-game poll.
    var followedNames: [String] {
        var seen = Set<String>()
        return followed.map { UrgencyClassifier.splitScope($0)?.rest ?? $0 }.filter { seen.insert($0).inserted }
    }

    /// The rules with these names followed too: lowercased, trimmed, in order, no repeats.
    func addingFollows(_ names: [String]) -> UrgencyRules {
        var r = self
        func bare(_ f: String) -> String { UrgencyClassifier.splitScope(f)?.rest ?? f }
        for raw in names {
            // A leading "#" would read back as a section header in the stored text.
            let name = String(raw.lowercased().trimmingCharacters(in: .whitespaces).drop(while: { $0 == "#" }))
                .trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !r.followed.contains(name) else { continue }
            let plain = bare(name) == name
            if plain {
                // Followed everywhere supersedes the same name scoped to one chip.
                r.followed.removeAll { bare($0) == name }
            } else if r.followed.contains(bare(name)) {
                continue
            }
            r.followed.append(name)
        }
        return r
    }

    static func stored(_ d: UserDefaults = .standard) -> UrgencyRules {
        guard let text = d.string(forKey: defaultsKey), !text.isEmpty else { return defaults }
        return parse(text)
    }

    private static func number(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(v)
    }
}

enum UrgencyClassifier {
    /// The keyword floor. Runs on every new story, on every tier.
    static func keywordTier(title: String, category: String, topic: String?, rules: UrgencyRules) -> UrgencyTier {
        let t = " " + title.lowercased() + " "
        func hit(_ pattern: String) -> Bool {
            guard let bare = inScope(pattern, category: category, topic: topic) else { return false }
            return matches(t, bare)
        }
        let vetoed = rules.neverUrgent.contains(where: hit)
        var tier: UrgencyTier = .summary
        if rules.urgentPatterns.contains(where: hit) {
            tier = .urgent
        } else if rules.followed.contains(where: { name in
                      inScope(name, category: category, topic: topic).map { containsName(title, $0) } ?? false }),
                  UrgencyRules.eventWords.contains(where: { t.contains($0) }) {
            tier = .urgent
        } else if rules.headlinePatterns.contains(where: hit) {
            tier = .headline
        }
        if vetoed, tier == .urgent { tier = .headline }
        return tier
    }

    /// The catalog's topic ids, so a topic scope is recognised in the running app.
    static let catalogTopicIDs: Set<String> = Set(Catalog.bundled?.topics.map(\.id) ?? [])

    /// "<scope>: <rest>" when the scope is a chip-level category id or a catalog topic id (or `topic`, the
    /// story's own); anything else ("mission: impossible", "report:") is a plain pattern or name. The one
    /// scope grammar: patterns, follows, `followedNames`.
    static func splitScope(_ s: String, topic: String? = nil) -> (scope: String, rest: String)? {
        guard let colon = s.range(of: ": ") else { return nil }
        let scope = String(s[..<colon.lowerBound])
        let rest = s[colon.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty,
              NewsCategory.pickerIDs.contains(scope) || catalogTopicIDs.contains(scope) || scope == topic else { return nil }
        return (scope, rest)
    }

    /// "crypto: exchange hack" → "exchange hack" when the story's category or topic is "crypto", nil when
    /// it is not; a pattern without a scope applies everywhere and is returned as is.
    static func inScope(_ pattern: String, category: String, topic: String?) -> String? {
        guard let (scope, rest) = splitScope(pattern, topic: topic) else { return pattern }
        return scope == category || scope == topic ? rest : nil
    }

    /// A followed name is one literal name ("at&t" is not "at" and "t"), matched as whole words; a plural
    /// or possessive still counts ("Porsches", "LeBron's").
    static func containsName(_ title: String, _ name: String) -> Bool {
        func words(_ s: String) -> [String] {
            s.lowercased().components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "&+")).inverted)
                .filter { !$0.isEmpty }
        }
        let want = words(name)
        guard !want.isEmpty else { return false }
        let have = words(title)
        guard have.count >= want.count else { return false }
        for start in 0...(have.count - want.count) {
            let slice = Array(have[start..<start + want.count])
            let last = slice[slice.count - 1], target = want[want.count - 1]
            if Array(slice.dropLast()) == Array(want.dropLast()),
               last == target || last == target + "s" || last == target + "es" {
                return true
            }
        }
        return false
    }

    /// "a&b" requires every part; otherwise a substring match.
    static func matches(_ text: String, _ pattern: String) -> Bool {
        pattern.split(separator: "&").allSatisfy { text.contains($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// Markets are decided from numbers, never from headlines: stock indexes and funds on the SPY threshold
    /// (a day's move), coins on the BTC threshold (24 h); gold, oil and currencies never.
    static func isMarketShock(instrument: String, change24h: Double?, rules: UrgencyRules) -> Bool {
        guard let change24h, let kind = MarketInstrument.named(instrument.lowercased())?.kind else { return false }
        switch kind {
        case .equity: return abs(change24h) >= rules.spyThreshold
        case .crypto: return abs(change24h) >= rules.btcThreshold
        case .metal, .energy, .fx: return false
        }
    }
}

/// Caps urgent alerts so a busy day does not become noise; overflow goes to the summary.
struct UrgencyBudget: Sendable {
    let perHour: Int
    let perDay: Int
    private(set) var sentAt: [Date] = []

    init(perHour: Int, perDay: Int) {
        self.perHour = perHour
        self.perDay = perDay
    }

    mutating func admit(at now: Date) -> Bool {
        sentAt.removeAll { now.timeIntervalSince($0) > 86_400 }
        let lastHour = sentAt.filter { now.timeIntervalSince($0) <= 3_600 }.count
        guard lastHour < perHour, sentAt.count < perDay else { return false }
        sentAt.append(now)
        return true
    }
}
