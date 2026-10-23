import XCTest
@testable import PulseFeed

/// Integration check of the on-device engine through the exact code path AIGate uses.
/// Skips (does not fail) on machines without Apple's on-device model.
final class OnDeviceEnricherTests: XCTestCase {

    func testOnDeviceEnrichmentReturnsParseableJSON() async throws {
        try XCTSkipUnless(OnDeviceEnricher.isAvailable, "on-device model unavailable: \(OnDeviceEnricher.unavailableReason ?? "unknown")")

        let user = """
            Title: Bitcoin reaches new all-time high of $100,000

            Excerpt: Bitcoin surged past $100,000 for the first time in history as institutional demand accelerated.
            """
        let started = Date()
        let text = try await OnDeviceEnricher().generate(
            system: AIService.enrichmentSystemPrompt(profile: .builtIn, followed: []), user: user, maxTokens: 256)
        let elapsed = Date().timeIntervalSince(started)

        let parsed = AIService.parseEnrichmentJSON(text)
        XCTAssertNotNil(parsed, "model output must parse as enrichment JSON; got: \(text.prefix(300))")
        XCTAssertFalse(parsed?.tldr.isEmpty ?? true)
        XCTAssertTrue(["breaking", "important", "fyi"].contains(parsed?.priority ?? ""))
        XCTAssertLessThan(elapsed, 30, "one enrichment should take about a second, took \(elapsed)s")
        print("on-device enrichment in \(String(format: "%.2f", elapsed))s: \(parsed?.tldr ?? "") topics=\(parsed?.topics ?? [])")
    }
}
