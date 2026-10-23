import Foundation

/// What a macOS banner actually shows, and how to fill it.
///
/// A collapsed banner gives three always-visible lines — title, subtitle, and about two lines of
/// body — and hides the rest until the reader hovers. So the job here is not "write less": it is
/// that the *front* of every field has to carry the news, because the front is the part that
/// survives. The source name, the coverage count and the housekeeping go last, since those are the
/// characters macOS eats first. And a cut lands on a sentence or a word, never mid-word: a banner
/// that stops at "the Fed cut rates by 25 basis po" reads as broken rather than as abbreviated.
enum NotificationText {
    /// The recap's subtitle: the one line that is always on screen and today carries nothing at all.
    /// Lead stories first, then the rest, joined until the line is full.
    static let leadLineLimit = 90
    /// The body of an urgent alert. Well past the two lines a collapsed banner shows, because the
    /// remainder is not wasted — it is what the reader gets on hover and in Notification Center.
    static let bodyLimit = 320

    /// One always-visible line naming what actually happened: headlines first, then the others,
    /// joined with "·" while they fit. Never empty when there is any story at all.
    static func leadLine(headlines: [String], others: [String], limit: Int = leadLineLimit) -> String {
        let candidates = (headlines + others)
            .map(collapseWhitespace)
            .filter { !$0.isEmpty }
        guard let first = candidates.first else { return "" }

        var line = clip(first, to: limit)
        for candidate in candidates.dropFirst() {
            let joined = line + " · " + candidate
            guard joined.count <= limit else { break }
            line = joined
        }
        return line
    }

    /// Cuts to `limit` on a sentence end when one falls late enough to be worth it, otherwise on a
    /// word boundary with an ellipsis. Text already inside the limit is returned untouched.
    static func clip(_ text: String, to limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit, limit > 0 else { return trimmed }

        let head = String(trimmed.prefix(limit))
        // A sentence end is only a better cut than a word cut if it keeps most of the room; ending
        // after three words when there was space for thirty is a worse answer than an ellipsis.
        let sentenceFloor = (limit * 3) / 5
        if let end = head.lastIndex(where: { $0 == "." || $0 == "!" || $0 == "?" }) {
            let kept = String(head[...end])
            if kept.count >= sentenceFloor {
                return kept.trimmingCharacters(in: .whitespaces)
            }
        }
        if let space = head.lastIndex(of: " ") {
            let kept = String(head[..<space]).trimmingCharacters(in: .whitespaces)
            if !kept.isEmpty { return kept + "…" }
        }
        return head.trimmingCharacters(in: .whitespaces) + "…"
    }

    /// The urgent alert's subtitle. The reason it is urgent leads, because that is the thing the
    /// reader needs in order to decide whether to look now; the outlet is the part that can be lost.
    static func urgentSubtitle(reason: String, sourceCount: Int, feedTitle: String) -> String {
        let parts = sourceCount > 1
            ? [reason, "\(sourceCount) sources", feedTitle]
            : [reason, feedTitle]
        return parts
            .map(collapseWhitespace)
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private static func collapseWhitespace(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }
}
