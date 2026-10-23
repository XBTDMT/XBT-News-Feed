import Foundation
import FeedKit
import GRDB

/// The list state every popover and window shares: the article observation for one category,
/// full-text search, the Google News web search and the relative-time ticker. Views drive the async
/// functions from `.task(id:)` so SwiftUI cancels them on change.
@MainActor
@Observable
final class FeedListModel {
    let appDB: AppDatabase

    var articles: [ArticleInfo] = []
    var searchText = ""
    var searchResults: [ArticleInfo] = []
    var webSearchResults: [WebSearchItem] = []
    var isSearchingWeb = false
    var lastUpdated: Date?
    /// Flips every 30 s (60 s off AC) while a view is visible so relative times re-render.
    var tick = false

    var displayed: [ArticleInfo] { searchText.isEmpty ? articles : searchResults }

    init(appDB: AppDatabase) {
        self.appDB = appDB
    }

    /// Split of `displayed` against the last-looked time (idea ①).
    func partition(lastLooked: Date?) -> SinceLastLooked.Partition<ArticleInfo> {
        SinceLastLooked.partition(displayed, arrival: { $0.arrivalDate }, lastLooked: lastLooked)
    }

    /// `nil` = all, `"starred"`, `"saved"`, or a feed category. Runs until cancelled.
    func observe(category: String?) async {
        let observation = ArticleInfo.observation(category: category)
        do {
            for try await newArticles in observation.values(in: appDB.dbPool) {
                articles = newArticles
                lastUpdated = Date()
            }
        } catch {
            // Observation cancelled (view disappeared or category changed)
        }
    }

    /// FTS after 2 characters (300 ms debounce), then the web after 3 characters (+200 ms).
    func runSearch(_ query: String) async {
        webSearchResults = []
        guard query.count >= 2 else {
            searchResults = []
            return
        }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        let results = (try? await appDB.searchArticles(query: query)) ?? []
        guard !Task.isCancelled else { return }
        searchResults = results
        guard query.count >= 3 else { return }
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled else { return }
        await searchWeb(query: query)
    }

    func tickWhileVisible() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(PowerMonitor.shared.shouldThrottle ? 60 : 30))
            tick.toggle()
        }
    }

    private func searchWeb(query: String) async {
        guard let url = NewsSearch.url(query: query, region: "us") else { return }
        isSearchingWeb = true
        defer { isSearchingWeb = false }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else { return }

        guard let feed = try? FeedKit.Feed(data: data) else { return }
        switch feed {
        case .rss(let rss):
            guard let items = rss.channel?.items else { return }
            webSearchResults = items.prefix(8).compactMap { item -> WebSearchItem? in
                guard let title = item.title, let link = item.link else { return nil }
                return WebSearchItem(title: title, url: link, source: item.source?.text ?? "Google News")
            }
        default:
            break
        }
    }
}
