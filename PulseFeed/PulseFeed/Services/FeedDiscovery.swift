import Foundation
import FeedKit
import SwiftSoup

/// What Settings › Sources › Add source found: enough to show the person a title, the feed's own
/// address and a count before they commit.
struct DiscoveredFeed: Sendable, Equatable {
    let title: String
    let url: URL
    let itemCount: Int
    let format: FeedFormat
}

enum FeedFormat: String, Sendable, Equatable {
    case rss = "RSS"
    case atom = "Atom"
    case json = "JSON Feed"
}

enum DiscoveryError: Error, Equatable, Sendable, LocalizedError {
    /// Not something a URL can be made from.
    case invalidInput
    /// The typed address answered with a transport error or a non-2xx status.
    case unreachable(String)
    /// The typed address answered, but with neither a feed nor an HTML page.
    case notAFeed
    /// The bytes looked like a feed (or were advertised as one) and FeedKit refused them.
    case parseFailed(URL)
    /// An HTML page with no usable `<link rel="alternate">` and none of the common paths.
    case noFeedFound

    /// Shown verbatim in the sheet, so keep it human.
    var errorDescription: String? {
        switch self {
        case .invalidInput: return "Enter a web address or a site name, like theverge.com."
        case .unreachable(let why): return "Could not reach that address (\(why))."
        case .notAFeed: return "That address is not a feed or a web page."
        case .parseFailed(let url): return "Found a feed at \(url.absoluteString) but it could not be parsed."
        case .noFeedFound: return "No feed found on that page. Try pasting the feed's own address."
        }
    }
}

/// Turns what a person types into a feed. The pure parts (`normalize`, `candidates`, `feedLinks`,
/// `looksLikeFeed`, `looksLikeHTML`, `parse`) are unit tested; only `resolve` touches the network.
enum FeedDiscovery {
    /// Where sites usually keep their feed when the page does not say (WordPress, Ghost, Hugo, Jekyll…).
    static let feedPaths = ["/feed", "/feed/", "/rss", "/rss.xml", "/feed.xml", "/atom.xml", "/index.xml", "/?feed=rss2"]

    /// The same browser-shaped User-Agent as FeedEngine's session: some publishers answer a bare
    /// CFNetwork UA with a challenge page instead of the feed.
    static let userAgent = "PulseFeed/1.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Safari/605.1.15"

