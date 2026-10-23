import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// `make showcase`'s last step (the Stream run, the last of the three): the renders in the output folder laid
/// out as the README's pictures (`composed/`), the Look step's thumbnails (`composed/look-*.png`, written first
/// by `thumbnails(in:)` so the welcome renders of the same run show them) and the X post set (`x-post/`, with
/// the welcome flow as an MP4). Composition only: each render is drawn whole or cropped, on a soft light
/// ground, with rounded corners and a real drop shadow; captions are the system font through
/// `NSAttributedString`; nothing is drawn over a render's pixels.
@MainActor
enum ShowcaseComposer {
    enum ComposeError: Error { case missing(String), encode(String), video(String), tooLarge(String, Int) }

    // MARK: Inputs

    /// The welcome window's footer (step dots, Back / Skip / Next) starts here in the 2× render; no crop
    /// reaches it, so the footer's inactive default button never shows.
    static let welcomeContentHeight = 1148
    /// A welcome screen is cut at most this far down, in the lowest gap between rows of content above it.
    static let welcomeCropLimit = 1060

    @MainActor
    struct Renders {
        let popovers: [AppDesign: CGImage]
        let windows: [AppDesign: CGImage]
        /// welcome-0…6, each cropped below its own content (`contentCrop`), never through a row of it.
        let welcome: [CGImage]
        /// (state, light bar, dark bar)
        let menuBar: [(String, CGImage, CGImage)]

        init(dir: URL) throws {
            var pops: [AppDesign: CGImage] = [:], wins: [AppDesign: CGImage] = [:]
            for d in AppDesign.allCases {
                pops[d] = try ShowcaseComposer.load(dir, "\(d.rawValue)-popover.png")
                wins[d] = try ShowcaseComposer.load(dir, "\(d.rawValue)-window.png")
            }
            popovers = pops
            windows = wins
            welcome = try WelcomeStep.allCases.map { step in
                let full = try ShowcaseComposer.load(dir, "welcome-\(step.rawValue).png")
                let bottom = ShowcaseComposer.contentCrop(full, limit: min(ShowcaseComposer.welcomeCropLimit, ShowcaseComposer.welcomeContentHeight))
                guard let cropped = full.cropping(to: CGRect(x: 0, y: 0, width: full.width, height: bottom)) else {
                    throw ComposeError.missing("welcome-\(step.rawValue) crop")
                }
                return cropped
            }
            menuBar = try ["idle", "new-count", "breaking-dot"].map {
                ($0, try ShowcaseComposer.load(dir, "menubar-\($0).png"), try ShowcaseComposer.load(dir, "menubar-\($0)-dark.png"))
            }
        }
    }

