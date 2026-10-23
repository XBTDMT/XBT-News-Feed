import Foundation
import SwiftUI
import SwiftSoup

// MARK: - Date Formatting

/// One shared formatter. DateFormatter allocation costs milliseconds; these were being created per
/// row per redraw. DateFormatter is documented thread-safe on modern macOS.
enum SQLiteDateFormatting {
    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

extension Date {
    /// Format as SQLite datetime string: "yyyy-MM-dd HH:mm:ss" (UTC)
    var sqliteString: String {
        SQLiteDateFormatting.formatter.string(from: self)
    }

    /// Relative time from a Date: "now", "2m", "1h", "3d"
    var relativeTime: String {
        let interval = Date().timeIntervalSince(self)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        return "\(Int(interval / 86400))d"
    }
}

extension String {
    /// Parse a SQLite datetime string ("yyyy-MM-dd HH:mm:ss", UTC).
    var sqliteDate: Date? {
        SQLiteDateFormatting.formatter.date(from: self)
    }

    /// Parse SQLite datetime string to relative time: "2m", "1h", "3d"
    var relativeTime: String {
        guard let date = sqliteDate else { return self }
        return date.relativeTime
    }
}

// MARK: - HTML entities

extension String {
    /// Decodes HTML entities ("&#038;", "&#8217;", "&amp;") that some feeds leave in titles.
    /// Plain text passes through unchanged; a decode failure returns the original.
    var htmlEntitiesDecoded: String {
        guard contains("&") else { return self }
        return (try? Entities.unescape(self)) ?? self
    }
}

// MARK: - Priority Badge Color

extension String {
    var priorityColor: Color {
        switch self {
        case "breaking": return .red
        case "important": return .yellow
        default: return .green
        }
    }
}
