import Foundation

struct SummaryText: Sendable, Equatable {
    let title: String
    /// The always-visible middle line of the banner: the lead headlines themselves. The title only
    /// ever says how many stories there are, so without this the collapsed banner names none of them.
    var subtitle: String = ""
    let body: String
}

/// The 15-minute "what's new" notification. Headlines lead; nothing new means nothing sent.
enum SummaryComposer {
    static let intervalKey = "summary_interval"        // seconds; 0 = off
    static let lastSentKey = "summary_last_sent_at"
    static let lastIDsKey = "summary_last_ids"
    static func saveLastIDs(_ ids: [String], in d: UserDefaults = .standard) { d.set(ids, forKey: lastIDsKey) }
    static func loadLastIDs(in d: UserDefaults = .standard) -> [String] { d.stringArray(forKey: lastIDsKey) ?? [] }
    static let lastTextKey = "summary_last_text"
    static let lastSubtitleKey = "summary_last_subtitle"
    static let defaultInterval: TimeInterval = 900

    static func isDue(lastSentAt: Date?, now: Date, interval: TimeInterval) -> Bool {
        guard interval > 0 else { return false }
        guard let lastSentAt else { return true }
        return now.timeIntervalSince(lastSentAt) > interval
    }

    /// The no-model summary (critical battery, or the model unavailable): headlines, then the top three.
    static func plainSummary(headlines: [String], others: [String]) -> SummaryText? {
        let total = headlines.count + others.count
        guard total > 0 else { return nil }
        var lines = headlines
        lines.append(contentsOf: others.prefix(3))
        return SummaryText(
            title: title(count: total),
            subtitle: subtitle(headlines: headlines, others: others),
            body: lines.joined(separator: "\n"))
    }

    static func title(count: Int) -> String {
        "What's new · \(count) \(count == 1 ? "story" : "stories")"
    }

    /// The banner's second line. The title is a count and the body is prose that macOS cuts after
    /// about two lines, so this is where the actual headlines go — the one line guaranteed to be
    /// read at a glance.
    static func subtitle(headlines: [String], others: [String]) -> String {
        NotificationText.leadLine(headlines: headlines, others: others)
    }

    /// Prompt for the on-device model. JSON out, because the on-device model follows a JSON shape far
    /// better than free text (it echoed "HEADLINE:" markers back when asked for prose). No marker in
    /// the input that it could copy: leads are listed under their own heading.
    static func prompt(headlines: [String], others: [String]) -> (system: String, user: String) {
        let system = """
            You write a short news recap for one reader, delivered as a macOS notification.
            Respond with EXACTLY this JSON and nothing else — no markdown, no code fences, no commentary:
            {"recap": "3 to 5 short sentences, at most 70 words, grouped by topic, plain prose"}
            Rules: the FIRST sentence must name the single most important story and its concrete detail (who,
            what, the number) — only that sentence is visible before the reader opens the notification, so it
            has to stand alone. Then the lead stories, then the rest by topic. Do not open with a scene-setting
            or counting sentence ("Several stories today", "Here is what is new"). Do not invent details that
            are not in the headlines. Do not list the headlines back; write sentences. No bullet points, no labels.
            """
        var lines: [String] = []
        if !headlines.isEmpty {
            lines.append("Lead stories:")
            lines.append(contentsOf: headlines.map { "- " + $0 })
        }
        if !others.isEmpty {
            lines.append(headlines.isEmpty ? "Stories:" : "Other stories:")
            lines.append(contentsOf: others.map { "- " + $0 })
        }
        return (system, lines.joined(separator: "\n"))
    }

    /// The model's answer → the recap text, or nil when it is unusable (then the plain list goes out).
    static func parseRecap(_ text: String) -> String? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            t = t.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let start = t.firstIndex(of: "{"), let end = t.lastIndex(of: "}"), start < end else { return nil }
        let json = String(t[start...end])
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let recap = (object["recap"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !recap.isEmpty
        else { return nil }
        let upper = recap.uppercased()
        if upper.contains("HEADLINE:") || upper.contains("LEAD:") || recap.contains("\n- ") { return nil }
        return recap
    }
}
