import Foundation
import UserNotifications

struct NotificationService: Sendable {

    // MARK: - Category & Permission Setup

    static func setupCategories() {
        let openAction = UNNotificationAction(
            identifier: "OPEN_ACTION", title: "Open", options: .foreground)
        let markReadAction = UNNotificationAction(
            identifier: "MARK_READ_ACTION", title: "Mark Read", options: [])
        let dismissAction = UNNotificationAction(
            identifier: "DISMISS", title: "Dismiss", options: .destructive)

        let newsCategory = UNNotificationCategory(
            identifier: "NEWS",
            actions: [openAction, markReadAction, dismissAction],
            intentIdentifiers: [], options: [])
        let priceCategory = UNNotificationCategory(
            identifier: "PRICE_ALERT",
            actions: [dismissAction],
            intentIdentifiers: [], options: [])
        let summaryMarkRead = UNNotificationAction(
            identifier: "SUMMARY_MARK_READ", title: "Mark these read", options: [])
        let summaryCategory = UNNotificationCategory(
            identifier: "SUMMARY",
            actions: [openAction, summaryMarkRead, dismissAction],
            intentIdentifiers: [], options: [])

        UNUserNotificationCenter.current()
            .setNotificationCategories([newsCategory, priceCategory, summaryCategory])
    }

    static func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        let statusName: String
        switch settings.authorizationStatus {
        case .notDetermined: statusName = "notDetermined"
        case .denied: statusName = "DENIED"
        case .authorized: statusName = "authorized"
        case .provisional: statusName = "provisional"
        case .ephemeral: statusName = "ephemeral"
        @unknown default: statusName = "unknown(\(settings.authorizationStatus.rawValue))"
        }
        print("PulseFeed: [Notifications] Auth status: \(statusName), bundle: \(Bundle.main.bundleIdentifier ?? "nil")")

