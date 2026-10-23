import Foundation

/// The 30 NBA teams by the names a person types to follow one ("lakers", "los angeles lakers"), keyed by the
/// league's abbreviation. Live scores (balldontlie, and ESPN in the private build) follow the followed list
/// through this, so no team is built in.
enum NBATeams {
    static let all: [(abbreviation: String, nickname: String, fullName: String)] = [
        ("ATL", "hawks", "atlanta hawks"), ("BOS", "celtics", "boston celtics"), ("BKN", "nets", "brooklyn nets"),
        ("CHA", "hornets", "charlotte hornets"), ("CHI", "bulls", "chicago bulls"), ("CLE", "cavaliers", "cleveland cavaliers"),
        ("DAL", "mavericks", "dallas mavericks"), ("DEN", "nuggets", "denver nuggets"), ("DET", "pistons", "detroit pistons"),
        ("GSW", "warriors", "golden state warriors"), ("HOU", "rockets", "houston rockets"), ("IND", "pacers", "indiana pacers"),
        ("LAC", "clippers", "la clippers"), ("LAL", "lakers", "los angeles lakers"), ("MEM", "grizzlies", "memphis grizzlies"),
        ("MIA", "heat", "miami heat"), ("MIL", "bucks", "milwaukee bucks"), ("MIN", "timberwolves", "minnesota timberwolves"),
        ("NOP", "pelicans", "new orleans pelicans"), ("NYK", "knicks", "new york knicks"), ("OKC", "thunder", "oklahoma city thunder"),
        ("ORL", "magic", "orlando magic"), ("PHI", "76ers", "philadelphia 76ers"), ("PHX", "suns", "phoenix suns"),
        ("POR", "trail blazers", "portland trail blazers"), ("SAC", "kings", "sacramento kings"), ("SAS", "spurs", "san antonio spurs"),
        ("TOR", "raptors", "toronto raptors"), ("UTA", "jazz", "utah jazz"), ("WAS", "wizards", "washington wizards"),
    ]

    static let abbreviationByName: [String: String] = {
        var map: [String: String] = [:]
        for t in all { map[t.nickname] = t.abbreviation; map[t.fullName] = t.abbreviation }
        return map
    }()

    /// The abbreviations of every followed name that is an NBA team, in the order followed, without repeats.
    static func abbreviations(followed: [String]) -> [String] {
        var seen = Set<String>()
        return followed.map { UrgencyClassifier.splitScope($0)?.rest ?? $0 }
            .compactMap { abbreviationByName[$0.lowercased().trimmingCharacters(in: .whitespaces)] }
            .filter { seen.insert($0).inserted }
    }
}