    static func load(_ dir: URL, _ name: String) throws -> CGImage {
        let url = dir.appendingPathComponent(name)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ComposeError.missing(name) }
        return image
    }

    /// A render's pixels as 8-bit sRGB RGBA, top row first.
    struct Pixels {
        let width: Int, height: Int
        let bytes: [UInt8]
        init?(_ image: CGImage) {
            width = image.width
            height = image.height
            var buffer = [UInt8](repeating: 0, count: width * height * 4)
            let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
                guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                      let ctx = CGContext(data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                          bytesPerRow: image.width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                return true
            }
            guard drawn else { return nil }
            bytes = buffer
        }
        func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let i = (y * width + x) * 4
            return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
        }
        static func near(_ a: (Int, Int, Int), _ b: (Int, Int, Int), _ tolerance: Int = 2) -> Bool {
            abs(a.0 - b.0) <= tolerance && abs(a.1 - b.1) <= tolerance && abs(a.2 - b.2) <= tolerance
        }

        /// The welcome window's grounds: its own on the left, the preview pane's on the right (from `split`),
        /// and the divider's columns between them, read from a row of the top margin.
        func grounds() -> (left: (Int, Int, Int), right: (Int, Int, Int), split: Int, divider: Range<Int>) {
            let left = rgb(12, 12), right = rgb(width - 12, 12)
            guard !Self.near(left, right, 1) else { return (left, right, width, width..<width) }
            var split = width
            for x in (width / 2)..<width where Self.near(rgb(x, 12), right, 1) && !Self.near(rgb(x, 12), left, 1) {
                split = x
                break
            }
            var start = split
            while start > width / 2, !Self.near(rgb(start - 1, 12), left, 1) { start -= 1 }
            return (left, right, split, start..<split)
        }

        /// A row holding only the grounds (no text, control or card).
        func isBlank(_ y: Int, _ g: (left: (Int, Int, Int), right: (Int, Int, Int), split: Int, divider: Range<Int>)) -> Bool {
            for x in 0..<width where !g.divider.contains(x) {
                if !Self.near(rgb(x, y), x < g.split ? g.left : g.right) { return false }
            }
            return true
        }
    }

    /// Where to cut a welcome screen: `padding` below its last content when that ends above `limit`; else in
    /// the lowest gap of at least `minGap` blank rows above `limit`. Gaps that wide fall between sections, not
    /// between a heading and its chips or two lines of one block, so nothing is cut through or left dangling.
    static func contentCrop(_ image: CGImage, limit: Int, padding: Int = 44, minGap: Int = 28) -> Int {
        guard let px = Pixels(image) else { return min(limit, image.height) }
        let g = px.grounds()
        let end = min(limit, px.height)
        let blank = (0..<end).map { px.isBlank($0, g) }
        guard let last = blank.lastIndex(of: false) else { return end }
        if last + padding < end { return last + padding }
        // Content runs into the limit: walk up to the lowest gap wide enough to sit between two rows.
        var y = end - 1
        while y > 0 {
            while y > 0, !blank[y] { y -= 1 }
            var top = y
            while top > 0, blank[top - 1] { top -= 1 }
            if y - top + 1 >= minGap { return min(top + padding, y + 1) }
            y = top - 1
        }
        return end
    }

    /// The rightmost content column left of the preview pane (or of the window) within `rows`.
    static func contentRight(_ image: CGImage, rows: ClosedRange<Int>, padding: Int = 56) -> Int {
        guard let px = Pixels(image) else { return image.width }
        let g = px.grounds()
        var right = 0
        for y in rows.clamped(to: 0...(px.height - 1)) {
            var x = min(g.divider.lowerBound, g.split) - 1
            while x > right, Pixels.near(px.rgb(x, y), g.left) { x -= 1 }
            right = max(right, x)
        }
        return min(right + padding, min(g.divider.lowerBound, g.split))
    }

    /// The runs of rows holding content (anything but the ground) in the step's own column, left of the
    /// preview pane, within the top `rows`, top to bottom.
    static func contentBands(_ image: CGImage, rows: Int) -> [ClosedRange<Int>] {
        guard let px = Pixels(image) else { return [] }
        let g = px.grounds()
        let columnEnd = min(g.divider.lowerBound, g.split)
        var bands: [ClosedRange<Int>] = []
        var start: Int?
        for y in 0..<min(rows, px.height) {
            let blank = (0..<columnEnd).allSatisfy { Pixels.near(px.rgb($0, y), g.left) }
            if !blank, start == nil { start = y }
            if blank, let s = start { bands.append(s...(y - 1)); start = nil }
        }
        if let s = start { bands.append(s...(min(rows, px.height) - 1)) }
        return bands
    }

    /// The Alerts step's rows the X picture keeps: from "Breaking + recap" (the band just above the first
    /// banner, the first band 80 px or taller) to the recap interval (the band above the last, which is the
    /// notifications row), padded by up to `padding` but never into a band it leaves out. Nil when the bands
    /// do not look like that step.
    static func alertsDetailRows(bands: [ClosedRange<Int>], padding: Int = 40) -> ClosedRange<Int>? {
        guard let banner = bands.firstIndex(where: { $0.count >= 80 }), banner >= 1, bands.count >= banner + 3 else { return nil }
        let first = bands[banner - 1], last = bands[bands.count - 2], after = bands[bands.count - 1]
        let above = banner >= 2 ? bands[banner - 2].upperBound + 1 : 0
        return max(above, first.lowerBound - padding)...min(after.lowerBound - 1, last.upperBound + padding)
    }

    // MARK: The set

    static func composedDirectory(_ dir: URL) -> URL { dir.appendingPathComponent("composed", isDirectory: true) }

    /// The Look step's three thumbnails, written first (into a fresh `composed/`) so the same run's welcome
    /// renders show them.
    static func thumbnails(in dir: URL) throws -> [URL] {
        let composed = composedDirectory(dir)
        try? FileManager.default.removeItem(at: composed)
        try FileManager.default.createDirectory(at: composed, withIntermediateDirectories: true)
        return try AppDesign.allCases.map { d in
            let url = composed.appendingPathComponent("\(LookThumbnail.resourceName(for: d)).png")
            try writePNG(lookThumbnail(load(dir, "\(d.rawValue)-popover.png")), to: url)
            return url
        }
    }

    /// Writes every other composed picture and returns their paths.
    static func compose(in dir: URL) throws -> [URL] {
        let renders = try Renders(dir: dir)
        let composed = composedDirectory(dir)
        let xPost = dir.appendingPathComponent("x-post", isDirectory: true)
        try? FileManager.default.removeItem(at: xPost)
        for folder in [composed, xPost] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        var written: [URL] = []
        func png(_ image: CGImage, _ folder: URL, _ name: String) throws {
            let url = folder.appendingPathComponent(name)
            try writePNG(image, to: url)
            written.append(url)
        }

        let card = try socialCard(renders)
        let designsImage = try designs(renders, width: 2400)

        // The README's pictures.
        try png(hero(renders, width: 2400, height: 1400), composed, "hero.png")
        try png(designsImage, composed, "designs.png")
        for d in AppDesign.allCases {
            try png(window(renders.windows[d]!, width: 2400), composed, "window-\(d.rawValue).png")
        }
        try png(menuBarStates(renders), composed, "menubar-states.png")
        try png(card, composed, "social-card-1200x675.png")
        let gif = composed.appendingPathComponent("welcome.gif")
        try writeGIF(welcomeSlides(renders, width: 1600, maxHeight: nil, dots: true, flat: true).map { try flatten($0) }, delay: 3, to: gif)
        written.append(gif)

        // The X post set: 16:9 where it matters, every picture at least 1600 px wide except the card.
        try png(card, xPost, "1-social-card.png")
        try png(hero(renders, width: 2400, height: 1350), xPost, "2-hero.png")
        try png(alertsSlide(renders), xPost, "3-welcome.png")
        try png(designs(renders, width: 2400, height: 1350), xPost, "4-three-looks.png")
        try png(window(renders.windows[.deck]!, width: 2400, height: 1350), xPost, "5-window.png")
        try png(menuBarStates(renders, canvas: CGSize(width: 1600, height: 900)), xPost, "6-menubar.png")
        let video = xPost.appendingPathComponent("welcome.mp4")
        try writeVideo(welcomeSlides(renders, width: 1600, maxHeight: 900, dots: false), to: video)
        written.append(video)
        return written
    }

    // MARK: Pictures

    /// The Deck popover beside the welcome flow's Topics step (with its live preview); the popover a little
    /// larger than life, as the subject.
    static func hero(_ r: Renders, width: Int, height: Int) throws -> CGImage {
        let pop = r.popovers[.deck]!, topics = r.welcome[WelcomeStep.topics.rawValue]
        let w = CGFloat(width), h = CGFloat(height)
        let marginX = w * 0.05, marginY = h * 0.085, gap = w * 0.04, boost: CGFloat = 1.15
        let s = min((w - 2 * marginX - gap) / (CGFloat(pop.width) * boost + CGFloat(topics.width)),
                    (h - 2 * marginY) / (CGFloat(pop.height) * boost))
        let popSize = CGSize(width: CGFloat(pop.width) * boost * s, height: CGFloat(pop.height) * boost * s)
        let topSize = CGSize(width: CGFloat(topics.width) * s, height: CGFloat(topics.height) * s)
        let x0 = (w - popSize.width - gap - topSize.width) / 2
        return try canvas(width: width, height: height) {
            drawCard(pop, in: NSRect(origin: CGPoint(x: x0, y: (h - popSize.height) / 2), size: popSize),
                     radius: 12 * 2 * boost * s)
            drawCard(topics, in: NSRect(origin: CGPoint(x: x0 + popSize.width + gap, y: (h - topSize.height) / 2), size: topSize),
                     radius: 14 * 2 * s)
        }
    }

    static let designLines: [AppDesign: String] = [
        .nativePro: "System materials and a markets strip",
        .deck: "Glance-first tiles, one click to any story",
        .stream: "Pictures where they earn their place",
    ]

    /// The three popovers at one scale, bottoms aligned, each captioned with its name and one line. With
    /// `height` (16:9 for X, which crops other shapes), the set is scaled to fit that frame and centred.
    static func designs(_ r: Renders, width: Int, height fixedHeight: Int? = nil) throws -> CGImage {
        let order: [AppDesign] = [.nativePro, .deck, .stream]
        let w = CGFloat(width)
        let gapRatio: CGFloat = 0.045, top = w * 0.05, bottom = w * 0.045
        let nameSize = w * 0.02, lineSize = w * 0.0135
        let captions = order.map { d in
            (text(d.displayName, size: nameSize, weight: .semibold),
             text(designLines[d]!, size: lineSize, color: secondaryInk))
        }
        let totalWidth = order.reduce(CGFloat(0)) { $0 + CGFloat(r.popovers[$1]!.width) }
        let maxHeight = order.map { CGFloat(r.popovers[$0]!.height) }.max()!
        var s = (w - 2 * w * 0.06 - 2 * w * gapRatio) / totalWidth
        let captionBlock = w * 0.024 + captions.map { height($0.0, width: w / 3) + nameSize * 0.3 + height($0.1, width: w / 3) }.max()!
        if let fixedHeight { s = min(s, (CGFloat(fixedHeight) - top - bottom - captionBlock) / maxHeight) }
        let gap = w * gapRatio
        let marginX = (w - totalWidth * s - 2 * gap) / 2
        let tallest = maxHeight * s
        let h = fixedHeight.map(CGFloat.init) ?? (top + tallest + captionBlock + bottom)
        let topY = fixedHeight == nil ? top : (h - tallest - captionBlock) / 2
        let captionTop = topY + tallest + w * 0.024
        return try canvas(width: width, height: Int(h.rounded())) {
            var x = marginX
            for (i, d) in order.enumerated() {
                let img = r.popovers[d]!
                let size = CGSize(width: CGFloat(img.width) * s, height: CGFloat(img.height) * s)
                drawCard(img, in: NSRect(x: x, y: topY + tallest - size.height, width: size.width, height: size.height),
                         radius: 12 * 2 * s)
                let (name, line) = captions[i]
                let nameHeight = height(name, width: size.width)
                draw(name, in: NSRect(x: x, y: captionTop, width: size.width, height: nameHeight))
                draw(line, in: NSRect(x: x, y: captionTop + nameHeight + nameSize * 0.3, width: size.width,
                                      height: height(line, width: size.width)))
                x += size.width + gap
            }
        }
    }

    /// One main window on the ground; with `height`, fitted into that frame (16:9 for X) instead.
    static func window(_ img: CGImage, width: Int, height: Int? = nil) throws -> CGImage {
        let w = CGFloat(width), margin = w * 0.05
        var s = (w - 2 * margin) / CGFloat(img.width)
        let h: CGFloat
        if let height {
            h = CGFloat(height)
            s = min(s, (h - 2 * margin * 0.8) / CGFloat(img.height))
        } else {
            h = (CGFloat(img.height) * s + margin * 2.1).rounded()
        }
        let size = CGSize(width: CGFloat(img.width) * s, height: CGFloat(img.height) * s)
        return try canvas(width: width, height: Int(h)) {
            drawCard(img, in: NSRect(x: (w - size.width) / 2, y: (h - size.height) / 2 - (height == nil ? margin * 0.05 : 0),
                                     width: size.width, height: size.height),
                     radius: 14 * 2 * s)
        }
    }

    static let menuBarTitle = "News Feed in your menu bar"
    static let menuBarSubtitle = "What\u{2019}s new since you last looked, and a red dot when the model rates a story breaking."

    static let menuBarLabels: [String: String] = [
        "idle": "Nothing new",
        "new-count": "12 new since you last looked",
        "breaking-dot": "An unread story rated breaking",
    ]

    /// The menu bar item's three states on a light and a dark bar, as Battery's README shows its own. With
    /// `canvas` (16:9 for X), the table is centred in that frame under a title line.
    static func menuBarStates(_ r: Renders, canvas frame: CGSize? = nil) throws -> CGImage {
        let labelSize: CGFloat = 44, headerSize: CGFloat = 36
        let labels = r.menuBar.map { text(menuBarLabels[$0.0] ?? $0.0, size: labelSize, align: .left) }
        let labelWidth = labels.map { $0.size().width }.max()!.rounded(.up)
        let pill = CGSize(width: CGFloat(r.menuBar[0].1.width), height: CGFloat(r.menuBar[0].1.height))
        let colGap: CGFloat = 56, rowGap: CGFloat = 40, labelGap: CGFloat = 96, headerGap: CGFloat = 44
        let tableWidth = labelWidth + labelGap + pill.width * 2 + colGap
        let headers = [text("Light menu bar", size: headerSize, color: secondaryInk),
                       text("Dark menu bar", size: headerSize, color: secondaryInk)]
        let headerHeight = height(headers[0], width: pill.width + colGap)
        let tableHeight = headerHeight + headerGap + CGFloat(r.menuBar.count) * pill.height + CGFloat(r.menuBar.count - 1) * rowGap
        let title = frame == nil ? nil : text(menuBarTitle, size: 60, weight: .bold)
        let subtitle = frame == nil ? nil : text(menuBarSubtitle, size: 34, color: secondaryInk)
        let size = frame ?? CGSize(width: max(1640, tableWidth + 240), height: tableHeight + 240)
        let titleWidth = size.width - 200
        let titleBlock = title.map { height($0, width: titleWidth) + 14 + height(subtitle!, width: titleWidth) + 70 } ?? 0
        let top = (size.height - titleBlock - tableHeight) / 2
        let left = (size.width - tableWidth) / 2
        return try canvas(width: Int(size.width), height: Int(size.height.rounded())) {
            if let title, let subtitle {
                let th = height(title, width: titleWidth)
                draw(title, in: NSRect(x: 100, y: top, width: titleWidth, height: th))
                draw(subtitle, in: NSRect(x: 100, y: top + th + 14, width: titleWidth, height: height(subtitle, width: titleWidth)))
            }
            let tableTop = top + titleBlock
            let colX = [left + labelWidth + labelGap, left + labelWidth + labelGap + pill.width + colGap]
            for (i, header) in headers.enumerated() {
                draw(header, in: NSRect(x: colX[i] - colGap / 2, y: tableTop, width: pill.width + colGap, height: headerHeight))
            }
            let rowsTop = tableTop + headerHeight + headerGap
            for (row, state) in r.menuBar.enumerated() {
                let y = rowsTop + CGFloat(row) * (pill.height + rowGap)
                let labelHeight = height(labels[row], width: labelWidth)
                draw(labels[row], in: NSRect(x: left, y: y + (pill.height - labelHeight) / 2, width: labelWidth, height: labelHeight))
                drawCard(state.1, in: NSRect(x: colX[0], y: y, width: pill.width, height: pill.height), radius: 22, shadowScale: 0.5)
                drawCard(state.2, in: NSRect(x: colX[1], y: y, width: pill.width, height: pill.height), radius: 22, shadowScale: 0.5)
            }
        }
    }

    static let stepCaptions: [(String, String)] = [
        ("Make it yours", "about a minute, and all of it can change later"),
        ("Topics", "type what you\u{2019}re into, start from a pack, or tick topics"),
        ("Sources", "the outlets your topics turn on"),
        ("Follow", "people and teams that may break through as alerts"),
        ("Alerts", "breaking news interrupts; the rest waits for one recap"),
        ("Look", "three designs, light or dark, and the prices you want"),
        ("You\u{2019}re set", "look for the X in your menu bar"),
    ]

    static func stepCaption(_ step: Int, size: CGFloat) -> NSAttributedString {
        let caption = NSMutableAttributedString(attributedString: text("Step \(step + 1) of \(stepCaptions.count)   ", size: size, color: secondaryInk))
        caption.append(text(stepCaptions[step].0, size: size, weight: .semibold))
        caption.append(text(": " + stepCaptions[step].1, size: size, color: secondaryInk))
        return centered(caption)
    }

    /// One welcome screen as two layers: the card on the ground (opaque) and its caption, with step dots for
    /// the GIF (transparent), so the clip can cross-fade the cards and cut the captions. Every screen is drawn
    /// at one scale (text stays the same size from screen to screen), centred above a fixed caption line.
    struct Slide {
        let card: CGImage
        let caption: CGImage
    }

    /// `flat`: one light colour instead of the washed ground, for the GIF, whose 256 colours turn the wash into
    /// blotches.
    static func welcomeSlides(_ r: Renders, width: Int, maxHeight: Int?, dots: Bool, flat: Bool = false) throws -> [Slide] {
        let w = CGFloat(width)
        let captionSize = (w * 0.021).rounded(), dotSize: CGFloat = dots ? 12 : 0, dotGap: CGFloat = dots ? 26 : 0
        let captionHeight = (0..<r.welcome.count).map { height(stepCaption($0, size: captionSize), width: w) }.max()!
        let top: CGFloat = maxHeight == nil ? 60 : 30, below: CGFloat = 28, bottom: CGFloat = maxHeight == nil ? 52 : 30
        let tallest = CGFloat(r.welcome.map(\.height).max()!), widest = CGFloat(r.welcome.map(\.width).max()!)
        var s = w * 0.88 / widest
        if let maxHeight { s = min(s, (CGFloat(maxHeight) - top - below - captionHeight - bottom) / tallest) }
        let area = tallest * s
        let h = maxHeight.map(CGFloat.init) ?? (top + area + below + captionHeight + dotGap + dotSize + bottom).rounded()
        let captionY = top + area + below
        return try r.welcome.indices.map { step in
            let img = r.welcome[step]
            let size = CGSize(width: CGFloat(img.width) * s, height: CGFloat(img.height) * s)
            let card = try canvas(width: width, height: Int(h), ground: !flat) {
                if flat {
                    hex(0xEEF1F6).setFill()
                    NSRect(x: 0, y: 0, width: w, height: h).fill()
                }
                drawCard(img, in: NSRect(x: (w - size.width) / 2, y: top + (area - size.height) / 2,
                                         width: size.width, height: size.height), radius: 14 * 2 * s)
            }
            let caption = try canvas(width: width, height: Int(h), ground: false, opaque: false) {
                draw(stepCaption(step, size: captionSize), in: NSRect(x: 0, y: captionY, width: w, height: captionHeight))
                guard dots else { return }
                let spacing: CGFloat = 26, count = stepCaptions.count
                let x0 = (w - CGFloat(count - 1) * spacing - dotSize) / 2
                for i in 0..<count {
                    (i == step ? accent : NSColor.black.withAlphaComponent(0.16)).setFill()
                    NSBezierPath(ovalIn: NSRect(x: x0 + CGFloat(i) * spacing, y: captionY + captionHeight + dotGap,
                                                width: dotSize, height: dotSize)).fill()
                }
            }
            return Slide(card: card, caption: caption)
        }
    }

    static func flatten(_ slide: Slide) throws -> CGImage {
        try canvas(width: slide.card.width, height: slide.card.height, ground: false) {
            let rect = NSRect(x: 0, y: 0, width: slide.card.width, height: slide.card.height)
            drawImage(slide.card, in: rect)
            drawImage(slide.caption, in: rect)
        }
    }

    /// X's third picture: the Alerts step large enough to read in a timeline (about 600 px wide there), beside
    /// what it means in two lines. The whole flow is the clip's job.
    static let alertsTitle = "It interrupts you only for real breaking news"
    static let alertsBody = "Breaking stories get their own alert, at most 3 an hour and 10 a day. Everything else waits for one short recap, every 15 minutes or whenever you choose."

    static func alertsSlide(_ r: Renders) throws -> CGImage {
        let full = r.welcome[WelcomeStep.alerts.rawValue]
        // Only the three modes and the recap interval: the bullets and the notifications row would make the
        // rest too small to read in a timeline.
        let rows = alertsDetailRows(bands: contentBands(full, rows: full.height)) ?? 0...(full.height - 1)
        let top = rows.lowerBound, bottom = min(full.height, rows.upperBound + 1)
        let right = contentRight(full, rows: rows)
        guard let detail = full.cropping(to: CGRect(x: 0, y: top, width: right, height: bottom - top)) else {
            throw ComposeError.encode("alerts crop")
        }
        let w: CGFloat = 2400, h: CGFloat = 1350, margin: CGFloat = 130, gap: CGFloat = 110
        let textWidth: CGFloat = 820
        let areaWidth = w - margin * 2 - textWidth - gap, areaHeight = h - margin * 2
        let s = min(areaWidth / CGFloat(detail.width), areaHeight / CGFloat(detail.height))
        let size = CGSize(width: CGFloat(detail.width) * s, height: CGFloat(detail.height) * s)
        let title = text(alertsTitle, size: 78, weight: .bold, align: .left, lineHeight: 1.05)
        let body = text(alertsBody, size: 40, color: secondaryInk, align: .left, lineHeight: 1.2)
        let th = height(title, width: textWidth), bh = height(body, width: textWidth)
        let ty = (h - th - 40 - bh) / 2
        return try canvas(width: Int(w), height: Int(h)) {
            draw(title, in: NSRect(x: margin, y: ty, width: textWidth, height: th))
            draw(body, in: NSRect(x: margin, y: ty + th + 40, width: textWidth, height: bh))
            drawCard(detail, in: NSRect(x: w - margin - size.width, y: (h - size.height) / 2, width: size.width, height: size.height),
                     radius: 14 * 2 * s)
        }
    }

    static let socialLine = "The news you choose, in your Mac\u{2019}s menu bar. Each story once, and an alert only when it\u{2019}s really breaking."

    /// The social card, exactly 1200 × 675: the icon, the name, one line, and the Deck popover running off
    /// the bottom edge.
    static func socialCard(_ r: Renders) throws -> CGImage {
        let w: CGFloat = 1200, h: CGFloat = 675
        let pop = r.popovers[.deck]!
        let popWidth: CGFloat = 480, s = popWidth / CGFloat(pop.width)
        let popRect = NSRect(x: w - popWidth - 72, y: 64, width: popWidth, height: CGFloat(pop.height) * s)
        let textWidth = popRect.minX - 72 - 56
        let title = text("News Feed", size: 96, weight: .bold, align: .left)
        let line = text(socialLine, size: 33, color: secondaryInk, align: .left, lineHeight: 1.18)
        let iconSize: CGFloat = 132, iconGap: CGFloat = 26, lineGap: CGFloat = 18
        let titleHeight = height(title, width: textWidth), lineHeight = height(line, width: textWidth)
        let block = iconSize + iconGap + titleHeight + lineGap + lineHeight
        let y0 = (h - block) / 2
        return try canvas(width: Int(w), height: Int(h)) {
            if let icon = AppIconRenderer.image(for: .master) {
                shadowed(blur: 18, y: 6, alpha: 0.18) {
                    icon.draw(in: NSRect(x: 72, y: y0, width: iconSize, height: iconSize), from: .zero,
                              operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                }
            }
            draw(title, in: NSRect(x: 72, y: y0 + iconSize + iconGap, width: textWidth, height: titleHeight))
            draw(line, in: NSRect(x: 72, y: y0 + iconSize + iconGap + titleHeight + lineGap, width: textWidth, height: lineHeight))
            drawCard(pop, in: popRect, radius: 12 * 2 * s)
        }
    }

    /// 360 px wide, the top 3:2 of a popover: what the Look step shows above each design's name.
    static func lookThumbnail(_ pop: CGImage) throws -> CGImage {
        let crop = CGRect(x: 0, y: 0, width: pop.width, height: pop.width * 2 / 3)
        guard let top = pop.cropping(to: crop) else { throw ComposeError.encode("thumbnail crop") }
        return try canvas(width: 360, height: 240, ground: false) {
            drawImage(top, in: NSRect(x: 0, y: 0, width: 360, height: 240))
        }
    }

    // MARK: Drawing

    static let ink = NSColor(srgbRed: 0x1D / 255, green: 0x1D / 255, blue: 0x1F / 255, alpha: 1)
    static let secondaryInk = NSColor(srgbRed: 0x5C / 255, green: 0x61 / 255, blue: 0x6B / 255, alpha: 1)
    static let accent = NSColor(srgbRed: 0x0A / 255, green: 0x7A / 255, blue: 0xFF / 255, alpha: 1)

    static func hex(_ v: Int, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: alpha)
    }

    /// A flipped (top-left origin) sRGB canvas, opaque, the ground drawn first unless `ground` is false.
    static func canvas(width: Int, height: Int, ground: Bool = true, opaque: Bool = true,
                       _ body: () throws -> Void) throws -> CGImage {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast).rawValue) else {
            throw ComposeError.encode("canvas \(width)×\(height)")
        }
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        defer { NSGraphicsContext.restoreGraphicsState() }
        if opaque {
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: width, height: height).fill()
        }
        if ground { drawGround(CGSize(width: width, height: height)) }
        try body()
        guard let image = ctx.makeImage() else { throw ComposeError.encode("canvas image") }
        return image
    }

    /// A soft light ground: a cool top-to-bottom wash, a blue glow top left and a warm one bottom right.
    /// Computed per pixel rather than drawn with `NSGradient`, whose dithering would triple a PNG's size.
    static func drawGround(_ size: CGSize) {
        if let ground = groundImage(width: Int(size.width), height: Int(size.height)) {
            drawImage(ground, in: NSRect(origin: .zero, size: size))
        }
    }

    static func groundImage(width: Int, height: Int) -> CGImage? {
        typealias RGB = (r: Double, g: Double, b: Double)
        func rgb(_ v: Int) -> RGB { (Double((v >> 16) & 0xFF), Double((v >> 8) & 0xFF), Double(v & 0xFF)) }
        let top = rgb(0xF8F9FC), bottom = rgb(0xE7ECF4)
        let w = Double(width), h = Double(height), reach = max(w, h)
        // The wash runs along (0.3 w, h); each glow eases from its alpha at the centre to 0 at its radius.
        let dx = w * 0.3, dy = h, along = dx * dx + dy * dy
        let glows: [(cx: Double, cy: Double, radius: Double, alpha: Double, color: RGB)] = [
            (w * 0.1, h * 0.02, reach * 0.55, 0.8, rgb(0xD3E2FA)),
            (w * 0.95, h * 1.0, reach * 0.5, 0.65, rgb(0xF8E0D6)),
        ]
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            let fy = Double(y)
            for x in 0..<width {
                let fx = Double(x)
                let t = min(1, max(0, (fx * dx + fy * dy) / along))
                var c: RGB = (top.r + (bottom.r - top.r) * t, top.g + (bottom.g - top.g) * t, top.b + (bottom.b - top.b) * t)
                for g in glows {
                    let d = ((fx - g.cx) * (fx - g.cx) + (fy - g.cy) * (fy - g.cy)).squareRoot()
                    let u = min(1, d / g.radius), a = g.alpha * (1 - u * u * (3 - 2 * u))   // smoothstep: no cusp at the centre
                    if a > 0 { c = (c.r + (g.color.r - c.r) * a, c.g + (g.color.g - c.g) * a, c.b + (g.color.b - c.b) * a) }
                }
                let i = (y * width + x) * 4
                pixels[i] = UInt8(c.r.rounded())
                pixels[i + 1] = UInt8(c.g.rounded())
                pixels[i + 2] = UInt8(c.b.rounded())
            }
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    static func shadowed(blur: CGFloat, y: CGFloat, alpha: CGFloat, _ body: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = blur
        shadow.shadowOffset = NSSize(width: 0, height: -y)
        shadow.shadowColor = NSColor.black.withAlphaComponent(alpha)
        shadow.set()
        body()
        NSGraphicsContext.restoreGraphicsState()
    }

    static func drawImage(_ image: CGImage, in rect: NSRect) {
        NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            .draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                  hints: [.interpolation: NSNumber(value: NSImageInterpolation.high.rawValue)])
    }

    /// A render as a floating card: a wide soft shadow and a tight contact one, the render clipped to rounded
    /// corners, and a hairline just outside its edge.
    static func drawCard(_ image: CGImage, in rect: NSRect, radius: CGFloat, shadowScale: CGFloat = 1) {
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        let reach = (rect.width + rect.height) / 2 * shadowScale
        shadowed(blur: max(10, reach * 0.06), y: max(4, reach * 0.02), alpha: 0.16) {
            NSColor.white.setFill()
            path.fill()
        }
        shadowed(blur: 3, y: 1, alpha: 0.10) {
            NSColor.white.setFill()
            path.fill()
        }
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        drawImage(image, in: rect)
        NSGraphicsContext.restoreGraphicsState()
        let edge = NSBezierPath(roundedRect: rect.insetBy(dx: -0.75, dy: -0.75), xRadius: radius + 0.75, yRadius: radius + 0.75)
        edge.lineWidth = 1.5
        NSColor.black.withAlphaComponent(0.07).setStroke()
        edge.stroke()
    }

    static func text(_ string: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = ink,
                     align: NSTextAlignment = .center, lineHeight: CGFloat = 1.12) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.alignment = align
        style.lineHeightMultiple = lineHeight
        return NSAttributedString(string: string, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style,
        ])
    }

    static func centered(_ s: NSAttributedString) -> NSAttributedString {
        let m = NSMutableAttributedString(attributedString: s)
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineHeightMultiple = 1.12
        m.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: m.length))
        return m
    }

    static func height(_ s: NSAttributedString, width: CGFloat) -> CGFloat {
        s.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                       options: [.usesLineFragmentOrigin, .usesFontLeading]).height.rounded(.up)
    }

    static func draw(_ s: NSAttributedString, in rect: NSRect) {
        s.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }

    // MARK: Files

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw ComposeError.encode(url.lastPathComponent)
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw ComposeError.encode(url.lastPathComponent) }
    }

    /// The README's welcome loop: one frame per screen, `delay` seconds each, looping, at most 8 MB.
    static func writeGIF(_ frames: [CGImage], delay: Double, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else {
            throw ComposeError.encode(url.lastPathComponent)
        }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let frameProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay,
                                                               kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary
        for frame in frames { CGImageDestinationAddImage(dest, frame, frameProperties) }
        guard CGImageDestinationFinalize(dest) else { throw ComposeError.encode(url.lastPathComponent) }
        // ImageIO labels the file GIF87a; an animated GIF (its loop and delay blocks) is a GIF89a file.
        var data = try Data(contentsOf: url)
        if data.starts(with: Array("GIF87a".utf8)) {
            data.replaceSubrange(3..<6, with: Array("89a".utf8))
            try data.write(to: url)
        }
        let bytes = data.count
        if bytes > 8_000_000 { throw ComposeError.tooLarge(url.lastPathComponent, bytes) }
    }

    /// The X clip: each screen held `hold` seconds, its card cross-fading into the next one's over `fade`
    /// seconds while the caption cuts over at the midpoint (two captions dissolved together are unreadable).
    /// H.264, no audio, its index at the front so it starts playing before it has all arrived.
    static func writeVideo(_ slides: [Slide], to url: URL, hold: Double = 2.0, fade: Double = 0.5, fps: Int32 = 30) throws {
        guard let first = slides.first else { return }
        let width = first.card.width, height = first.card.height
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000,
                                              AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                                              AVVideoMaxKeyFrameIntervalKey: Int(fps) * 2],
            AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                                        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                                        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        guard writer.canAdd(input) else { throw ComposeError.video("cannot add input") }
        writer.add(input)
        guard writer.startWriting() else { throw ComposeError.video("start: \(String(describing: writer.error))") }
        writer.startSession(atSourceTime: .zero)

        var frame: Int64 = 0
        func append(_ a: CGImage, _ b: CGImage? = nil, mix: CGFloat = 0, caption: CGImage) throws {
            guard let pool = adaptor.pixelBufferPool else { throw ComposeError.video("no pixel buffer pool") }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { throw ComposeError.video("no pixel buffer") }
            CVPixelBufferLockBaseAddress(buffer, [])
            let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            let rect = CGRect(x: 0, y: 0, width: width, height: height)
            ctx?.draw(a, in: rect)
            if let b {
                ctx?.setAlpha(mix)
                ctx?.draw(b, in: rect)
                ctx?.setAlpha(1)
            }
            ctx?.draw(caption, in: rect)
            CVPixelBufferUnlockBaseAddress(buffer, [])
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: frame, timescale: fps)) else {
                throw ComposeError.video("append: \(String(describing: writer.error))")
            }
            frame += 1
        }

        let holdFrames = Int(hold * Double(fps)), fadeFrames = Int(fade * Double(fps))
        for (i, slide) in slides.enumerated() {
            let isLast = i == slides.count - 1
            for _ in 0..<(isLast ? holdFrames + Int(fps) : holdFrames) { try append(slide.card, caption: slide.caption) }
            guard !isLast else { break }
            let next = slides[i + 1]
            for k in 1...fadeFrames {
                let t = CGFloat(k) / CGFloat(fadeFrames + 1)
                try append(slide.card, next.card, mix: t * t * (3 - 2 * t),   // smoothstep
                           caption: t < 0.5 ? slide.caption : next.caption)
            }
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else { throw ComposeError.video("finish: \(String(describing: writer.error))") }
        // The network-use pass writes a first copy beside the file (`<name>.sb-…`); the run exits before
        // AVFoundation tidies it, so remove it here.
        let folder = url.deletingLastPathComponent()
        for name in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        where name.hasPrefix(url.lastPathComponent + ".sb-") {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }
}
