import Foundation

// MARK: - Budget (pure, unit tested)

/// Daily call cap that rolls over by calendar day, plus an exponential cooldown after failures.
struct AIBudget: Sendable, Equatable {
    var day: String = ""
    var callsUsed: Int = 0
    var cooldownUntil: Date? = nil
    var consecutiveFailures: Int = 0

    static let baseCooldown: TimeInterval = 30
    static let maxCooldown: TimeInterval = 1800

    /// Admits one call and counts it, or refuses. Refusals never consume budget.
    mutating func admit(now: Date, today: String, dailyCap: Int) -> Bool {
        if day != today {
            day = today
            callsUsed = 0
        }
        if let until = cooldownUntil, now < until { return false }
        if callsUsed >= dailyCap { return false }
        callsUsed += 1
        return true
    }

    mutating func recordFailure(now: Date) {
        consecutiveFailures += 1
        let delay = min(Self.baseCooldown * pow(2, Double(consecutiveFailures - 1)), Self.maxCooldown)
        cooldownUntil = now.addingTimeInterval(delay)
    }

    mutating func recordSuccess() {
        consecutiveFailures = 0
        cooldownUntil = nil
    }
}

// MARK: - Engines

enum AIEngineError: Error, Sendable {
    case unavailable
    case transport(String)
}

/// One text model. Both engines produce raw text; the gate parses.
protocol Enricher: Sendable {
    var name: String { get }
    func generate(system: String, user: String, maxTokens: Int) async throws -> String
}

struct AIGateStatus: Sendable {
    let enabled: Bool
    let engine: String
    let onDeviceAvailable: Bool
    let hasClaudeKey: Bool
    let callsToday: Int
    let dailyCap: Int
    let cooldownUntil: Date?
    let tier: PowerTier
}

// MARK: - Gate

