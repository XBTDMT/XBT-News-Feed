import Foundation

extension Notification.Name {
    /// Posted after `LastLookedStore.markLooked()` so the menu bar count can restart its observation.
    static let pulseFeedLastLookedChanged = Notification.Name("PulseFeed.lastLookedChanged")
}

/// Idea ①: when the popover was last closed. Written by every design's popover `onDisappear`, never
/// by the window, so "new" means "arrived since you last glanced".
enum LastLookedStore {
    static let key = "lastOpenedAt"

    static func read(_ defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: key) as? Date
    }

    static func markLooked(_ date: Date = Date(), defaults: UserDefaults = .standard) {
        defaults.set(date, forKey: key)
        NotificationCenter.default.post(name: .pulseFeedLastLookedChanged, object: nil)
    }
}

enum SinceLastLooked {
    struct Partition<T> {
        var new: [T]
        var seen: [T]
        var newCount: Int { new.count }
    }

    /// Pure split. Order inside each part is the input order (lists arrive newest-first).
    /// `lastLooked == nil` means the user has never looked, so everything is new.
    static func partition<T>(_ items: [T], arrival: (T) -> Date?, lastLooked: Date?) -> Partition<T> {
        guard let lastLooked else { return Partition(new: items, seen: []) }
        var new: [T] = []
        var seen: [T] = []
        for item in items {
            if let at = arrival(item), at > lastLooked { new.append(item) } else { seen.append(item) }
        }
        return Partition(new: new, seen: seen)
    }

    /// "Since you last looked · 4 new · 13:45" (24-hour local time); no time when never looked.
    static func dividerText(newCount: Int, lastLooked: Date?, timeZone: TimeZone = .current) -> String {
        var text = "Since you last looked · \(newCount) new"
        if let lastLooked {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            f.timeZone = timeZone
            f.locale = Locale(identifier: "en_US_POSIX")
            text += " · " + f.string(from: lastLooked)
        }
        return text
    }
}

extension ArticleInfo {
    /// `dateArrived` parsed; nil when the stored string is malformed (then the row counts as seen).
    var arrivalDate: Date? { dateArrived.sqliteDate }
}
