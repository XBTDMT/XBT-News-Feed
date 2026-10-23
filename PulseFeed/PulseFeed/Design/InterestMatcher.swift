import Foundation

/// One thing a typed interest turned into.
enum InterestMatch: Hashable, Sendable {
    /// A catalog topic to switch on.
    case topic(id: String)
    /// A name to follow (alert-capable), with the catalog topic it belongs to when known.
    case follow(name: String, topicID: String?)
    /// A news search for something the catalog has no topic for, filed under a chip-level category.
    case newSearch(phrase: String, category: String)
}

/// Where the typing happens: the Topics step / Settings box, or the Follow step.
enum InterestContext: Sendable {
    case topics, follow
}

/// What typed interests sort into: `sure` is applied when the person presses Add; `suggested` is shown
/// for a tap and applied only if tapped (G-5). Only an exact catalog name, or a phrase the catalog's names
/// fully explain, is sure; anything partial is a suggestion, so a wrong guess ("apple pie" → Apple)
/// changes nothing. A phrase that is not fully placed is always searched for, so nothing typed is lost.
struct InterestResult: Equatable, Sendable {
    var sure: [InterestMatch] = []
    var suggested: [InterestMatch] = []

    mutating func addSure(_ m: InterestMatch) {
        if case .follow(let name, _) = m, sure.contains(where: { if case .follow(name, _) = $0 { return true } else { return false } }) { return }
        if !sure.contains(m) { sure.append(m) }
        suggested.removeAll { $0 == m }
    }

    mutating func addSuggested(_ m: InterestMatch) {
        if sure.contains(m) || suggested.contains(m) { return }
        if case .follow(let name, _) = m,
           (sure + suggested).contains(where: { if case .follow(name, _) = $0 { return true } else { return false } }) { return }
        suggested.append(m)
    }
}

/// Typed interests ("Arsenal, sourdough, Formula E") → catalog topics, names to follow and news
/// searches. Word matching against the catalog's names (with their full names, G-4) decides what is sure;
/// the on-device model (on-device only: nothing typed leaves the Mac) only sorts the phrases the catalog
/// cannot place into follow-or-search and a chip. Nothing typed is dropped.
enum InterestMatcher {
    static let maxCharacters = 500
    static let minSubstring = 4

    static let clubWords: Set<String> = ["fc", "cf", "sc"]
    static let footballTopics: Set<String> = ["soccer", "premier-league", "la-liga", "champions-league", "mls"]

    /// Words that add nothing to a name typed in a phrase ("lakers fan", "arsenal fc").
    static let filler: Set<String> = ["fan", "fans", "news", "fc", "cf", "sc", "club", "team", "updates", "update",
                                      "scores", "score", "highlights", "my", "latest"]

    /// Split on commas, semicolons and new lines only: "R&B", "AT&T", "Barnes & Noble" and "Tom and Jerry"
    /// stay whole. Read up to the last separator inside the first 500 characters; a list's joiner ("…, and
    /// ufc") and a leading "#" dropped; one-letter and joiner-only phrases dropped; repeats dropped.
    static func phrases(_ text: String) -> [String] {
        var bounded = String(text.prefix(maxCharacters)).lowercased()
        if text.count > maxCharacters, let cut = bounded.lastIndex(where: { ",;\n".contains($0) }) {
            bounded = String(bounded[..<cut])
        }
        var seen = Set<String>()
        return bounded
            .components(separatedBy: CharacterSet(charactersIn: ",;\n"))
            .enumerated()
            .map { index, item in
                // A list's joiner is not part of the item ("…, and ufc"); a first item keeps its own words
                // ("And Just Like That"). Then a leading "#" goes.
                let trimmed = trimmingJoiners(item.trimmingCharacters(in: .whitespacesAndNewlines), leading: index > 0)
                return String(trimmed.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces)
            }
            .filter { phrase in
                // A phrase of nothing but joiners ("and", "&") names nothing; a lone filler word is still
                // searched for.
                phrase.count >= 2 && !words(phrase).allSatisfy(joiners.contains) && seen.insert(phrase).inserted
            }
    }

    static let joiners: Set<String> = ["and", "&", "+", "or"]

    /// "and ufc" → "ufc", "lakers &" → "lakers": the joiner of an Oxford-comma list is not part of the item.
    private static func trimmingJoiners(_ phrase: String, leading: Bool) -> String {
        var parts = phrase.split(separator: " ").map(String.init)
        while leading, let first = parts.first, joiners.contains(first) { parts.removeFirst() }
        while let last = parts.last, joiners.contains(last) { parts.removeLast() }
        return parts.joined(separator: " ")
    }

    // MARK: - Word matching

    static func sort(_ phrases: [String], catalog: Catalog, context: InterestContext) -> InterestResult {
        var r = InterestResult()
        for phrase in phrases { place(phrase, catalog: catalog, context: context, into: &r) }
        return r
    }

