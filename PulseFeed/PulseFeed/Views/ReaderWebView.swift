import SwiftUI
import WebKit

/// Reader colours per design: dark for Native Pro and Deck, light with coral links for Stream.
enum ReaderTheme: Sendable {
    case dark(link: String)
    case light(link: String)

    var cssVariables: String {
        switch self {
        case .dark(let link):
            return """
            --bg: #1c1c1e; --text: #d4d4d4; --title: #f5f5f7; --meta: #8e8e93; --link: \(link);
            --border: #3a3a3c; --quote-bg: rgba(255,255,255,0.03); --quote-border: #555;
            --code-bg: #2c2c2e; --strong: #f0f0f0; --h3: #e8e8e8;
            """
        case .light(let link):
            return """
            --bg: #FFFFFF; --text: #2A2C31; --title: #17181C; --meta: #6B7079; --link: \(link);
            --border: #E3E5E9; --quote-bg: rgba(0,0,0,0.03); --quote-border: #C9CED8;
            --code-bg: #F1F2F4; --strong: #17181C; --h3: #17181C;
            """
        }
    }
}

struct ReaderWebView: NSViewRepresentable {
    let url: URL
    @Binding var isReaderMode: Bool
    var theme: ReaderTheme = .dark(link: "#6db3f2")
    var onTextExtracted: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(isReaderMode: $isReaderMode, onTextExtracted: onTextExtracted, theme: theme)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let ucc = WKUserContentController()

