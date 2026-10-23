import Foundation

struct OPMLService: Sendable {

    // MARK: - Export

    static let exportTitle = "News Feed subscriptions"
    /// Titles this app's exports have carried (the first one before the on/off attribute existed).
    static let ownTitles: Set<String> = [exportTitle, "XBTDMT Feed Subscriptions"]

    /// Whether the file is one of this app's own exports (by its title).
    static func isOwnExport(_ data: Data) -> Bool {
        guard let doc = try? XMLDocument(data: data),
              let title = (try? doc.nodes(forXPath: "//head/title"))?.first?.stringValue else { return false }
        return ownTitles.contains(title.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Generate OPML XML string from feeds
    func exportOPML(feeds: [Feed]) -> String {
        var xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <opml version="2.0">
            <head><title>\(Self.exportTitle)</title></head>
            <body>

            """

        // Group by category
        let grouped = Dictionary(grouping: feeds, by: \.category)
        for (category, categoryFeeds) in grouped.sorted(by: { $0.key < $1.key }) {
            xml += "  <outline text=\"\(escapeXML(category))\">\n"
            for feed in categoryFeeds {
                xml += "    <outline type=\"rss\""
                xml += " text=\"\(escapeXML(feed.title))\""
                xml += " xmlUrl=\"\(escapeXML(feed.url))\""
                if let home = feed.homePageURL {
                    xml += " htmlUrl=\"\(escapeXML(home))\""
                }
                xml += " category=\"\(escapeXML(feed.category))\""
                // Whether the source is on, so re-importing this file restores the state instead of
                // switching everything on (other readers ignore an attribute they do not know).
                xml += " pulsefeedEnabled=\"\(feed.isEnabled ? 1 : 0)\""
                xml += "/>\n"
            }
            xml += "  </outline>\n"
        }

        xml += "</body>\n</opml>\n"
        return xml
    }

    // MARK: - Import

    struct OPMLFeed: Sendable {
        let title: String
        let url: String
        let homePageURL: String?
        let category: String
        /// From this app's own export (`pulsefeedEnabled`); nil in any other reader's file.
        var enabled: Bool? = nil
    }

    /// Parse OPML XML data into feed entries. Handles malformed XML gracefully.
    func parseOPML(data: Data) -> [OPMLFeed] {
        guard let doc = try? XMLDocument(data: data) else { return [] }
        guard let body = try? doc.nodes(forXPath: "//body") else { return [] }

        var feeds: [OPMLFeed] = []
        let outlines = (try? doc.nodes(forXPath: "//outline[@xmlUrl]")) ?? []

        for node in outlines {
            guard let element = node as? XMLElement,
                let xmlUrl = element.attribute(forName: "xmlUrl")?.stringValue,
                !xmlUrl.isEmpty
            else { continue }

            let title = element.attribute(forName: "text")?.stringValue
                ?? element.attribute(forName: "title")?.stringValue
                ?? xmlUrl

            let htmlUrl = element.attribute(forName: "htmlUrl")?.stringValue

            // Try to get category from attribute, or from parent outline's text
            let category = element.attribute(forName: "category")?.stringValue
                ?? (element.parent as? XMLElement)?.attribute(forName: "text")?.stringValue
                ?? "general"

            let enabled = element.attribute(forName: "pulsefeedEnabled")?.stringValue.map { $0 == "1" }

            feeds.append(OPMLFeed(
                title: title, url: xmlUrl, homePageURL: htmlUrl, category: category.lowercased(), enabled: enabled))
        }

        // Suppress warning for unused `body`
        _ = body
        return feeds
    }

    // MARK: - Private

    private func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
