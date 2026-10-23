import Foundation

/// FeedKit's RFC 822 date parser knows GMT/UT and the US zones, not British Summer Time or the
/// European ones, so a feed that stamps its items "… 13:49:57 BST" fails to parse all summer
/// (DJ Mag, 2026-09-07). Only the date fields are rewritten, and only these named zones.
enum FeedDateNormalization {
    static let zones: [String: String] = [
        "BST": "+0100", "IST": "+0100",   // British / Irish Summer Time
        "CET": "+0100", "CEST": "+0200", "WET": "+0000", "WEST": "+0100",
        "EET": "+0200", "EEST": "+0300", "MSK": "+0300",
        "AEST": "+1000", "AEDT": "+1100", "JST": "+0900", "KST": "+0900", "HKT": "+0800", "SGT": "+0800",
    ]
    private static let pattern: NSRegularExpression = {
        let names = zones.keys.sorted { $0.count > $1.count }.joined(separator: "|")
        // A date field (pubDate / dc:date / lastBuildDate / updated / published) ending in a named zone.
        return try! NSRegularExpression(
            pattern: "(<(?:pubDate|dc:date|lastBuildDate|updated|published|modified)>[^<]*?\\d{2}:\\d{2}(?::\\d{2})?\\s)(\(names))(\\s*</)",
            options: [])
    }()

    static func numericTimezones(in xml: String) -> String {
        let range = NSRange(xml.startIndex..., in: xml)
        var out = xml
        var offset = 0
        for m in pattern.matches(in: xml, options: [], range: range) {
            guard let zoneRange = Range(m.range(at: 2), in: xml), let numeric = zones[String(xml[zoneRange])] else { continue }
            let start = out.index(out.startIndex, offsetBy: xml.distance(from: xml.startIndex, to: zoneRange.lowerBound) + offset)
            let end = out.index(start, offsetBy: xml.distance(from: zoneRange.lowerBound, to: zoneRange.upperBound))
            out.replaceSubrange(start..<end, with: numeric)
            offset += numeric.count - xml.distance(from: zoneRange.lowerBound, to: zoneRange.upperBound)
        }
        return out
    }

    /// The same, on the raw body; nil when nothing changed.
    static func numericTimezones(in data: Data) -> Data? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let fixed = numericTimezones(in: text)
        return fixed == text ? nil : fixed.data(using: .utf8)
    }
}
