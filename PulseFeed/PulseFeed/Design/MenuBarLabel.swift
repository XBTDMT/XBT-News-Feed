import SwiftUI
import AppKit

/// Counts behind the state-aware menu bar item: a red dot while a BREAKING story is unread, and the
/// number of stories that arrived since the popover was last closed (idea ①).
@MainActor
@Observable
final class MenuBarStatusModel {
    let appDB: AppDatabase
    private(set) var breakingUnread = 0
    private(set) var newSince = 0
    /// Option D's current frame while "menubar_x_animation" is on; nil = the static template glyph.
    /// Driven by a plain timer: a TimelineView inside the MenuBarExtra label re-enters SwiftUI's
    /// status-item update synchronously and never returns from launch (2026-09-08).
    private(set) var animationFrame: NSImage?
    private var animationTimer: Timer?
    private var defaultsObserver: (any NSObjectProtocol)?
    private var breakingTask: Task<Void, Never>?
    private var newSinceTask: Task<Void, Never>?
    private var observer: (any NSObjectProtocol)?

    init(appDB: AppDatabase) {
        self.appDB = appDB
    }

    /// `make showcase`: one menu bar state set by hand on a model that is never started.
    func showcase(breakingUnread: Int, newSince: Int) {
        self.breakingUnread = breakingUnread
        self.newSince = newSince
    }

    func start() {
        guard breakingTask == nil else { return }
        breakingTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await n in AppDatabase.breakingUnreadCountObservation().values(in: self.appDB.dbPool) {
                    self.breakingUnread = n
                }
            } catch {}
        }
        restartNewSince()
        syncAnimation()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncAnimation() }
        }
        observer = NotificationCenter.default.addObserver(
            forName: .pulseFeedLastLookedChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.restartNewSince() }
        }
    }

    /// Start or stop the frame timer to match the setting.
    private func syncAnimation() {
        let on = UserDefaults.standard.bool(forKey: XTileGlyph.animationDefaultsKey)
        if on, animationTimer == nil {
            let timer = Timer(timeInterval: 1 / XTileGlyph.quadrantsFPS, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.animationFrame = XTileGlyph.quadrantsFrame(at: Date().timeIntervalSinceReferenceDate)
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            animationTimer = timer
            animationFrame = XTileGlyph.quadrantsFrame(at: Date().timeIntervalSinceReferenceDate)
        } else if !on, animationTimer != nil {
            animationTimer?.invalidate()
            animationTimer = nil
            animationFrame = nil
        }
    }

    private func restartNewSince() {
        newSinceTask?.cancel()
        let since = LastLookedStore.read()
        newSinceTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await n in AppDatabase.newSinceObservation(since: since).values(in: self.appDB.dbPool) {
                    self.newSince = n
                }
            } catch {}
        }
    }
}

/// Colour images for the menu bar label. Template glyphs come from SF Symbols; only the additions
/// (dot, capsule) are rendered as original-colour images.
enum MenuBarImages {
    static let redDot: NSImage = {
        let image = NSImage(size: NSSize(width: 7, height: 7), flipped: false) { rect in
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        image.isTemplate = false
        return image
    }()

    nonisolated(unsafe) private static var capsuleCache: [String: NSImage] = [:]

    /// "BTC +1.8%" in green/red on a tinted capsule, cached per formatted string.
    @MainActor
    static func capsule(change: Double) -> NSImage? {
        let text = "BTC " + (PriceFormatting.change(change) ?? "")
        if let cached = capsuleCache[text] { return cached }
        let color: Color = change >= 0 ? Color(hex: "#34C759") : Color(hex: "#FF3B30")
        let view = Text(text)
            .font(.system(size: 11, weight: .semibold)).monospacedDigit()
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = false
        capsuleCache[text] = image
        return image
    }
}

/// The MenuBarExtra label: design glyph + breaking dot + new-since count + optional BTC capsule.
struct MenuBarLabel: View {
    let design: AppDesign
    let status: MenuBarStatusModel
    let engine: FeedEngine
    @AppStorage("menubar_btc_capsule") private var capsuleOn = false
    @AppStorage(AppIconStyle.defaultsKey) private var iconRaw: String = AppIconStyle.autoValue
    @ObservedObject private var power = PowerMonitor.shared

    var body: some View {
        let style = AppIconStyle.resolve(stored: iconRaw, design: design)
        HStack(spacing: 3) {
            if style.isMaster, let frame = status.animationFrame {
                // Option D: the coloured outline with its four-way split turning clockwise.
                Image(nsImage: frame)
            } else if let glyph = style.menuBarImage {
                Image(nsImage: glyph)
            } else {
                Image(systemName: style.glyphSymbolName)
            }
            if status.breakingUnread > 0 {
                Image(nsImage: MenuBarImages.redDot)
            }
            if status.newSince > 0 {
                Text(status.newSince > 99 ? "99+" : "\(status.newSince)")
            }
            if capsuleOn, power.tier == .ac,
               let change = engine.latestPrices["bitcoin"]?.change24h,
               let image = MenuBarImages.capsule(change: change) {
                Image(nsImage: image)
            }
        }
    }
}