    /// One session for the sheet: short timeouts, fail fast offline.
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 45
        config.httpAdditionalHeaders = ["User-Agent": userAgent]
        return URLSession(configuration: config)
    }()

    /// Never fetch more than this many addresses for one input.
    static let maxAttempts = 14

    // MARK: - Pure

    /// Trims, accepts a bare domain, adds https://, turns feed: into https:. nil when no URL can be made.
    static func normalize(_ input: String) -> URL? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !s.contains(where: \.isWhitespace) else { return nil }
        let lower = s.lowercased()
        if lower.hasPrefix("feed://") {
            s = "https://" + s.dropFirst("feed://".count)
        } else if lower.hasPrefix("feed:") {
            s = String(s.dropFirst("feed:".count))
        }
        if !s.contains("://") {
            // A bare domain, maybe with a port (localhost:8080) — but not another scheme (mailto:).
            if let colon = s.firstIndex(of: ":") {
                let before = s[..<colon], after = s[s.index(after: colon)...]
                let schemeLike = !before.isEmpty && !before.contains(".") && before.allSatisfy { $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" }
                if schemeLike, !(after.first?.isNumber ?? false) { return nil }
            }
            s = "https://" + s
        }
        guard let components = URLComponents(string: s),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty
        else { return nil }
        return components.url
    }

    /// The typed address first, then the common feed paths under its directory (when it has one),
    /// then under the site root. Fragments are dropped; nothing repeats.
    static func candidates(for input: String) -> [URL] {
        guard var components = normalize(input).flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: true) }) else { return [] }
        components.fragment = nil
        guard let typed = components.url, let scheme = components.scheme, let host = components.host else { return [] }
        var origin = "\(scheme)://\(host)"
        if let port = components.port { origin += ":\(port)" }

        var out: [URL] = [typed]
        var seen: Set<String> = [typed.absoluteString]
        func add(_ string: String) {
            guard let url = URL(string: string), seen.insert(url.absoluteString).inserted else { return }
            out.append(url)
        }

        // Directory of the typed path: "/blog/" stays, "/blog/2026/post" becomes "/blog/2026/".
        let path = components.path
        let directory: String
        if path.hasSuffix("/") {
            directory = path
        } else if let slash = path.lastIndex(of: "/") {
            directory = String(path[...slash])
        } else {
            directory = ""
        }
        if directory.count > 1 {
            for p in feedPaths { add(origin + directory + p.dropFirst()) }
        }
        for p in feedPaths { add(origin + p) }
        return out
    }

    private static let feedLinkTypes: Set<String> = [
        "application/rss+xml", "application/atom+xml", "application/feed+json", "application/rdf+xml",
    ]

    /// `<link rel="alternate" type="application/rss+xml|atom+xml|feed+json" href>` in document
    /// order, relative hrefs resolved against `base` (dropped when there is no base), no repeats.
    static func feedLinks(inHTML html: String, base: URL?) -> [URL] {
        guard !html.isEmpty, html.range(of: "<link", options: .caseInsensitive) != nil,
              let doc = try? SwiftSoup.parse(html), let links = try? doc.select("link")
        else { return [] }
        var out: [URL] = []
        var seen: Set<String> = []
        for link in links {
            let rel = ((try? link.attr("rel")) ?? "").lowercased().split(whereSeparator: \.isWhitespace)
            guard rel.contains("alternate") else { continue }
            let type = ((try? link.attr("type")) ?? "").lowercased().trimmingCharacters(in: .whitespaces)
            guard feedLinkTypes.contains(type) else { continue }
            let href = ((try? link.attr("href")) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !href.isEmpty, let url = URL(string: href, relativeTo: base)?.absoluteURL,
                  let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
                  seen.insert(url.absoluteString).inserted
            else { continue }
            out.append(url)
        }
        return out
    }

    /// The first 4 KB as text, BOM stripped, leading whitespace gone.
    private static func head(_ data: Data) -> Substring {
        let prefix = data.prefix(4096)
        let text = String(decoding: prefix, as: UTF8.self)
        var s = Substring(text)
        if s.hasPrefix("\u{FEFF}") { s = s.dropFirst() }
        return s.drop(while: \.isWhitespace)
    }

    /// The first element name after any XML declaration, processing instructions, comments and DOCTYPE.
    private static func rootElementName(_ s: Substring) -> String? {
        var rest = s
        while let lt = rest.firstIndex(of: "<") {
            rest = rest[lt...]
            if rest.hasPrefix("<?") {
                guard let end = rest.range(of: "?>") else { return nil }
                rest = rest[end.upperBound...]
            } else if rest.hasPrefix("<!--") {
                guard let end = rest.range(of: "-->") else { return nil }
                rest = rest[end.upperBound...]
            } else if rest.hasPrefix("<!") {
                guard let end = rest.firstIndex(of: ">") else { return nil }
                rest = rest[rest.index(after: end)...]
            } else {
                let name = rest.dropFirst().prefix { !$0.isWhitespace && $0 != ">" && $0 != "/" }
                return name.isEmpty ? nil : String(name).lowercased()
            }
        }
        return nil
    }

    /// RSS / Atom / RDF by root element, or a JSON object with an "items" array.
    static func looksLikeFeed(_ data: Data) -> Bool {
        let s = head(data)
        guard let first = s.first else { return false }
        if first == "<" {
            guard let root = rootElementName(s) else { return false }
            return root == "rss" || root == "feed" || root.hasPrefix("rdf")
        }
        if first == "{" {
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            return object["items"] is [Any]
        }
        return false
    }

    /// A DOCTYPE, an <html>, or a <head>/<body>/<link>/<meta> root — the page we should mine for links.
    static func looksLikeHTML(_ data: Data) -> Bool {
        let s = head(data)
        guard s.first == "<" else { return false }
        if s.lowercased().hasPrefix("<!doctype html") { return true }
        guard let root = rootElementName(s) else { return false }
        return ["html", "head", "body", "link", "meta", "div"].contains(root)
    }

    /// FeedKit the way RSSFetcher does it (retrying with <?...?> stripped); the title falls back to
    /// the host when the feed has none. nil when FeedKit refuses the bytes.
    static func parse(_ data: Data, url: URL) -> DiscoveredFeed? {
        guard let parsed = RSSFetcher.parseFeed(data) else { return nil }
        let rawTitle: String?
        let count: Int
        let format: FeedFormat
        switch parsed {
        case .rss(let rss):
            rawTitle = rss.channel?.title
            count = rss.channel?.items?.count ?? 0
            format = .rss
        case .atom(let atom):
            rawTitle = atom.title?.text
            count = atom.entries?.count ?? 0
            format = .atom
        case .json(let json):
            rawTitle = json.title
            count = json.items?.count ?? 0
            format = .json
        }
        let cleaned = rawTitle?.htmlEntitiesDecoded.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return DiscoveredFeed(title: cleaned.isEmpty ? (url.host ?? url.absoluteString) : cleaned, url: url, itemCount: count, format: format)
    }

    // MARK: - Network

    private enum Fetched {
        case ok(Data, URL)
        case failed(String)
    }

    private static func fetch(_ url: URL, session: URLSession) async -> Fetched {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(
            "application/rss+xml, application/atom+xml, application/feed+json, application/xml;q=0.9, text/html;q=0.8, */*;q=0.5",
            forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .failed("not an HTTP response") }
            guard (200..<300).contains(http.statusCode) else { return .failed("HTTP \(http.statusCode)") }
            return .ok(data, http.url ?? url)
        } catch {
            let message = (error as? URLError)?.localizedDescription ?? error.localizedDescription
            return .failed(message.trimmingCharacters(in: CharacterSet(charactersIn: ". ")))
        }
    }

    /// Fetches the typed address; a feed is returned as is, an HTML page is mined for its advertised
    /// feeds and then the common paths are tried, first one that parses wins.
    static func resolve(_ input: String, session: URLSession = FeedDiscovery.session) async -> Result<DiscoveredFeed, DiscoveryError> {
        let typed = candidates(for: input)
        guard let first = typed.first else { return .failure(.invalidInput) }

        var tried: Set<String> = [first.absoluteString]
        let data: Data
        let landed: URL
        switch await fetch(first, session: session) {
        case .failed(let why): return .failure(.unreachable(why))
        case .ok(let d, let url): data = d; landed = url
        }
        tried.insert(landed.absoluteString)

        if looksLikeFeed(data) {
            guard let feed = parse(data, url: landed) else { return .failure(.parseFailed(landed)) }
            return .success(feed)
        }
        // Not sniffed as a feed but FeedKit may still take it (an unusual root, a BOM in the wrong place).
        if let feed = parse(data, url: landed) { return .success(feed) }
        guard looksLikeHTML(data) else { return .failure(.notAFeed) }

        // 1. What the page says about itself, 2. the usual places, computed from where we landed
        //    so a redirect to www. or https:// is honoured.
        let html = String(decoding: data.prefix(512 * 1024), as: UTF8.self)
        let advertised = feedLinks(inHTML: html, base: landed)
        let usual = candidates(for: landed.absoluteString).dropFirst()
        var firstUnparsable: URL?
        for url in advertised + Array(usual) {
            guard tried.count < maxAttempts, tried.insert(url.absoluteString).inserted else { continue }
            guard case .ok(let bytes, let at) = await fetch(url, session: session) else { continue }
            if let feed = parse(bytes, url: at) { return .success(feed) }
            if firstUnparsable == nil, looksLikeFeed(bytes) { firstUnparsable = at }
        }
        if let firstUnparsable { return .failure(.parseFailed(firstUnparsable)) }
        return .failure(.noFeedFound)
    }
}