        if settings.authorizationStatus == .notDetermined {
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                print("PulseFeed: [Notifications] Auth request → \(granted ? "GRANTED" : "DENIED")")
            } catch {
                print("PulseFeed: [Notifications] Auth request ERROR: \(error)")
            }
        } else if settings.authorizationStatus == .denied {
            print("PulseFeed: [Notifications] User denied. Enable in System Settings → Notifications → \(AppInfo.shortName)")
        } else {
            print("PulseFeed: [Notifications] Authorized (alerts: \(settings.alertSetting == .enabled), sound: \(settings.soundSetting == .enabled))")
        }
    }

    // MARK: - Should Notify

    func shouldNotify(
        _ article: ArticleInfo,
        settings: NotificationSettings,
        rateLimiter: RateLimiter
    ) -> Bool {
        // Already notified
        if article.isNotified == true { return false }

        // Category disabled
        if !(settings.isCategoryEnabled(article.feedCategory)) { return false }

        // Quiet hours
        if settings.quietHoursEnabled && settings.isInQuietHours() { return false }

        // Relevance threshold (0.0 default = notify all until AI pipeline)
        if let score = article.relevanceScore, score < settings.relevanceThreshold {
            return false
        }

        // Rate limiting
        let isBreaking = article.priority == "breaking"
        if !rateLimiter.allowNotification(
            category: article.feedCategory, isBreaking: isBreaking,
            maxPerCategory: settings.maxPerCategoryPerHour,
            maxTotal: settings.maxTotalPerHour
        ) {
            return false
        }

        return true
    }

    // MARK: - Post Notification

    func postArticleNotification(
        _ article: ArticleInfo, feedTitle: String
    ) async {
        let content = UNMutableNotificationContent()
        content.title = article.title ?? "New Article"
        // Idea ②: coverage is a count in the subtitle, not an "Also in …" line in the body.
        content.subtitle = article.sourceCount > 1 ? "\(feedTitle) · \(article.sourceCount) sources" : feedTitle

        if let body = Self.body(for: article) {
            content.body = body
        }

        content.threadIdentifier = article.feedCategory
        content.categoryIdentifier = "NEWS"
        content.sound = .default
        content.userInfo = [
            "articleID": article.articleID,
            "url": article.url ?? "",
        ]

        // Download thumbnail — 5s timeout, skip on failure
        if let imageURLString = article.imageURL,
            let imageURL = URL(string: imageURLString)
        {
            if let attachment = await downloadThumbnail(
                imageURL: imageURL, articleID: article.articleID)
            {
                content.attachments = [attachment]
            }
        }

        let request = UNNotificationRequest(
            identifier: article.articleID, content: content, trigger: nil)

        try? await UNUserNotificationCenter.current().add(request)
    }

    /// The alert body: the AI one-liner when there is one, otherwise the article's own opening.
    /// Both go through the same clip, so a runaway `tldr` cannot become a wall of text and the
    /// article preview no longer stops mid-word the way a bare `prefix(200)` did.
    static func body(for article: ArticleInfo) -> String? {
        for candidate in [article.summary, article.contentText] {
            guard let candidate else { continue }
            let clipped = NotificationText.clip(candidate, to: NotificationText.bodyLimit)
            if !clipped.isEmpty { return clipped }
        }
        return nil
    }

    /// An urgent story: its own alert, right away. `reason` is one short line ("Celtics trade").
    func postUrgent(_ article: ArticleInfo, reason: String) async {
        let content = UNMutableNotificationContent()
        content.title = article.title ?? "Breaking"
        // Why it is urgent leads; the outlet trails, because the tail is what macOS truncates.
        content.subtitle = NotificationText.urgentSubtitle(
            reason: reason, sourceCount: article.sourceCount, feedTitle: article.feedTitle)
        if let body = Self.body(for: article) {
            content.body = body
        }
        content.threadIdentifier = "urgent"
        content.categoryIdentifier = "NEWS"
        content.sound = .defaultCritical
        content.interruptionLevel = .timeSensitive
        content.userInfo = ["articleID": article.articleID, "url": article.url ?? "", "urgent": true]
        if let imageURLString = article.imageURL, let imageURL = URL(string: imageURLString),
           let attachment = await downloadThumbnail(imageURL: imageURL, articleID: article.articleID) {
            content.attachments = [attachment]
        }
        do {
            try await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "urgent-" + article.articleID, content: content, trigger: nil))
        } catch {
            print("PulseFeed: [Urgent] Notification Center refused the alert: \(error)")
        }
    }

    /// A big move in a chosen instrument: its own time-sensitive alert, once per move (MarketShock).
    func postMarketShock(label: String, change: Double, price: Double, rolling24h: Bool, key: String) async {
        let content = UNMutableNotificationContent()
        content.title = MarketShock.title(label: label, change: change, rolling24h: rolling24h)
        content.subtitle = "Market move"
        content.body = "\(label) is at \(PriceFormatting.price(price, symbol: label))."
        content.threadIdentifier = "markets"
        content.sound = .defaultCritical
        content.interruptionLevel = .timeSensitive
        do {
            try await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "shock-" + key, content: content, trigger: nil))
        } catch {
            print("PulseFeed: [Shock] Notification Center refused the alert: \(error)")
        }
    }

    /// The 15-minute recap: one notification, replaced (same identifier) rather than stacked.
    func postSummary(_ summary: SummaryText, storyIDs: [String]) async {
        let content = UNMutableNotificationContent()
        content.title = summary.title
        // The title is only a count. Without this line the collapsed banner names no story at all.
        if !summary.subtitle.isEmpty { content.subtitle = summary.subtitle }
        content.body = summary.body
        content.threadIdentifier = "summary"
        content.categoryIdentifier = "SUMMARY"
        content.sound = nil
        content.interruptionLevel = .passive
        content.userInfo = ["summaryIDs": storyIDs]
        do {
            try await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "summary", content: content, trigger: nil))
            let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
            print("PulseFeed: [Recap] delivered to Notification Center; \(delivered.count) notification(s) from this app are showing")
        } catch {
            print("PulseFeed: [Recap] Notification Center refused the recap: \(error)")
        }
    }

    // MARK: - Thumbnail Download

    private func downloadThumbnail(
        imageURL: URL, articleID: String
    ) async -> UNNotificationAttachment? {
        var request = URLRequest(url: imageURL)
        request.timeoutInterval = 5

        guard let (data, response) = try? await URLSession.shared.data(for: request),
            let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200,
            !data.isEmpty
        else { return nil }

        // Determine file extension from content type
        let ext: String
        switch httpResponse.mimeType {
        case "image/png": ext = "png"
        case "image/gif": ext = "gif"
        default: ext = "jpg"
        }

        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(articleID).\(ext)")

        guard let _ = try? data.write(to: tempFile) else { return nil }

        return try? UNNotificationAttachment(
            identifier: "thumb-\(articleID)", url: tempFile)
    }
}

