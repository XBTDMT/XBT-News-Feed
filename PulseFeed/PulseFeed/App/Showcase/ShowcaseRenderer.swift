import AppKit
import SwiftUI
import Sparkle

/// `make showcase`: the app's OWN surfaces (nothing re-drawn) on `ShowcaseFixture`, rendered offscreen into
/// 2× PNGs in the light appearance, the way Battery's `--render-showcase` does it: each surface is an
/// `NSHostingView` in a borderless window that is never ordered on screen (SwiftUI still attaches, so
/// `.task` observations run), drawn with `cacheDisplay(in:to:)` into a bitmap of our own. No screen
/// recording is involved. One run draws one design (`AppDesign.current`, from `PULSEFEED_DESIGN`):
/// `<design>-popover.png` and `<design>-window.png` (the window with the system's traffic lights drawn where
/// the window would show them). The Stream run, the last, then makes the Look step's thumbnails from the three
/// popovers, draws the welcome flow's seven screens with them (so one `make showcase` is enough) and the menu
/// bar item's three states, and hands the folder to `ShowcaseComposer` for the README and X pictures.
@MainActor
enum ShowcaseRenderer {
    static let scale: CGFloat = 2
    /// Long enough for every `.task` observation to deliver its first value and the layout to settle.
    static let settle: TimeInterval = 1.5

    enum RenderError: Error { case bitmap(String), noCatalog }

    /// The state the fixture's install would have after a tick: the engine's prices, recap and brief, and
    /// this showcase domain's settings (the chosen instruments, last looked). `make showcase` runs the public
    /// build, so its providers (keyless quotes, Gemini) and its catalog are the public app's own defaults.
    static func prepare(engine: FeedEngine) {
        MarketInstrument.store(ShowcaseFixture.instruments, .standard)
        LastLookedStore.markLooked(ShowcaseFixture.lastLooked)
        engine.showcase(
            prices: ShowcaseFixture.prices, recap: ShowcaseFixture.recap, recapIDs: ShowcaseFixture.recapIDs,
            digest: ShowcaseFixture.digest, headlines: ShowcaseFixture.topHeadlines,
            lastTickAt: ShowcaseFixture.now.addingTimeInterval(-2 * 60),
            nextTickAt: ShowcaseFixture.now.addingTimeInterval(3 * 60), stats: ShowcaseFixture.tickStats)
    }

    /// Writes this design's PNGs (and, on the last run, the welcome flow, the menu bar and the composed set)
    /// and returns their paths.
    @discardableResult
    static func run(outputDir: URL, design: AppDesign, appDB: AppDatabase, engine: FeedEngine) throws -> [URL] {
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        NSApp.appearance = NSAppearance(named: .aqua)
        let updater = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        var written: [URL] = []
        func out(_ name: String) -> URL {
            let url = outputDir.appendingPathComponent(name)
            written.append(url)
            return url
        }

        // Each surface starts from the same "last looked"; a popover's onDisappear moves it to now.
        LastLookedStore.markLooked(ShowcaseFixture.lastLooked)
        try snapshot(design.popover(appDB: appDB, updater: updater).environment(engine),
                     size: design.popoverSize, to: out("\(design.rawValue)-popover.png"))
        LastLookedStore.markLooked(ShowcaseFixture.lastLooked)
        let windowSize = windowRenderSize(design)
        try snapshot(design.mainWindow(appDB: appDB).environment(engine)
                        .overlay(alignment: .topLeading) { ShowcaseTrafficLights(lights: trafficLights(contentSize: windowSize)) },
                     size: windowSize, to: out("\(design.rawValue)-window.png"))

        guard design == .stream else { return written }

        // The Look step's thumbnails from this run's popovers, read by the welcome renders below.
        written += try ShowcaseComposer.thumbnails(in: outputDir)
        LookThumbnail.directoryOverride = ShowcaseComposer.composedDirectory(outputDir)

        guard let catalog = Catalog.bundled else { throw RenderError.noCatalog }
        for step in WelcomeStep.allCases {
            let model = WelcomeFlowModel(appDB: appDB, catalog: catalog, dryRun: true, startStep: step, livePreview: false)
            model.draft = WelcomeFlowModel.sample(model.draft)
            model.headlines = ShowcaseFixture.headlines
            // The Sources step is a list of on/off switches: drawn inactive, an "on" switch reads as off.
            try snapshot(WelcomeFlowView(model: model), size: CGSize(width: 920, height: 620),
                         to: out("welcome-\(step.rawValue).png"), activeLook: step == .sources)
        }

        // The menu bar item at 4x (a 24 pt bar is 96 px), on a light and on a dark bar, one width for all
        // three states so the composer can line them up. Drawn by ImageRenderer at that scale, so the glyph's
        // drawing handler runs at 4x and the X is as crisp as the digits (an offscreen window rasterises at 2x).
        for (name, breaking, newSince) in [("idle", 0, 0), ("new-count", 0, 12), ("breaking-dot", 1, 12)] {
            for dark in [false, true] {
                let status = MenuBarStatusModel(appDB: appDB)
                status.showcase(breakingUnread: breaking, newSince: newSince)
                let bar = dark ? Color(red: 0x24 / 255, green: 0x24 / 255, blue: 0x27 / 255)
                               : Color(red: 0xEC / 255, green: 0xEC / 255, blue: 0xEE / 255)
                let item = MenuBarLabel(design: design, status: status, engine: engine)
                    .padding(.horizontal, 10)
                    .frame(width: menuBarItemWidth, height: menuBarHeight)
                    .background(bar)
                    .environment(\.colorScheme, dark ? .dark : .light)
                    // The menu bar draws its template images in plain white or black; outside a status item
                    // ImageRenderer would tint them with a dimmer label colour.
                    .foregroundStyle(dark ? Color.white : Color.black)
                let renderer = ImageRenderer(content: item)
                renderer.scale = menuBarScale
                var rendered: CGImage?
                NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance { rendered = renderer.cgImage }
                guard let image = rendered else { throw RenderError.bitmap("menubar-\(name)") }
                try ShowcaseComposer.writePNG(image, to: out("menubar-\(name)\(dark ? "-dark" : "").png"))
            }
        }

        written += try ShowcaseComposer.compose(in: outputDir)
        return written
    }

