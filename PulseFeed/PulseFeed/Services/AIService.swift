import Foundation
import SwiftAnthropic

struct AIService: Sendable {

    // MARK: - API Key (file-based — Application Support, single source of truth)

    private static var apiKeyFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("PulseFeed")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(".claude-api-key")
    }

    static func setAPIKey(_ key: String) {
        do {
            try key.write(to: apiKeyFileURL, atomically: true, encoding: .utf8)
            print("PulseFeed: [APIKey] saved to \(apiKeyFileURL.path)")
        } catch {
            print("PulseFeed: [APIKey] FAILED to save: \(error)")
        }
    }

    static func getAPIKey() -> String? {
        guard let key = try? String(contentsOf: apiKeyFileURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !key.isEmpty
        else { return nil }
        return key
    }

    static func removeAPIKey() {
        try? FileManager.default.removeItem(at: apiKeyFileURL)
        print("PulseFeed: [APIKey] removed")
    }

    // MARK: - Keyword Scoring (Tier 1: local, free, instant)

    /// Score article relevance based on userInterest keywords. Returns 0-10.
    func keywordRelevance(article: Article, interests: [UserInterest]) -> Double {
        let text = ((article.title ?? "") + " " + (article.contentText ?? "")).lowercased()
        let tokens = Set(text.split(separator: " ").map(String.init))
        var score = 0.0
        for interest in interests {
            let keyword = interest.keyword.lowercased()
            if tokens.contains(keyword) || text.contains(keyword) {
                score += interest.weight
            }
        }
        return min(score, 10.0)
    }

    // MARK: - Enrichment (Tier 2: on-device model or Claude Haiku, via AIGate)

    struct AIEnrichment: Sendable {
        let tldr: String
        let relevance: Double
        let priority: String
        let topics: [String]
    }

    /// The fixed prompt around the profile's two judgements (`AIProfile`); the profile's "{follows}"
    /// slot, when it has one, becomes the reader's followed names.
    static func enrichmentSystemPrompt(profile: AIProfile, followed: [String]) -> String {
        let names = followed.isEmpty ? "no one yet" : followed.joined(separator: ", ")
        let breaking = profile.breakingDefinition.replacingOccurrences(of: AIProfile.followsSlot, with: names)
        let relevance = profile.relevanceFocus.replacingOccurrences(of: AIProfile.followsSlot, with: names)
        return """
            You are a concise news analyst. Given an article title and excerpt, respond with ONLY a JSON object
            with these four keys (describe, do not copy, the placeholders):
            {"tldr": "one sentence, at most 20 words, stating the key news value",
             "relevance": a number from 1 to 10,
             "priority": one of "breaking", "important" or "fyi",
             "topics": an array of two to four short lowercase topic tags taken from this article}

            Priority levels (be strict; most stories are "fyi"):
            - "breaking": \(breaking)
            - "important": significant, worth seeing at the top of the next recap, but nothing changes if it waits
              15 minutes (a star retiring, a big product update, a notable ruling)
            - "fyi": everything else

            Relevance 1-10 scale based on: \(relevance)
            The "tldr" field MUST be 100 words or fewer. Be concise and direct. No markdown, no code fences.
            """
    }

    /// Direct Claude enrichment, bypassing the gate. Used only by the Settings "Test" button.
    func enrichWithClaude(article: Article, apiKey: String) async -> AIEnrichment? {
        let user = "Title: \(article.title ?? "Untitled")\n\nExcerpt: \(String((article.contentText ?? "").prefix(500)))"
        guard let text = try? await ClaudeEnricher(apiKey: apiKey)
            .generate(system: Self.enrichmentSystemPrompt(profile: AIProfile.stored(), followed: UrgencyRules.stored().followedNames), user: user, maxTokens: 256)
        else { return nil }
        return Self.parseEnrichmentJSON(text)
    }

    // MARK: - JSON Parsing

    /// Tolerates code fences and prose around the JSON object.
    static func parseEnrichmentJSON(_ text: String) -> AIEnrichment? {
        let jsonString: String
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end {
            jsonString = String(text[start...end])
        } else {
            jsonString = text
        }
        guard let data = jsonString.data(using: .utf8) else { return nil }

        struct EnrichmentResponse: Codable {
            let tldr: String?
            let relevance: Double?
            let priority: String?
            let topics: [String]?
        }
        guard let parsed = try? JSONDecoder().decode(EnrichmentResponse.self, from: data) else { return nil }

        let validPriorities = Set(["breaking", "important", "fyi"])
        let priority = validPriorities.contains(parsed.priority ?? "") ? parsed.priority! : "fyi"
        return AIEnrichment(
            tldr: parsed.tldr ?? "",
            relevance: min(max(parsed.relevance ?? 0, 0), 10),
            priority: priority,
            topics: parsed.topics ?? [])
    }
}

typealias AIEnrichment = AIService.AIEnrichment

// MARK: - Claude engine

struct ClaudeEnricher: Enricher {
    let apiKey: String
    let name = "claude"
    static let model = "claude-haiku-4-5-20251001"

    func generate(system: String, user: String, maxTokens: Int) async throws -> String {
        // betaHeaders has no default in SwiftAnthropic 2.x — it must be passed explicitly.
        let service = AnthropicServiceFactory.service(apiKey: apiKey, betaHeaders: nil)
        let message = MessageParameter.Message(role: .user, content: .text(user))
        let params = MessageParameter(
            model: .other(Self.model),
            messages: [message],
            maxTokens: maxTokens,
            system: .text(system))
        let response: MessageResponse
        do {
            response = try await service.createMessage(params)
        } catch {
            throw AIEngineError.transport(error.localizedDescription)
        }
        guard let first = response.content.first, case .text(let text, _) = first else {
            throw AIEngineError.transport("empty response")
        }
        return text
    }
}
