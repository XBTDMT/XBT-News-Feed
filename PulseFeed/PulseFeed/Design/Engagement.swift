import Foundation

/// The learning week (2026-09-07): for seven days the app only WATCHES — what it showed,
/// what was opened, how long the reader stayed open, what was starred, saved or waved away with
/// "not interested" — all in a local table. Nothing about ranking or sources changes during the
/// week. At the end, the numbers become proposals under rules written down before the first event
/// (`EngagementReport.Rules.preregistered`), and each proposal waits for an explicit accept.

enum EngagementEvent: String, Sendable, CaseIterable {
    case shown, opened, dwell, starred, saved, dismissed
}

/// One logged event joined to its story's feed and category (the report's input).
struct EngagementRow: Sendable, Equatable {
    var at: String
    var event: String
    var articleID: String
    var feedID: String
    var feedTitle: String
    var category: String
    var topics: String?
    var value: Double?
}

/// A row is "shown" once per app run, however often it scrolls past.
struct ImpressionDedupe: Sendable {
    private var seen = Set<String>()
    mutating func firstTime(_ articleID: String) -> Bool { seen.insert(articleID).inserted }
}

/// The seven-day clock. It starts the first time the app asks for it after this build is installed.
struct EngagementStudy: Sendable {
    static let startedKey = "engagement_study_started_at"
    static let length: TimeInterval = 7 * 86400

    let startedAt: Date
    var endsAt: Date { startedAt.addingTimeInterval(Self.length) }

    func progress(now: Date = Date()) -> (day: Int, ready: Bool) {
        let elapsed = now.timeIntervalSince(startedAt)
        let day = max(1, min(7, Int(elapsed / 86400) + 1))
        return (day, elapsed >= Self.length)
    }

    /// Off for a new install (spec D11); on where a week already started (the owner's install, 2026-09-07) unless switched off.
    static let enabledKey = "engagement_study_enabled"

    static func isEnabled(_ d: UserDefaults) -> Bool {
        d.object(forKey: enabledKey) as? Bool ?? (d.object(forKey: startedKey) != nil)
    }

    /// On starts the clock now unless a week already started (turning it back on keeps that week); off keeps
    /// the recorded rows and the clock and stops recording.
    static func setEnabled(_ on: Bool, _ d: UserDefaults, now: Date = Date()) {
        d.set(on, forKey: enabledKey)
        if on, d.object(forKey: startedKey) == nil { d.set(now, forKey: startedKey) }
    }

    static func current(_ defaults: UserDefaults = .standard, now: Date = Date()) -> EngagementStudy {
        if let started = defaults.object(forKey: startedKey) as? Date { return EngagementStudy(startedAt: started) }
        defaults.set(now, forKey: startedKey)
        return EngagementStudy(startedAt: now)
    }
}

/// Counts, then proposals. Pure: give it the rows and the current category state.
struct EngagementReport: Sendable {
    /// Written down before the week started. A source is proposed for disabling when it was shown
    /// at least `minImpressions` times and opened (or starred/saved) at most `lowOpenRate` of them,
    /// or when it collected `minDismissals` "not interested" and no open at all. A category that is
    /// off is proposed for enabling when at least `minTopicOpens` opened stories carry its topic.
    struct Rules: Sendable {
        var minImpressions = 50
        var lowOpenRate = 0.02
        var minDismissals = 5
        var minTopicOpens = 5
        static let preregistered = Rules()
    }

    struct Totals: Sendable, Equatable { var shown = 0, opened = 0, starred = 0, saved = 0, dismissed = 0, dwellSeconds = 0.0 }

    struct SourceStat: Sendable, Identifiable {
        var feedID: String, title: String, category: String
        var shown = 0, opens = 0, dismissed = 0, dwellSeconds = 0.0
        var id: String { feedID }
        var rate: Double { shown == 0 ? 0 : Double(opens) / Double(shown) }
    }

    struct CategoryStat: Sendable, Identifiable {
        var category: String
        var shown = 0, opens = 0
        var id: String { category }
        var rate: Double { shown == 0 ? 0 : Double(opens) / Double(shown) }
    }

    struct TopicStat: Sendable, Identifiable {
        var topic: String
        var opens = 0, dismissals = 0
        var id: String { topic }
    }

    struct Proposal: Sendable, Identifiable, Equatable {
        enum Kind: Sendable, Equatable { case disableSource(feedID: String), enableCategory(String) }
        var id: String
        var kind: Kind
        var title: String
        var evidence: String
    }

    var totals = Totals()
    var sources: [SourceStat] = []
    var categories: [CategoryStat] = []
    var topics: [TopicStat] = []
    var proposals: [Proposal] = []

