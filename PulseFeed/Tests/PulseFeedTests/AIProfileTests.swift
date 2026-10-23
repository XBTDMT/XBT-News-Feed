import XCTest
@testable import PulseFeed

/// The enrichment prompt is a fixed template around an `AIProfile`: what counts as breaking news and
/// what relevance is scored on. The built-in profile must reproduce the prompt as it stood on
/// 2026-10-22, word for word, so an existing install keeps asking its model the same question.
final class AIProfileTests: XCTestCase {

    /// The prompt as committed at 9a5fb5e (AIService.swift), copied verbatim.
    static let promptAt20261022 = """
        You are a concise news analyst. Given an article title and excerpt, respond with ONLY a JSON object
        with these four keys (describe, do not copy, the placeholders):
        {"tldr": "one sentence, at most 20 words, stating the key news value",
         "relevance": a number from 1 to 10,
         "priority": one of "breaking", "important" or "fyi",
         "topics": an array of two to four short lowercase topic tags taken from this article}

        Priority levels (be strict; most stories are "fyi"):
        - "breaking": a major, singular event an informed person would want to hear about RIGHT NOW — a war
          breaking out or a ceasefire, a coup or an assassination, a market index or major asset moving more
          than 2–3% in a day or setting a record, an exchange hack or insolvency, a frontier AI model launch
          (GPT, Claude, Gemini), a marquee trade or signing in the NBA or a top F1 driver changing teams, a
          major artist announcing a tour, a major death. Not routine results, previews, rumours or opinion.
        - "important": significant, worth seeing at the top of the next recap, but nothing changes if it waits
          15 minutes (a star retiring, a big product update, a notable ruling)
        - "fyi": everything else

        Relevance 1-10 scale based on: impact on crypto/finance markets, AI/tech significance, sports relevance to NBA/F1.
        The "tldr" field MUST be 100 words or fewer. Be concise and direct. No markdown, no code fences.
        """

    /// The profile as stored on 2026-10-22 (it names one person's interests, so the public copy leaves
    /// it out and this test skips there).
    private func storedProfileAt20261022() throws -> AIProfile {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ai-profile-2026-10-22.txt")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { throw XCTSkip("private fixture not present") }
        return try XCTUnwrap(AIProfile.parse(text))
    }

    /// An install whose profile was frozen on 2026-10-22 asks its model exactly what it asked that day,
    /// whatever it follows: that text has no {follows} slot.
    func testFrozenProfileReproducesTodaysPromptByteForByte() throws {
        let frozen = try storedProfileAt20261022()
        XCTAssertEqual(AIService.enrichmentSystemPrompt(profile: frozen, followed: []), Self.promptAt20261022)
        XCTAssertEqual(AIService.enrichmentSystemPrompt(profile: frozen, followed: ["celtics", "mclaren"]), Self.promptAt20261022)
    }

    func testBuiltInProfileIsNeutral() {
        let text = AIProfile.builtIn.asText.lowercased()
        for word in ["nba", "f1", "lakers", "tour", "gpt", "claude", "crypto"] {
            XCTAssertFalse(text.contains(word), word)
        }
        XCTAssertTrue(text.contains("war"))
        XCTAssertTrue(text.contains("ceasefire"))
    }

    func testFollowedNamesFillTheBuiltInSlot() {
        let prompt = AIService.enrichmentSystemPrompt(profile: .builtIn, followed: ["arsenal", "nvidia"])
        XCTAssertTrue(prompt.contains("arsenal, nvidia"))
        XCTAssertFalse(prompt.contains("{follows}"))
    }

    func testNoFollowedSaysSo() {
        let prompt = AIService.enrichmentSystemPrompt(profile: .builtIn, followed: [])
        XCTAssertTrue(prompt.contains("no one yet"))
        XCTAssertFalse(prompt.contains("{follows}"))
    }

    func testProfileTextRoundTrips() {
        XCTAssertEqual(AIProfile.parse(AIProfile.builtIn.asText), .builtIn)
    }

    func testUnparseableTextIsNil() {
        XCTAssertNil(AIProfile.parse(""))
        XCTAssertNil(AIProfile.parse("no sections here"))
    }

    func testScopedFollowsReachThePromptAsPlainNames() {
        var r = UrgencyRules.defaults
        r.followed = ["sports: heat", "nvidia"]
        let prompt = AIService.enrichmentSystemPrompt(profile: .builtIn, followed: r.followedNames)
        XCTAssertTrue(prompt.contains("heat, nvidia"))
        XCTAssertFalse(prompt.contains("sports: heat"))
    }
}
