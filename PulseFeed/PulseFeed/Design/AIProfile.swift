import Foundation

/// What the enrichment prompt asks the model to judge by: which stories count as breaking news, and
/// what relevance is scored on. The rest of the prompt (the JSON shape, the other priority levels) is
/// fixed in `AIService.enrichmentSystemPrompt(profile:)`. Stored as text under `ai_profile_text`, so an
/// install keeps its own wording when the built-in one changes (`SettingsFreeze`).
struct AIProfile: Sendable, Equatable {
    var breakingDefinition: String
    var relevanceFocus: String

    static let defaultsKey = "ai_profile_text"

    /// A new user's profile. "{follows}" becomes the names the reader follows. An install in use keeps
    /// its own stored text (`SettingsFreeze`); a text without the slot is used as written.
    static let builtIn = AIProfile(
        breakingDefinition: """
            a major, singular event an informed person would want to hear about RIGHT NOW — a war
              breaking out or a ceasefire, a coup or an assassination, a major disaster, a market index or major
              asset moving more than 2–3% in a day or setting a record, a major death, or a major turn for
              someone or something the reader follows ({follows}). Not routine results, previews, rumours or opinion.
            """,
        relevanceFocus: """
            how much it matters to the people, teams, companies and subjects the reader follows ({follows}), and its significance for an informed general reader.
            """)

    static let followsSlot = "{follows}"

    private static let breakingHeader = "# Breaking — what counts as breaking news"
    private static let relevanceHeader = "# Relevance — what relevance 1-10 is scored on"

    var asText: String {
        "\(Self.breakingHeader)\n\(breakingDefinition)\n\n\(Self.relevanceHeader)\n\(relevanceFocus)"
    }

    /// Lines are kept as written (continuation indentation included); nil unless both sections are present.
    static func parse(_ text: String) -> AIProfile? {
        var sections: [String: [String]] = [:]
        var current: String?
        for line in text.components(separatedBy: "\n") {
            if line == breakingHeader || line == relevanceHeader {
                current = line
                sections[line] = []
            } else if let current {
                sections[current, default: []].append(line)
            }
        }
        func body(_ header: String) -> String? {
            guard var lines = sections[header] else { return nil }
            while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
            let joined = lines.joined(separator: "\n")
            return joined.isEmpty ? nil : joined
        }
        guard let breaking = body(breakingHeader), let relevance = body(relevanceHeader) else { return nil }
        return AIProfile(breakingDefinition: breaking, relevanceFocus: relevance)
    }

    static func stored(_ d: UserDefaults = .standard) -> AIProfile {
        d.string(forKey: defaultsKey).flatMap(parse) ?? builtIn
    }
}
