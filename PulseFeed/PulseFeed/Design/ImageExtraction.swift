import Foundation
import SwiftSoup

/// Finds an article's picture where feeds actually put it.
enum ImageExtraction {
    /// The first candidate that is a non-empty URL.
    static func pick(_ candidates: [String?]) -> String? {
        candidates.compactMap { $0 }.first { !$0.isEmpty }
    }

    /// Of several renditions of the same picture, the widest; unsized ones keep feed order and
    /// lose to any sized one. Empty and nil URLs never win.
    static func largest(_ renditions: [(url: String?, width: Int?)]) -> String? {
        let usable = renditions.compactMap { r -> (url: String, width: Int?)? in
            guard let u = r.url, !u.isEmpty else { return nil }
            return (u, r.width)
        }
        guard !usable.isEmpty else { return nil }
        if let widest = usable.filter({ $0.width != nil }).max(by: { ($0.width ?? 0) < ($1.width ?? 0) }) {
            return widest.url
        }
        return usable.first?.url
    }

    /// The first real <img> in an HTML body: skips data: URIs and 1×1 tracking pixels.
    static func firstImageURL(inHTML html: String) -> String? {
        guard !html.isEmpty, html.contains("<img") else { return nil }
        guard let doc = try? SwiftSoup.parse(html), let images = try? doc.select("img") else { return nil }
        for img in images {
            let src = (try? img.attr("src")) ?? ""
            guard src.hasPrefix("http") else { continue }
            let w = (try? img.attr("width")) ?? "", h = (try? img.attr("height")) ?? ""
            if w == "1" || h == "1" { continue }
            return src
        }
        return nil
    }

    /// The page's social card image (og:image, then twitter:image), absolute; a relative value
    /// is resolved against `base` (the article URL) or dropped.
    static func socialImageURL(inHTML html: String, base: URL?) -> String? {
        guard !html.isEmpty, html.contains("<meta") else { return nil }
        guard let doc = try? SwiftSoup.parse(html) else { return nil }
        let selectors = ["meta[property=og:image]", "meta[property=og:image:url]", "meta[name=twitter:image]", "meta[name=twitter:image:src]"]
        for selector in selectors {
            guard let meta = try? doc.select(selector).first() else { continue }
            let content = ((try? meta.attr("content")) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { continue }
            if content.hasPrefix("http") { return content }
            if let base, let resolved = URL(string: content, relativeTo: base)?.absoluteString, resolved.hasPrefix("http") {
                return resolved
            }
        }
        return nil
    }
}