// MARK: - Notification Settings

struct NotificationSettings: Sendable {
    /// Categories the user switched off for notifications (`notif_<id>` = false). Everything else notifies.
    var disabledCategories: Set<String>
    var quietHoursEnabled: Bool
    var quietHoursStart: Int
    var quietHoursEnd: Int
    var maxPerCategoryPerHour: Int
    var maxTotalPerHour: Int
    var relevanceThreshold: Double

    func isCategoryEnabled(_ category: String) -> Bool {
        !disabledCategories.contains(category)
    }

    static func notificationKey(for category: String) -> String { "notif_\(category)" }

    func isInQuietHours() -> Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        if quietHoursStart < quietHoursEnd {
            // e.g., 1am–6am
            return hour >= quietHoursStart && hour < quietHoursEnd
        } else {
            // e.g., 23pm–7am (wraps midnight)
            return hour >= quietHoursStart || hour < quietHoursEnd
        }
    }

    /// Read current settings from UserDefaults
    static func fromDefaults(_ d: UserDefaults = .standard) -> NotificationSettings {
        let off = (NewsCategory.all + [NewsCategory.general])
            .map(\.id)
            .filter { (d.object(forKey: notificationKey(for: $0)) as? Bool ?? true) == false }
        return NotificationSettings(
            disabledCategories: Set(off),
            quietHoursEnabled: d.object(forKey: "notif_quietHoursEnabled") as? Bool ?? false,
            quietHoursStart: d.object(forKey: "notif_quietHoursStart") as? Int ?? 23,
            quietHoursEnd: d.object(forKey: "notif_quietHoursEnd") as? Int ?? 7,
            maxPerCategoryPerHour: d.object(forKey: "notif_maxPerCategory") as? Int ?? 5,
            maxTotalPerHour: d.object(forKey: "notif_maxTotal") as? Int ?? 20,
            relevanceThreshold: d.object(forKey: "notif_relevanceThreshold") as? Double ?? 0.0
        )
    }
}

// MARK: - Rate Limiter

/// In-memory rate limiter — tracks notification timestamps per category.
/// Thread-safe via actor isolation (called from FeedEngine on MainActor).
final class RateLimiter: @unchecked Sendable {
    private var timestamps: [String: [Date]] = [:]
    private let lock = NSLock()

    func allowNotification(
        category: String, isBreaking: Bool,
        maxPerCategory: Int, maxTotal: Int
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        let oneHourAgo = now.addingTimeInterval(-3600)

        // Clean up old timestamps
        for key in timestamps.keys {
            timestamps[key] = timestamps[key]?.filter { $0 > oneHourAgo }
        }

        // Check global limit
        let totalCount = timestamps.values.flatMap { $0 }.count
        if totalCount >= maxTotal { return false }

        // Check per-category limit (breaking bypasses this)
        if !isBreaking {
            let categoryCount = timestamps[category]?.count ?? 0
            if categoryCount >= maxPerCategory { return false }
        }

        // Record this notification
        timestamps[category, default: []].append(now)
        return true
    }
}