/// The single front door for every model call. Enforces the AI toggle, the power tier, a daily
/// call cap, exponential cooldown after transport failures, and per-article in-flight dedup.
actor AIGate {
    static let shared = AIGate()

    static let dailyCap = PulseFeedConstants.aiDailyCap
    private static let budgetDayKey = "ai_budget_day"
    private static let budgetCallsKey = "ai_budget_calls"

    private var budget: AIBudget
    private var inFlight: [String: Task<AIEnrichment?, Never>] = [:]
    private var lastClaudeCall = Date.distantPast

    init() {
        let d = UserDefaults.standard
        budget = AIBudget(
            day: d.string(forKey: Self.budgetDayKey) ?? "",
            callsUsed: d.integer(forKey: Self.budgetCallsKey))
    }

    // MARK: Preferences

    /// The "Enable AI" toggle. `bool(forKey:)` would read false when never written, while the
    /// settings switch defaults to true; this reads the same default the UI shows.
    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: "ai_enabled") as? Bool ?? true
    }

    static func prefersOnDevice(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: "ai_prefer_on_device") as? Bool ?? true
    }

    // MARK: Public API

    /// Enrich one article for the background pipeline (no DB write; the engine batches those).
    func enrich(article: Article, userInitiated: Bool) async -> AIEnrichment? {
        if let existing = inFlight[article.articleID] {
            return await existing.value
        }
        let task = Task<AIEnrichment?, Never> { [self] in
            await self.performEnrich(article: article, userInitiated: userInitiated)
        }
        inFlight[article.articleID] = task
        let result = await task.value
        inFlight[article.articleID] = nil
        return result
    }

    /// Enrich one article on demand (a click), store the result, return the summary.
    func enrichAndStore(articleID: String, appDB: AppDatabase, userInitiated: Bool) async -> String? {
        guard let article = try? await appDB.fetchArticles(ids: [articleID]).first else { return nil }
        if let existing = article.summary, !existing.isEmpty { return existing }
        guard let enrichment = await enrich(article: article, userInitiated: userInitiated) else { return nil }
        try? await appDB.updateAIEnrichment(
            articleID: articleID,
            summary: enrichment.tldr,
            relevanceScore: enrichment.relevance,
            priority: enrichment.priority,
            topics: enrichment.topics.joined(separator: ","))
        return enrichment.tldr
    }

    /// Text generation for non-article uses (the daily brief). Claude first when a key exists,
    /// on-device otherwise; `preferOnDevice` flips the order.
    func generateText(system: String, user: String, maxTokens: Int, kind: String, preferOnDevice: Bool, onDeviceOnly: Bool = false) async -> String? {
        guard Self.isEnabled() else { return nil }
        let tier = await currentTier()
        guard tier != .critical else {
            print("PulseFeed: [AI] \(kind): skipped (critical battery)")
            return nil
        }
        for engine in engines(preferOnDevice: preferOnDevice, onDeviceOnly: onDeviceOnly) {
            guard admit() else {
                print("PulseFeed: [AI] \(kind): refused (cap or cooldown)")
                return nil
            }
            do {
                let text = try await call(engine) { try await engine.generate(system: system, user: user, maxTokens: maxTokens) }
                budget.recordSuccess()
                print("PulseFeed: [AI] \(kind): \(engine.name) ok (\(text.count) chars)")
                return text
            } catch {
                noteFailure(engine: engine, error: error, kind: kind)
            }
        }
        return nil
    }

    func status() async -> AIGateStatus {
        let tier = await currentTier()
        let engines = engines(preferOnDevice: Self.prefersOnDevice())
        return AIGateStatus(
            enabled: Self.isEnabled(),
            engine: engines.first?.name ?? "none",
            onDeviceAvailable: OnDeviceEnricher.isAvailable,
            hasClaudeKey: AIService.getAPIKey() != nil,
            callsToday: budget.day == Self.today() ? budget.callsUsed : 0,
            dailyCap: Self.dailyCap,
            cooldownUntil: budget.cooldownUntil.flatMap { $0 > Date() ? $0 : nil },
            tier: tier)
    }

    // MARK: Internals

    private func performEnrich(article: Article, userInitiated: Bool) async -> AIEnrichment? {
        guard Self.isEnabled() else { return nil }
        let tier = await currentTier()
        if tier == .critical { return nil }
        let engines = engines(preferOnDevice: Self.prefersOnDevice())
        guard !engines.isEmpty else { return nil }

        let user = "Title: \(article.title ?? "Untitled")\n\nExcerpt: \(String((article.contentText ?? "").prefix(500)))"
        for engine in engines {
            guard admit() else { return nil }
            do {
                let started = Date()
                let text = try await call(engine) {
                    try await engine.generate(system: AIService.enrichmentSystemPrompt(profile: AIProfile.stored(), followed: UrgencyRules.stored().followedNames), user: user, maxTokens: 256)
                }
                budget.recordSuccess()
                if let parsed = AIService.parseEnrichmentJSON(text) {
                    print("PulseFeed: [AI] enrich: \(engine.name) ok in \(String(format: "%.1f", Date().timeIntervalSince(started)))s (\(article.articleID.prefix(8)))")
                    return parsed
                }
                print("PulseFeed: [AI] \(engine.name) returned unparseable enrichment for \(article.articleID.prefix(8))")
                // Parse failure is not a transport failure; try the next engine without cooldown.
            } catch {
                noteFailure(engine: engine, error: error, kind: "enrich")
            }
        }
        return nil
    }

    /// The engine names a call may use, in order. `onDeviceOnly` is for text that must not leave the Mac.
    static func engineOrder(preferOnDevice: Bool, onDeviceOnly: Bool, onDeviceAvailable: Bool, claudeAvailable: Bool) -> [String] {
        let onDevice = onDeviceAvailable ? ["on-device"] : []
        if onDeviceOnly { return onDevice }
        let claude = claudeAvailable ? ["claude"] : []
        return preferOnDevice ? onDevice + claude : claude + onDevice
    }

    /// Ordered engine list honouring availability and the user's preference.
    private func engines(preferOnDevice: Bool, onDeviceOnly: Bool = false) -> [Enricher] {
        let key = AIService.getAPIKey()
        return Self.engineOrder(preferOnDevice: preferOnDevice, onDeviceOnly: onDeviceOnly,
                                onDeviceAvailable: OnDeviceEnricher.isAvailable, claudeAvailable: key != nil)
            .compactMap { name -> Enricher? in
                name == "on-device" ? OnDeviceEnricher() : key.map { ClaudeEnricher(apiKey: $0) }
            }
    }

    private func admit() -> Bool {
        let ok = budget.admit(now: Date(), today: Self.today(), dailyCap: Self.dailyCap)
        if ok {
            let d = UserDefaults.standard
            d.set(budget.day, forKey: Self.budgetDayKey)
            d.set(budget.callsUsed, forKey: Self.budgetCallsKey)
        }
        return ok
    }

    /// Paces Claude calls to at most one per second; on-device calls run back to back.
    private func call<T: Sendable>(_ engine: Enricher, _ body: @Sendable () async throws -> T) async throws -> T {
        if engine is ClaudeEnricher {
            let since = Date().timeIntervalSince(lastClaudeCall)
            if since < 1.0 { try? await Task.sleep(for: .seconds(1.0 - since)) }
            lastClaudeCall = Date()
        }
        return try await body()
    }

    private func noteFailure(engine: Enricher, error: Error, kind: String) {
        budget.recordFailure(now: Date())
        let until = budget.cooldownUntil.map { Int($0.timeIntervalSinceNow) } ?? 0
        print("PulseFeed: [AI] \(kind): \(engine.name) failed (\(error)); cooling down \(until)s")
    }

    private func currentTier() async -> PowerTier {
        await MainActor.run { PowerMonitor.shared.tier }
    }

    private static func today() -> String {
        String(Date().sqliteString.prefix(10))
    }
}
