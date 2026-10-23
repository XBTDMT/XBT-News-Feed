import Foundation

/// Idea ②: two-to-four letter source monograms for the coverage chips ("TR", "BBC", "×3").
enum Monogram {
    /// Shipped feeds whose natural initials would mislead or collide.
    static let overrides: [String: String] = [
        "BBC Sport F1": "BBC", "ESPN": "ESPN", "ESPN MMA": "EMMA", "Hacker News (50+ points)": "HN",
        "Motorsport.com F1": "MS", "The Race F1": "TR", "CoinDesk": "CD", "Decrypt": "DC", "FT Markets": "FT",
        "NPR News": "NPR", "The Guardian": "TG", "The Verge": "TV", "MMA Mania": "MM", "Sherdog MMA": "SD",
        "Bloody Elbow": "BE", "OpenAI News": "OAI", "404 Media": "404", "Rest of World": "ROW",
        "MMA Fighting": "MF", "Jolpica F1": "JF", "CoinGecko": "CG",
    ]

    /// Override table first; otherwise strip parentheticals, ".com" and a leading "The", then
    /// initials of up to four words, or the first two letters of a single word. Always uppercase.
    static func make(_ title: String) -> String {
        if let o = overrides[title] { return o }
        var t = title.replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: ".com", with: "", options: .caseInsensitive)
        var words = t.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        if words.count > 1, words[0].lowercased() == "the" { words.removeFirst() }
        guard let first = words.first else { return "??" }
        if words.count == 1 { return String(first.prefix(2)).uppercased() }
        return words.prefix(4).compactMap(\.first).map(String.init).joined().uppercased()
    }

    /// Monograms for one list of titles. A later title that collides gets the first three letters of
    /// its longest word (then a numeric suffix if even that collides), so results are deterministic.
    static func assign(_ titles: [String]) -> [String: String] {
        var used = Set<String>()
        var out: [String: String] = [:]
        for title in titles {
            var m = make(title)
            if used.contains(m) {
                let longest = title.split(separator: " ").map(String.init)
                    .filter { $0.lowercased() != "the" }
                    .max(by: { $0.count < $1.count }) ?? title
                let base = String(longest.prefix(3)).uppercased()
                m = base
                var n = 2
                while used.contains(m) { m = base + "\(n)"; n += 1 }
            }
            used.insert(m)
            out[title] = m
        }
        return out
    }
}