        // 1. Inject Readability.js library at document end
        if let readerableJS = Self.loadBundledJS(named: "Readability-readerable"),
           let readabilityJS = Self.loadBundledJS(named: "Readability") {
            let libScript = WKUserScript(
                source: readerableJS + "\n" + readabilityJS,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            ucc.addUserScript(libScript)
        }

        // 2. Inject the extraction + MutationObserver script
        let extractionScript = WKUserScript(
            source: Self.extractionJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        ucc.addUserScript(extractionScript)

        // 3. Add pre-compiled ad-blocking content rules
        if let adBlockRules = AppDelegate.adBlockRuleList {
            ucc.add(adBlockRules)
        }

        // 4. Register message handler
        ucc.add(context.coordinator, name: "readerContent")
        config.userContentController = ucc

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if !isReaderMode && context.coordinator.hasRenderedReader {
            // User toggled to "Show Original" — reload the raw page
            context.coordinator.hasRenderedReader = false
            webView.load(URLRequest(url: url))
        } else if webView.url != url {
            context.coordinator.hasRenderedReader = false
            webView.load(URLRequest(url: url))
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var webView: WKWebView?
        var isReaderMode: Binding<Bool>
        var hasRenderedReader = false
        var onTextExtracted: ((String) -> Void)?
        let theme: ReaderTheme

        init(isReaderMode: Binding<Bool>, onTextExtracted: ((String) -> Void)?, theme: ReaderTheme) {
            self.isReaderMode = isReaderMode
            self.onTextExtracted = onTextExtracted
            self.theme = theme
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Extraction is triggered automatically by the injected JS
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "readerContent",
                  !hasRenderedReader,
                  isReaderMode.wrappedValue,
                  let json = message.body as? String,
                  let data = json.data(using: .utf8),
                  let article = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let title = article["title"] as? String,
                  let content = article["content"] as? String
            else { return }

            hasRenderedReader = true

            let byline = article["byline"] as? String ?? ""
            let siteName = article["siteName"] as? String ?? ""

            // Report extracted plain text for TTS
            if let textContent = article["textContent"] as? String, !textContent.isEmpty {
                onTextExtracted?(textContent)
            }

            let styledHTML = Self.buildReaderHTML(
                title: title,
                byline: byline,
                siteName: siteName,
                content: content,
                baseURL: webView?.url ?? URL(string: "about:blank")!,
                theme: theme
            )

            webView?.loadHTMLString(styledHTML, baseURL: webView?.url)
        }

        static func buildReaderHTML(
            title: String, byline: String, siteName: String,
            content: String, baseURL: URL, theme: ReaderTheme = .dark(link: "#6db3f2")
        ) -> String {
            let safeTitle = title
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            let safeByline = byline
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            let safeSiteName = siteName
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")

            return """
            <!DOCTYPE html>
            <html>
            <head>
                <meta charset="utf-8">
                <meta name="viewport" content="width=device-width, initial-scale=1">
                <base href="\(baseURL.absoluteString)">
                <style>
                    :root { \(theme.cssVariables) }
                    * { margin: 0; padding: 0; box-sizing: border-box; }
                    body {
                        font: 19px/1.65 Charter, 'Iowan Old Style', Palatino, Georgia, serif;
                        max-width: 680px;
                        margin: 0 auto;
                        padding: 40px 32px 80px;
                        background: var(--bg);
                        color: var(--text);
                        -webkit-font-smoothing: antialiased;
                    }
                    .reader-header {
                        margin-bottom: 32px;
                        padding-bottom: 24px;
                        border-bottom: 1px solid var(--border);
                    }
                    h1 {
                        font-family: -apple-system, 'SF Pro Display', sans-serif;
                        font-size: 32px;
                        font-weight: 700;
                        line-height: 1.2;
                        color: var(--title);
                        margin-bottom: 12px;
                    }
                    .reader-meta {
                        font-family: -apple-system, sans-serif;
                        font-size: 14px;
                        color: var(--meta);
                    }
                    .reader-meta span { margin-right: 12px; }
                    h2 {
                        font-family: -apple-system, sans-serif;
                        font-size: 24px; font-weight: 600;
                        margin: 32px 0 12px; color: var(--title);
                    }
                    h3, h4 {
                        font-family: -apple-system, sans-serif;
                        font-weight: 600;
                        margin: 24px 0 8px; color: var(--h3);
                    }
                    p { margin-bottom: 18px; }
                    img {
                        max-width: 100%; height: auto;
                        display: block;
                        margin: 24px auto;
                        border-radius: 6px;
                    }
                    figure { margin: 24px 0; }
                    figcaption {
                        font-family: -apple-system, sans-serif;
                        font-size: 13px; color: var(--meta);
                        text-align: center; margin-top: 8px;
                    }
                    a { color: var(--link); text-decoration: none; }
                    a:hover { text-decoration: underline; }
                    blockquote {
                        border-left: 4px solid var(--quote-border);
                        background: var(--quote-bg);
                        padding: 12px 20px;
                        margin: 20px 0;
                        font-style: italic;
                        border-radius: 0 6px 6px 0;
                    }
                    pre, code {
                        font-family: 'SF Mono', Menlo, monospace;
                        background: var(--code-bg);
                        border-radius: 4px;
                        font-size: 0.85em;
                    }
                    pre { padding: 16px; overflow-x: auto; margin: 20px 0; }
                    code { padding: 2px 6px; }
                    pre code { padding: 0; background: none; }
                    ul, ol { margin: 18px 0; padding-left: 28px; }
                    li { margin-bottom: 8px; }
                    strong, b { color: var(--strong); }
                    hr { border: none; border-top: 1px solid var(--border); margin: 32px 0; }
                    table { border-collapse: collapse; width: 100%; margin: 20px 0; }
                    th, td {
                        padding: 8px 12px;
                        border: 1px solid var(--border);
                        text-align: left;
                    }
                    th { background: var(--code-bg); }
                    iframe, video {
                        max-width: 100%;
                        border-radius: 6px;
                        margin: 20px 0;
                    }
                    .ad, .ads, .social, .share, .newsletter, .popup,
                    .cookie, .related, .recommended, .promo, .sponsored,
                    nav, .nav, [role="navigation"] {
                        display: none !important;
                    }
                </style>
            </head>
            <body>
                <div class="reader-header">
                    <h1>\(safeTitle)</h1>
                    <div class="reader-meta">
                        \(safeByline.isEmpty ? "" : "<span>\(safeByline)</span>")
                        \(safeSiteName.isEmpty ? "" : "<span>\(safeSiteName)</span>")
                    </div>
                </div>
                \(content)
            </body>
            </html>
            """
        }
    }

    // MARK: - Load Bundled JS Files

    static func loadBundledJS(named name: String) -> String? {
        if let path = Bundle.main.path(forResource: name, ofType: "js") {
            return try? String(contentsOfFile: path, encoding: .utf8)
        }
        if let path = Bundle.main.path(forResource: name, ofType: "js", inDirectory: "JS") {
            return try? String(contentsOfFile: path, encoding: .utf8)
        }
        if let resourcePath = Bundle.main.resourcePath {
            let jsPath = (resourcePath as NSString).appendingPathComponent("JS/\(name).js")
            if FileManager.default.fileExists(atPath: jsPath) {
                return try? String(contentsOfFile: jsPath, encoding: .utf8)
            }
        }
        print("PulseFeed: [Reader] WARNING: Could not load \(name).js from bundle")
        return nil
    }

    // MARK: - Extraction JavaScript

    static let extractionJS: String = """
    (function() {
        var parsed = false;

        function fixLazyImages() {
            document.querySelectorAll('img').forEach(function(img) {
                var dataSrc = img.getAttribute('data-src')
                    || img.getAttribute('data-lazy-src')
                    || img.getAttribute('data-original');
                if (dataSrc && !img.src) {
                    img.src = dataSrc;
                }
            });
            document.querySelectorAll('[loading="lazy"]').forEach(function(el) {
                el.loading = 'eager';
            });
        }

        function tryParse() {
            if (parsed) return true;
            if (typeof Readability === 'undefined') return false;

            if (typeof isProbablyReaderable !== 'undefined' && !isProbablyReaderable(document)) {
                return false;
            }

            fixLazyImages();

            var clone = document.cloneNode(true);
            var article = new Readability(clone, {
                charThreshold: 100
            }).parse();

            if (article && article.content && article.textContent && article.textContent.length > 200) {
                parsed = true;
                window.webkit.messageHandlers.readerContent.postMessage(
                    JSON.stringify({
                        title: article.title || '',
                        content: article.content || '',
                        textContent: article.textContent || '',
                        byline: article.byline || '',
                        excerpt: article.excerpt || '',
                        siteName: article.siteName || '',
                        length: article.length || 0,
                        publishedTime: article.publishedTime || ''
                    })
                );
                return true;
            }
            return false;
        }

        setTimeout(function() {
            if (!tryParse()) {
                setTimeout(function() {
                    if (!tryParse()) {
                        if (document.body) {
                            var observer = new MutationObserver(function(mutations) {
                                if (tryParse()) {
                                    observer.disconnect();
                                }
                            });
                            observer.observe(document.body, {
                                childList: true,
                                subtree: true
                            });
                            setTimeout(function() {
                                observer.disconnect();
                                tryParse();
                            }, 10000);
                        }
                    }
                }, 1500);
            }
        }, 500);
    })();
    """

    // MARK: - Ad Block Rules

    static let adBlockRulesJSON: String = """
    [
        {
            "trigger": {
                "url-filter": ".*",
                "resource-type": ["script", "image", "raw"],
                "if-domain": [
                    "*doubleclick.net", "*googlesyndication.com",
                    "*google-analytics.com", "*googletagmanager.com",
                    "*facebook.net", "*amazon-adsystem.com",
                    "*taboola.com", "*outbrain.com", "*criteo.com",
                    "*adnxs.com", "*rubiconproject.com",
                    "*pubmatic.com", "*openx.net",
                    "*moatads.com", "*adsrvr.org"
                ]
            },
            "action": { "type": "block" }
        },
        {
            "trigger": { "url-filter": ".*" },
            "action": {
                "type": "css-display-none",
                "selector": ".ad, .ads, .adsbygoogle, [class*='ad-container'], [class*='ad-wrapper'], .sponsored-content, .cookie-banner, .cookie-consent, .newsletter-popup, .newsletter-signup, [class*='paywall'], [class*='subscription'], [id*='cookie'], [class*='consent']"
            }
        }
    ]
    """
}