    static func build(events: [EngagementRow], enabledCategories: Set<String>, categoriesOff: [String],
                      rules: Rules = .preregistered) -> EngagementReport {
        var report = EngagementReport()
        var sources: [String: SourceStat] = [:]
        var categories: [String: CategoryStat] = [:]
        var topics: [String: TopicStat] = [:]

        for row in events {
            var s = sources[row.feedID] ?? SourceStat(feedID: row.feedID, title: row.feedTitle, category: row.category)
            var c = categories[row.category] ?? CategoryStat(category: row.category)
            let tags = (row.topics ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
            switch EngagementEvent(rawValue: row.event) {
            case .shown:
                report.totals.shown += 1; s.shown += 1; c.shown += 1
            case .opened, .starred, .saved:
                if row.event == "opened" { report.totals.opened += 1 }
                if row.event == "starred" { report.totals.starred += 1 }
                if row.event == "saved" { report.totals.saved += 1 }
                s.opens += 1; c.opens += 1
                for t in tags { topics[t, default: TopicStat(topic: t)].opens += 1 }
            case .dismissed:
                report.totals.dismissed += 1; s.dismissed += 1
                for t in tags { topics[t, default: TopicStat(topic: t)].dismissals += 1 }
            case .dwell:
                let seconds = row.value ?? 0
                report.totals.dwellSeconds += seconds; s.dwellSeconds += seconds
            case nil:
                break
            }
            sources[row.feedID] = s
            categories[row.category] = c
        }

        report.sources = sources.values.sorted { ($0.shown, $0.title) > ($1.shown, $1.title) }
        report.categories = categories.values.sorted { $0.shown > $1.shown }
        report.topics = topics.values.sorted { ($0.opens + $0.dismissals, $0.topic) > ($1.opens + $1.dismissals, $1.topic) }

        for s in report.sources {
            let quiet = s.shown >= rules.minImpressions && s.rate <= rules.lowOpenRate
            let refused = s.dismissed >= rules.minDismissals && s.opens == 0
            guard quiet || refused else { continue }
            let evidence = refused && !quiet
                ? "Not interested \(s.dismissed) times, never opened"
                : "Opened \(s.opens) of \(s.shown) shown" + (s.dismissed > 0 ? ", not interested \(s.dismissed) times" : "")
            report.proposals.append(Proposal(id: "disable-source:\(s.feedID)", kind: .disableSource(feedID: s.feedID),
                                             title: "Turn off \(s.title)", evidence: evidence))
        }
        for id in categoriesOff {
            let names = [id.lowercased(), NewsCategory.named(id).label.lowercased()]
            let opens = report.topics.filter { names.contains($0.topic) }.map(\.opens).reduce(0, +)
            guard opens >= rules.minTopicOpens else { continue }
            report.proposals.append(Proposal(id: "enable-category:\(id)", kind: .enableCategory(id),
                                             title: "Turn on \(NewsCategory.named(id).label)",
                                             evidence: "You opened \(opens) stories about it from other categories"))
        }
        return report
    }
}

/// The recorder. Events are buffered and written a few seconds later, so scrolling costs nothing.
@MainActor
final class EngagementLog {
    static let shared = EngagementLog()

    private var appDB: AppDatabase?
    private var dedupe = ImpressionDedupe()
    private var buffer: [(event: EngagementEvent, articleID: String, value: Double?)] = []
    private var flushTask: Task<Void, Never>?

    func attach(_ db: AppDatabase) {
        appDB = db
    }

    func shown(_ articleID: String) {
        guard dedupe.firstTime(articleID) else { return }
        enqueue(.shown, articleID, nil)
    }
    func opened(_ articleID: String) { enqueue(.opened, articleID, nil) }
    func dwell(_ articleID: String, seconds: Double) {
        guard seconds >= 3 else { return }   // a glance is not reading
        enqueue(.dwell, articleID, seconds.rounded())
    }
    func dismissed(_ articleID: String) { enqueue(.dismissed, articleID, nil) }

    private func enqueue(_ event: EngagementEvent, _ articleID: String, _ value: Double?) {
        guard EngagementStudy.isEnabled(.standard) else { return }   // nothing is recorded while the week is off
        buffer.append((event, articleID, value))
        if buffer.count >= 25 { flush() } else if flushTask == nil {
            flushTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                self?.flush()
            }
        }
    }

    func flush() {
        flushTask?.cancel()
        flushTask = nil
        guard let appDB, !buffer.isEmpty else { return }
        let rows = buffer
        buffer = []
        Task { try? await appDB.logEngagement(rows) }
    }
}
