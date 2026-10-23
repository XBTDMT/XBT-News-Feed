import Foundation

struct DailyDigest: Sendable {
    let date: String
    let generatedAt: Date
    let summary: String
    let topStories: [DigestStory]
    let marketMood: String?
    /// Short forward-looking items (events, releases, games, races, decisions). Empty for the basic brief.
    let whatToWatch: [String]
    /// True when the model was unavailable and this brief was assembled from raw headlines.
    let isFallback: Bool
}

struct DigestStory: Sendable, Identifiable {
    let id: String
    let headline: String
    let oneLiner: String
    let category: String
}

actor DigestService {
    private var cachedDigest: DailyDigest?
    private var lastGeneratedDate: String?
    /// Generation already running; concurrent callers join it instead of issuing a second model call.
    private var inFlight: Task<DailyDigest?, Never>?

    /// A successful AI brief is reused for this long (also invalidated when the calendar day changes).
    private static let successTTL: TimeInterval = 6 * 60 * 60
    /// A basic (fallback) brief is reused only briefly so a transient AI failure does not poison the day.
    private static let fallbackTTL: TimeInterval = 30 * 60
    private static let inputHours = 24
    private static let inputLimit = 40
    private static let headlinesSentToModel = 30
    private static let fallbackStoryLimit = 12

    func getOrGenerateDigest(appDB: AppDatabase, forceRefresh: Bool = false) async -> DailyDigest? {
        let today = Self.todayString()

        if !forceRefresh, let cached = cachedDigest, lastGeneratedDate == today,
           Self.isFresh(cached, now: Date()) {
            return cached
        }

        if let inFlight {
            return await inFlight.value
        }

        let task = Task { await self.generate(appDB: appDB, date: today) }
        inFlight = task
        let result = await task.value
        inFlight = nil
        return result
    }

    private func generate(appDB: AppDatabase, date: String) async -> DailyDigest? {
        guard let articles = try? await appDB.fetchRecentArticleInfos(hours: Self.inputHours, limit: Self.inputLimit),
              !articles.isEmpty
        else {
            return cachedDigest
        }

        if let digest = await generateAIDigest(articles: articles, date: date) {
            cachedDigest = digest
            lastGeneratedDate = date
            return digest
        }

        let fallback = generateBasicDigest(articles: articles, date: date)
        cachedDigest = fallback
        lastGeneratedDate = date
        return fallback
    }

    private static func isFresh(_ digest: DailyDigest, now: Date) -> Bool {
        let age = now.timeIntervalSince(digest.generatedAt)
        return age < (digest.isFallback ? fallbackTTL : successTTL)
    }

    // MARK: - AI brief

    private func generateAIDigest(articles: [ArticleInfo], date: String) async -> DailyDigest? {
        let headlines = articles.prefix(Self.headlinesSentToModel)
            .map(Self.formatHeadline)
            .joined(separator: "\n")
        let categories = Self.orderedCategories(in: articles).joined(separator: ", ")

        let systemPrompt = """
            You are a news briefing writer. Given the last 24 hours of headlines from a reader's personal feeds, write their daily brief.
            Respond with EXACTLY this JSON and nothing else — no markdown, no code fences, no commentary:
            {"summary": "6-8 sentence overview grouped by theme",
             "topStories": [{"headline": "...", "oneLiner": "...", "category": "..."}],
             "marketMood": "one short phrase",
             "whatToWatch": ["3-5 short items: upcoming events, scheduled releases, games, races, decisions"]}
            Rules:
            - topStories: 10 to 12 entries, ordered by importance. Together they MUST cover EVERY category listed under "Categories present". Favour stories marked "(covered by N sources)" — more sources means more important.
            - headline: short and factual, close to the input headline so it can be matched back. oneLiner: one sentence. category: exactly one of the input category labels, lowercase.
            - summary: 6-8 sentences grouped by theme (markets and crypto, tech, world, sport), not a list.
            - marketMood: one short phrase describing market sentiment from the finance and crypto items.
            - whatToWatch: 3-5 short items about what comes next (upcoming events, scheduled releases, games, races, decisions), drawn from the input. Use [] if nothing qualifies.
            - Be concise and factual. Do not invent facts or events that are not supported by the input.
            """

        let userContent = """
            Categories present: \(categories)

            Headlines (\(min(articles.count, Self.headlinesSentToModel)) of \(articles.count) from the last 24 hours):
            \(headlines)
            """

        // On-device first when it is available: the brief lands in seconds instead of ~30 s.
        // If its answer does not parse, one more try with the other engine before the basic brief.
        let onDeviceFirst = OnDeviceEnricher.isAvailable && AIGate.prefersOnDevice()
        for (attempt, preferOnDevice) in [onDeviceFirst, !onDeviceFirst].enumerated() {
            guard let text = await AIGate.shared.generateText(
                system: systemPrompt,
                user: userContent,
                maxTokens: 2000,
                kind: "digest",
                preferOnDevice: preferOnDevice)
            else {
                print("PulseFeed: [Digest] Model unavailable or gated; using basic brief")
                return nil
            }
            if let digest = parseDigestJSON(text, articles: articles, date: date) { return digest }
            print("PulseFeed: [Digest] Could not parse model response (attempt \(attempt + 1), onDevice=\(preferOnDevice))")
        }
        print("PulseFeed: [Digest] Using basic brief")
        return nil
    }

    /// `[category] Title — first 120 chars of summary/content (covered by N sources)`
    private static func formatHeadline(_ article: ArticleInfo) -> String {
        let title = Self.collapseWhitespace(article.title ?? "Untitled")
        let snippet = String(Self.bodyText(for: article).prefix(120)).trimmingCharacters(in: .whitespaces)
        var line = "[\(article.feedCategory)] \(title)"
        if !snippet.isEmpty {
            line += " — \(snippet)"
        }
        if article.sourceCount > 1 {
            line += " (covered by \(article.sourceCount) sources)"
        }
        return line
    }

    /// First non-empty of summary / contentText, whitespace collapsed to single spaces.
    private static func bodyText(for article: ArticleInfo) -> String {
        for candidate in [article.summary, article.contentText] {
            if let candidate {
                let collapsed = Self.collapseWhitespace(candidate)
                if !collapsed.isEmpty { return collapsed }
            }
        }
        return ""
    }

    private static func collapseWhitespace(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    /// Distinct categories in first-seen order.
    private static func orderedCategories(in articles: [ArticleInfo]) -> [String] {
        var seen = Set<String>()
        return articles.compactMap { seen.insert($0.feedCategory).inserted ? $0.feedCategory : nil }
    }

    // MARK: - Parsing

    private func parseDigestJSON(_ text: String, articles: [ArticleInfo], date: String) -> DailyDigest? {
        let jsonString = Self.extractJSONObject(from: text)

        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let summaryText = (json["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !summaryText.isEmpty
        else { return nil }

        let storiesArray = json["topStories"] as? [[String: Any]] ?? []
        let mood = (json["marketMood"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let whatToWatch = (json["whatToWatch"] as? [Any] ?? [])
            .compactMap { $0 as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var usedIDs = Set<String>()
        let stories = storiesArray.enumerated().compactMap { index, dict -> DigestStory? in
            guard let headline = (dict["headline"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !headline.isEmpty
            else { return nil }
            let oneLiner = (dict["oneLiner"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let matched = Self.matchArticle(for: headline, in: articles)
            let category = (dict["category"] as? String)?.lowercased() ?? matched?.feedCategory ?? "general"

            // Keep IDs unique so SwiftUI's ForEach never sees two rows with the same identity.
            var id = matched?.articleID ?? "digest-\(index)"
            if !usedIDs.insert(id).inserted {
                id = "digest-\(index)"
                usedIDs.insert(id)
            }
            return DigestStory(id: id, headline: headline, oneLiner: oneLiner, category: category)
        }

        return DailyDigest(
            date: date,
            generatedAt: Date(),
            summary: summaryText,
            topStories: stories,
            marketMood: (mood?.isEmpty == false) ? mood : nil,
            whatToWatch: whatToWatch,
            isFallback: false
        )
    }

    /// Strips markdown code fences, then returns the span from the first `{` to the last `}`.
    private static func extractJSONObject(from text: String) -> String {
        var cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```JSON", with: "")
            .replacingOccurrences(of: "```", with: "")
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = cleaned.firstIndex(of: "{"),
           let end = cleaned.lastIndex(of: "}"),
           start < end {
            return String(cleaned[start...end])
        }
        return cleaned
    }

    /// Maps a model-written headline back to a source article for tap-through.
    /// Pass 1: the original prefix-20 containment check. Pass 2: significant-word overlap.
    private static func matchArticle(for headline: String, in articles: [ArticleInfo]) -> ArticleInfo? {
        let needle = String(headline.prefix(20))
        if let direct = articles.first(where: { ($0.title ?? "").localizedCaseInsensitiveContains(needle) }) {
            return direct
        }

        let headlineWords = significantWords(headline)
        guard headlineWords.count >= 2 else { return nil }

        var best: (article: ArticleInfo, score: Double)?
        for article in articles {
            let titleWords = significantWords(article.title ?? "")
            guard !titleWords.isEmpty else { continue }
            let overlap = Double(headlineWords.intersection(titleWords).count)
            let score = overlap / Double(min(headlineWords.count, titleWords.count))
            if score > (best?.score ?? 0) {
                best = (article, score)
            }
        }
        if let best, best.score >= 0.5 {
            return best.article
        }
        return nil
    }

    private static let stopWords: Set<String> = [
        "the", "and", "for", "with", "from", "that", "this", "into", "over", "after",
        "amid", "says", "said", "will", "has", "have", "its", "are", "was", "were", "not",
        "new", "how", "why", "what", "who", "you", "your", "about", "just", "than", "more",
    ]

    private static func significantWords(_ text: String) -> Set<String> {
        Set(
            text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 && !stopWords.contains($0) }
        )
    }

    // MARK: - Basic (fallback) brief

    private func generateBasicDigest(articles: [ArticleInfo], date: String) -> DailyDigest {
        // Multi-source stories first; `sort` is stable so feed order is otherwise preserved.
        let ranked = articles.sorted { $0.sourceCount > $1.sourceCount }
        let stories = ranked.prefix(Self.fallbackStoryLimit).map { article in
            DigestStory(
                id: article.articleID,
                headline: article.title ?? "Untitled",
                oneLiner: String(Self.bodyText(for: article).prefix(100)),
                category: article.feedCategory
            )
        }

        let categoryCount = Set(articles.map(\.feedCategory)).count
        let summary = "\(articles.count) stories across \(categoryCount) categories in the last 24 hours."

        return DailyDigest(
            date: date,
            generatedAt: Date(),
            summary: summary,
            topStories: Array(stories),
            marketMood: nil,
            whatToWatch: [],
            isFallback: true
        )
    }

    private static func todayString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