    /// The size a main window is drawn at: the design's default, except Stream's, whose rail (prices, brief,
    /// unread, the Starred / Saved tiles) ends just past the default height and would be cut through; the extra
    /// stops above the cards under the "since you last looked" divider.
    static func windowRenderSize(_ design: AppDesign) -> CGSize {
        let size = design.mainWindowDefaultSize
        return CGSize(width: size.width, height: size.height + (design == .stream ? streamExtraHeight : 0))
    }
    static let streamExtraHeight: CGFloat = 32

    /// Where a main window's close / minimise / zoom buttons sit, read from a real window of that size with the
    /// main window's style (title bar transparent, content under it): centre and diameter, top-left origin.
    static func trafficLights(contentSize: CGSize) -> [(center: CGPoint, diameter: CGFloat)] {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: contentSize),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: true)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        let height = window.frame.height
        return [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { kind in
            guard let button = window.standardWindowButton(kind) else { return nil }
            let frame = button.convert(button.bounds, to: nil)
            return (CGPoint(x: frame.midX, y: height - frame.midY), min(frame.width, frame.height))
        }
    }

    static let menuBarHeight: CGFloat = 24
    static let menuBarItemWidth: CGFloat = 88
    static let menuBarScale: CGFloat = 4

    /// One surface: host it in an offscreen window at `size` (or its fitting size), let it settle, draw it.
    /// `activeLook`: draw AppKit switches as in a key window (`ShowcaseWindow`); see there for its limit.
    static func snapshot<V: View>(_ view: V, size: CGSize?, to url: URL, settle: TimeInterval = settle,
                                  activeLook: Bool = false, scale: CGFloat = ShowcaseRenderer.scale,
                                  appearance: NSAppearance? = NSAppearance(named: .aqua)) throws {
        let host = NSHostingView(rootView: view)
        host.appearance = appearance
        let frame = NSRect(origin: .zero, size: size ?? host.fittingSize)
        let window: NSWindow = activeLook
            ? ShowcaseWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            : NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = host.appearance
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        window.contentView = host
        host.frame = size == nil ? NSRect(origin: .zero, size: host.fittingSize) : frame
        host.layoutSubtreeIfNeeded()
        pump(seconds: settle)
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        pump(seconds: 0.2)
        try write(host, to: url, scale: scale)
        window.contentView = nil
        pump(seconds: 0.1)
    }

    /// Draw the view into a 2× (or `scale`×) bitmap of our own (the window is on no screen, so its backing
    /// scale is not the one we want) over the window ground of the view's appearance, and write it as PNG.
    static func write(_ view: NSView, to url: URL, scale: CGFloat = ShowcaseRenderer.scale) throws {
        let size = view.bounds.size
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw RenderError.bitmap(url.lastPathComponent)
        }
        rep.size = size
        if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = ctx
            (view.appearance ?? NSAppearance(named: .aqua))?.performAsCurrentDrawingAppearance {
                NSColor.windowBackgroundColor.setFill()
                NSRect(origin: .zero, size: size).fill()
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw RenderError.bitmap(url.lastPathComponent) }
        try data.write(to: url)
    }

    /// Run the main run loop (which also drains the main-actor queue) for `seconds`.
    static func pump(seconds: TimeInterval) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }
}

/// An offscreen window whose controls draw with the active look, without activating the app (that would take
/// focus from the person at the Mac): AppKit asks these private questions to choose an "on" switch's accent
/// and the default button's blue. Its limit: the default button's label stays dark (the active app draws it
/// white), which no window-level answer changes, so only the Sources step, where the switches are the
/// content, is drawn this way.
final class ShowcaseWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
    @objc func _hasActiveAppearance() -> Bool { true }
    @objc func _hasActiveAppearanceIgnoringKeyFocus() -> Bool { true }
    @objc func _hasKeyAppearance() -> Bool { true }
    @objc func _hasMainAppearance() -> Bool { true }
}


/// The window's close / minimise / zoom buttons as the active window shows them: a showcase render has no
/// title bar of its own, and the designs leave the corner free for these.
struct ShowcaseTrafficLights: View {
    let lights: [(center: CGPoint, diameter: CGFloat)]
    private static let fills: [Color] = [Color(red: 1, green: 0x5F / 255, blue: 0x57 / 255),
                                         Color(red: 0xFE / 255, green: 0xBC / 255, blue: 0x2E / 255),
                                         Color(red: 0x28 / 255, green: 0xC8 / 255, blue: 0x40 / 255)]
    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(lights.indices, id: \.self) { i in
                Circle()
                    .fill(Self.fills[i % 3])
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
                    .frame(width: lights[i].diameter, height: lights[i].diameter)
                    .position(lights[i].center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}
