import Foundation
import CryptoKit
import FeedKit
import SwiftSoup

struct RSSFetchResult: Sendable {
    let articles: [Article]
    let wasNotModified: Bool
    let etag: String?
    let lastModified: String?
    let contentHash: String?
    let conditionalGetResetAt: String?
    var bytes: Int = 0
}

struct RSSFetcher: Sendable {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch(feed: Feed) async throws -> RSSFetchResult {
        // 1. Check 8-day conditional GET reset (NNW pattern)
        var effectiveEtag = feed.etag
        var effectiveLastModified = feed.lastModified
        var newConditionalGetResetAt = feed.conditionalGetResetAt

        let now = Date()
        if let resetAtString = feed.conditionalGetResetAt {
            if let resetDate = resetAtString.sqliteDate,
               now.timeIntervalSince(resetDate) > TimeInterval(PulseFeedConstants.conditionalGetResetDays * 86400)
            {
                effectiveEtag = nil
                effectiveLastModified = nil
                newConditionalGetResetAt = now.sqliteString
            }
        } else {
            newConditionalGetResetAt = now.sqliteString
        }

        // 2. Build request with conditional GET headers
        guard let url = URL(string: feed.url) else {
            throw RSSFetchError.invalidURL(feed.url)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        if let etag = effectiveEtag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastMod = effectiveLastModified {
            request.setValue(lastMod, forHTTPHeaderField: "If-Modified-Since")
        }

        // 3. Fetch
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RSSFetchError.notHTTP
        }

        // 4. HTTP 304: nothing changed
        if httpResponse.statusCode == 304 {
            return RSSFetchResult(
                articles: [], wasNotModified: true,
                etag: feed.etag, lastModified: feed.lastModified,
                contentHash: feed.contentHash,
                conditionalGetResetAt: newConditionalGetResetAt,
                bytes: data.count)
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw RSSFetchError.httpError(httpResponse.statusCode)
        }

        // Extract new conditional GET headers from response
        let responseEtag = httpResponse.value(forHTTPHeaderField: "ETag")
        let responseLastModified = httpResponse.value(forHTTPHeaderField: "Last-Modified")

        // 5. Compute MD5 content hash
        let contentHash = Insecure.MD5.hash(data: data)
            .map { String(format: "%02x", $0) }.joined()

        // 6. Compare to stored hash — skip parsing if identical
        if contentHash == feed.contentHash {
            // NNW bug fix: always update conditional GET headers even on hash match
            return RSSFetchResult(
                articles: [], wasNotModified: false,
                etag: responseEtag ?? feed.etag,
                lastModified: responseLastModified ?? feed.lastModified,
                contentHash: contentHash,
                conditionalGetResetAt: newConditionalGetResetAt,
                bytes: data.count)
        }

        // 7. Parse with FeedKit. Some WordPress feeds (e.g. Rest of World) open with an
        //    <?xml-stylesheet?> processing instruction that defeats FeedKit's format sniffing;
        //    retry once with processing instructions removed before giving up.
        guard let parsedFeed = Self.parseFeed(data) else { throw RSSFetchError.parseFailed }
        let articles = normalize(parsedFeed, feedID: feed.id)

        return RSSFetchResult(
            articles: articles, wasNotModified: false,
            etag: responseEtag ?? feed.etag,
            lastModified: responseLastModified ?? feed.lastModified,
            contentHash: contentHash,
            conditionalGetResetAt: newConditionalGetResetAt,
            bytes: data.count)
    }

    // MARK: - Normalization

    func normalize(_ parsedFeed: FeedKit.Feed, feedID: String) -> [Article] {
        let now = Date().sqliteString
        switch parsedFeed {
        case .rss(let rss):
            return normalizeRSS(rss, feedID: feedID, arrived: now)
        case .atom(let atom):
            return normalizeAtom(atom, feedID: feedID, arrived: now)
        case .json(let json):
            return normalizeJSON(json, feedID: feedID, arrived: now)
        }
    }