    /// The sure part of `sort`.
    static func wordMatch(_ phrases: [String], catalog: Catalog, context: InterestContext) -> [InterestMatch] {
        sort(phrases, catalog: catalog, context: context).sure
    }

    private static func place(_ phrase: String, catalog: Catalog, context: InterestContext, into r: inout InterestResult) {
        if let parts = coveredParts(phrase, catalog: catalog) {
            // Exactly what each part names, nothing more ("us open and wimbledon" is two tennis events,
            // not US News; "heat and lakers" keeps the Heat).
            for (part, exact) in parts {
                exact.forEach { r.addSure($0) }
                // A topic alias typed in the Follow step is followed too ("ufc"), inside its topic's chip.
                if context == .follow, !exact.contains(where: isFollow),
                   case .topic(let id)? = exact.first(where: { if case .topic = $0 { return true } else { return false } }) {
                    r.addSure(.follow(name: part, topicID: id))
                }
            }
            return
        }
        if context == .follow { r.addSure(.follow(name: phrase, topicID: nil)) }
        // Filed under General: a guessed chip would switch a category on that nobody chose.
        r.addSure(.newSearch(phrase: phrase, category: NewsCategory.general.id))
        partialMatches(phrase, catalog: catalog).forEach { r.addSuggested($0) }
    }

    /// The phrases the catalog cannot place: the only ones the model is asked about.
    static func unplaced(_ phrases: [String], catalog: Catalog) -> [String] {
        phrases.filter { coveredParts($0, catalog: catalog) == nil }
    }

    private static func isFollow(_ m: InterestMatch) -> Bool {
        if case .follow = m { return true } else { return false }
    }

    /// The phrase is a topic's id, label or alias, or any name of a follow (which also brings its topic).
    /// Compared word for word, so punctuation inside a name does not matter ("harley-davidson",
    /// "christie's", "football (soccer)").
    private static func exactMatches(_ phrase: String, catalog: Catalog) -> [InterestMatch] {
        let key = normalized(phrase)
        guard !key.isEmpty else { return [] }
        var exact: [InterestMatch] = []
        for t in catalog.topics where names(of: t).contains(where: { normalized($0) == key }) { exact.append(.topic(id: t.id)) }
        for t in catalog.topics {
            for f in t.follows where t.forms(of: f).contains(where: { normalized($0) == key }) {
                exact.append(.follow(name: f, topicID: t.id))
                exact.append(.topic(id: t.id))
            }
        }
        return exact
    }

    /// As whole words only: a topic name, or a follow's name or full name, inside the phrase. A follow
    /// flagged as an everyday word counts only by its full name or with filler around it ("miami heat",
    /// "heat fan"; "heat pump" offers nothing). A name never matches inside a word.
    private static func partialMatches(_ phrase: String, catalog: Catalog) -> [InterestMatch] {
        let phraseWords = words(phrase)
        let padded = " " + phraseWords.joined(separator: " ") + " "
        func contains(_ name: String) -> Bool {
            let w = words(name)
            return !w.isEmpty && padded.contains(" " + w.joined(separator: " ") + " ")
        }
        var found: [InterestMatch] = []
        func add(_ m: InterestMatch) { if !found.contains(m) { found.append(m) } }
        for t in catalog.topics {
            if names(of: t).contains(where: contains) { add(.topic(id: t.id)) }
            let everyday = Set(t.everydayFollows ?? [])
            for f in t.follows {
                let hits = t.forms(of: f).filter(contains)
                guard !hits.isEmpty else { continue }
                if everyday.contains(f), hits == [f] {
                    var rest = phraseWords
                    for word in words(f) { if let k = rest.firstIndex(of: word) { rest.remove(at: k) } }
                    guard rest.allSatisfy(filler.contains) else { continue }
                }
                add(.follow(name: f, topicID: t.id))
                add(.topic(id: t.id))
            }
        }
        return found
    }

    /// Fully explained: the phrase is exactly a catalog name, or split on "and", "&", "+" and "or" every
    /// part is ("nba and f1", "lakers fan", "arsenal fc"), each with its exact matches; nil otherwise.
    /// "space cowboys", "apple pie" and "the sinner" are not explained: they are searched for, and their
    /// partial matches only suggested.
    private static func coveredParts(_ phrase: String, catalog: Catalog) -> [(part: String, exact: [InterestMatch])]? {
        let whole = exactMatches(phrase, catalog: catalog)
        if !whole.isEmpty { return [(phrase, whole)] }
        var parts: [[String]] = [[]]
        for w in words(phrase) {
            if joiners.contains(w) { parts.append([]) } else { parts[parts.count - 1].append(w) }
        }
        var out: [(part: String, exact: [InterestMatch])] = []
        for part in parts where !part.isEmpty {
            let full = part.joined(separator: " ")
            let asTyped = exactMatches(full, catalog: catalog)
            if !asTyped.isEmpty { out.append((full, asTyped)); continue }
            let named = part.filter { !filler.contains($0) }
            guard !named.isEmpty else { return nil }
            let name = named.joined(separator: " ")
            let exact = exactMatches(name, catalog: catalog)
            guard !exact.isEmpty else { return nil }
            // "fc", "cf" and "sc" name a football club: filler only for a football topic ("rangers fc" is
            // not the New York Rangers).
            if part.contains(where: clubWords.contains),
               !exact.contains(where: { if case .topic(let id) = $0 { return footballTopics.contains(id) } else { return false } }) {
                return nil
            }
            out.append((name, exact))
        }
        return out.isEmpty ? nil : out
    }