    private func normalizeRSS(_ feed: RSSFeed, feedID: String, arrived: String) -> [Article] {
        guard let items = feed.channel?.items else { return [] }
        return items.compactMap { item in
            let uniqueID = item.guid?.text ?? item.link ?? UUID().uuidString
            let contentHTML = item.content?.encoded ?? item.description
            let contentText = contentHTML.flatMap { extractText(from: $0) }
            return Article(
                articleID: Article.makeID(feedID: feedID, uniqueID: uniqueID),
                feedID: feedID, uniqueID: uniqueID,
                title: item.title?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).htmlEntitiesDecoded,
                url: item.link,
                contentHTML: contentHTML, contentText: contentText,
                imageURL: ImageExtraction.pick([
                    ImageExtraction.largest((item.media?.contents ?? [])
                        .filter { ($0.attributes?.medium ?? "image") == "image" }
                        .map { (url: $0.attributes?.url, width: $0.attributes?.width) }),
                    ImageExtraction.largest((item.media?.thumbnails ?? []).map { (url: $0.attributes?.url, width: $0.attributes?.width.flatMap(Int.init)) }),
                    item.enclosure?.attributes?.url.flatMap { ($0.hasSuffix(".mp3") || $0.hasSuffix(".m4a")) ? nil : $0 },
                    contentHTML.flatMap(ImageExtraction.firstImageURL(inHTML:)),
                ]),
                author: item.author ?? item.dublinCore?.creator,
                datePublished: item.pubDate?.sqliteString,
                dateArrived: arrived,
                priority: "fyi")
        }
    }

    private func normalizeAtom(_ feed: AtomFeed, feedID: String, arrived: String) -> [Article] {
        guard let entries = feed.entries else { return [] }
        return entries.compactMap { entry in
            let uniqueID = entry.id ?? entry.links?.first?.attributes?.href ?? UUID().uuidString
            let url = entry.links?.first(where: { $0.attributes?.rel == "alternate" })?.attributes?.href
                ?? entry.links?.first?.attributes?.href
            let contentHTML = entry.content?.text ?? entry.summary?.text
            let contentText = contentHTML.flatMap { extractText(from: $0) }
            return Article(
                articleID: Article.makeID(feedID: feedID, uniqueID: uniqueID),
                feedID: feedID, uniqueID: uniqueID,
                title: entry.title?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).htmlEntitiesDecoded,
                url: url,
                contentHTML: contentHTML, contentText: contentText,
                imageURL: ImageExtraction.pick([
                    ImageExtraction.largest((entry.media?.contents ?? []).map { (url: $0.attributes?.url, width: $0.attributes?.width) }),
                    ImageExtraction.largest((entry.media?.thumbnails ?? []).map { (url: $0.attributes?.url, width: $0.attributes?.width.flatMap(Int.init)) }),
                    contentHTML.flatMap(ImageExtraction.firstImageURL(inHTML:)),
                ]),
                author: entry.authors?.first?.name,
                datePublished: (entry.published ?? entry.updated)?.sqliteString,
                dateArrived: arrived,
                priority: "fyi")
        }
    }

    private func normalizeJSON(_ feed: JSONFeed, feedID: String, arrived: String) -> [Article] {
        guard let items = feed.items else { return [] }
        return items.compactMap { item in
            let uniqueID = item.id ?? item.url ?? UUID().uuidString
            let contentHTML = item.contentHtml ?? item.contentText
            let contentText = item.contentText ?? contentHTML.flatMap { extractText(from: $0) }
            return Article(
                articleID: Article.makeID(feedID: feedID, uniqueID: uniqueID),
                feedID: feedID, uniqueID: uniqueID,
                title: item.title?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).htmlEntitiesDecoded,
                url: item.url ?? item.externalURL,
                externalURL: item.externalURL,
                contentHTML: contentHTML, contentText: contentText,
                imageURL: item.image ?? item.bannerImage,
                author: item.author?.name,
                datePublished: item.datePublished?.sqliteString,
                dateArrived: arrived,
                priority: "fyi")
        }
    }

    // MARK: - Helpers

    /// Drops `<?...?>` processing instructions other than the XML declaration. nil when nothing changed.
    /// FeedKit, and on failure one retry with processing instructions removed and named summer-time
    /// zones in the date fields turned into numeric offsets (FeedKit cannot decode "BST"). Polling,
    /// Settings › Add source and `make check-catalog` all parse through here.
    static func parseFeed(_ data: Data) -> FeedKit.Feed? {
        if let first = try? FeedKit.Feed(data: data) { return first }
        var candidate = strippingProcessingInstructions(data) ?? data
        candidate = FeedDateNormalization.numericTimezones(in: candidate) ?? candidate
        return try? FeedKit.Feed(data: candidate)
    }

    static func strippingProcessingInstructions(_ data: Data) -> Data? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        var changed = false
        var out = ""
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("<?"), !trimmed.hasPrefix("<?xml ") {
                changed = true
                continue
            }
            out += line + "\n"
        }
        return changed ? out.data(using: .utf8) : nil
    }

    private func extractText(from html: String) -> String? {
        guard !html.isEmpty else { return nil }
        do {
            let text = try SwiftSoup.parse(html).text()
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
    }
}

enum RSSFetchError: Error, Sendable, LocalizedError {
    case invalidURL(String)
    case notHTTP
    case httpError(Int)
    case parseFailed

    /// Shown verbatim in Settings > Sources, so keep it human.
    var errorDescription: String? {
        switch self {
        case .invalidURL(let url): return "Invalid URL: \(url)"
        case .notHTTP: return "Not an HTTP response"
        case .httpError(let code): return "HTTP \(code)"
        case .parseFailed: return "Feed could not be parsed"
        }
    }
}