    private static func names(of t: CatalogTopic) -> [String] {
        [t.id, t.label.lowercased()] + t.aliases.map { $0.lowercased() }
    }

    private static func normalized(_ s: String) -> String { words(s.lowercased()).joined(separator: " ") }

    /// Apostrophes and dots are dropped, not word breaks ("christie's" = "christies", "u.s." = "us").
    private static func words(_ s: String) -> [String] {
        s.replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "’", with: "").replacingOccurrences(of: ".", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "&+")).inverted).filter { !$0.isEmpty }
    }

    // MARK: - The model

    /// The model is told nothing about the catalog's topics or follows: it only says whether each phrase
    /// names a person, team, company, product or coin, and which chip-level category it belongs to.
    static func prompt(phrases: [String]) -> (system: String, user: String) {
        let categories = NewsCategory.all.map { "\($0.id) (\($0.label))" }.joined(separator: ", ")
        let system = """
            You sort a reader's interests for a news app. For each phrase, answer with ONLY a JSON array of
            objects: {"phrase": the phrase exactly as given, "kind": "person_or_team" if it names a person,
            team, company, product or coin, otherwise "other", "category": the one category id that fits best
            from: \(categories)}. No prose, no code fences.
            """
        let encoded = (try? JSONEncoder().encode(phrases)).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
        return (system, "Phrases: \(encoded)")
    }

    /// Phrases the catalog places are sorted by word matching whatever the answer says; for the rest the
    /// answer decides follow-or-search and the chip (an unknown category is "general"), and word matching
    /// still offers its partial matches as suggestions; a phrase the answer leaves out is word-matched.
    static func parseModelAnswer(_ text: String, phrases: [String], catalog: Catalog, context: InterestContext) -> InterestResult {
        struct Entry: Decodable { let phrase: String; let kind: String; let category: String? }
        var entries: [Entry] = []
        if let start = text.firstIndex(of: "["), let end = text.lastIndex(of: "]"), start < end,
           let decoded = try? JSONDecoder().decode([Entry].self, from: Data(text[start...end].utf8)) {
            entries = decoded
        }
        let open = Set(unplaced(phrases, catalog: catalog))
        let categories = Set(NewsCategory.pickerIDs)
        var answered: [String: (follow: Bool, category: String)] = [:]
        for e in entries {
            let phrase = e.phrase.lowercased().trimmingCharacters(in: .whitespaces)
            guard open.contains(phrase), answered[phrase] == nil else { continue }
            let category = e.category.flatMap { categories.contains($0) ? $0 : nil } ?? NewsCategory.general.id
            answered[phrase] = (e.kind == "person_or_team" || context == .follow, category)
        }
        var r = InterestResult()
        for phrase in phrases {
            if let a = answered[phrase] {
                if a.follow { r.addSure(.follow(name: phrase, topicID: nil)) }
                r.addSure(.newSearch(phrase: phrase, category: a.category))
                partialMatches(phrase, catalog: catalog).forEach { r.addSuggested($0) }
            } else {
                place(phrase, catalog: catalog, context: context, into: &r)
            }
        }
        return r
    }

    /// The model (for what the catalog cannot place) when the on-device engine is there and the gate lets
    /// the call through; word matching otherwise.
    static func resolve(_ text: String, catalog: Catalog, context: InterestContext, gate: AIGate = .shared) async -> (result: InterestResult, engine: String) {
        let list = phrases(text)
        guard !list.isEmpty else { return (InterestResult(), "none") }
        let open = unplaced(list, catalog: catalog)
        if !open.isEmpty, OnDeviceEnricher.isAvailable {
            let (system, user) = prompt(phrases: open)
            if let answer = await gate.generateText(system: system, user: user, maxTokens: 400, kind: "aiInterests", preferOnDevice: true, onDeviceOnly: true) {
                return (parseModelAnswer(answer, phrases: list, catalog: catalog, context: context), "on-device")
            }
        }
        return (sort(list, catalog: catalog, context: context), "word match")
    }
}
