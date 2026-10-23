import SwiftUI
import AppKit

/// The app icons: the master (X-Tile, the owner's pick from the 25-option sheet on 2026-09-06) plus the
/// ten sheet icons, each with its matching menu bar glyph. Settings › General › Icon stores a
/// choice under `app_icon`; "auto" (the default) is the master, whichever design is running.
enum AppIconStyle: String, CaseIterable, Sendable {
    case xTile
    case quietNative, terminalDesk, frontPage, cardStream, commandBar
    case pulseTimeline, morningBrief, tileDeck, readingRoom, glassHUD

    static let defaultsKey = "app_icon"
    static let autoValue = "auto"

    /// The one icon baked into AppIcon.icns — what Finder, the Dock and notification banners show.
    static let master: AppIconStyle = .xTile
    var isMaster: Bool { self == AppIconStyle.master }

    static func resolve(stored: String?, design: AppDesign) -> AppIconStyle {
        if let raw = stored?.trimmingCharacters(in: .whitespaces).lowercased(), !raw.isEmpty, raw != autoValue,
           let match = allCases.first(where: { $0.rawValue.lowercased() == raw }) {
            return match
        }
        return auto(for: design)
    }

    /// "Auto" is the master for every design (one icon for the app and its notifications).
    static func auto(for design: AppDesign) -> AppIconStyle { master }

    /// The effective style right now (stored choice or the running design's own).
    static var current: AppIconStyle {
        resolve(stored: UserDefaults.standard.string(forKey: defaultsKey), design: AppDesign.current)
    }

    var displayName: String {
        switch self {
        case .xTile: return "XBTDMT"
        case .quietNative: return "Quiet Native"
        case .terminalDesk: return "Terminal Desk"
        case .frontPage: return "Front Page"
        case .cardStream: return "Card Stream"
        case .commandBar: return "Command Bar"
        case .pulseTimeline: return "Pulse Timeline"
        case .morningBrief: return "Morning Brief"
        case .tileDeck: return "Tile Deck"
        case .readingRoom: return "Reading Room"
        case .glassHUD: return "Glass HUD"
        }
    }

    /// A custom template image for the menu bar (the master's own letter); nil = use the SF Symbol.
    @MainActor var menuBarImage: NSImage? { isMaster ? XTileGlyph.menuBarImage : nil }

    /// SF Symbol drawn as a template image in the menu bar (the master carries its own letter).
    var glyphSymbolName: String {
        switch self {
        case .xTile: return "xmark"
        case .quietNative: return "newspaper"
        case .terminalDesk: return "chart.bar"
        case .frontPage: return "doc.text"
        case .cardStream: return "square.stack"
        case .commandBar: return "chevron.right"
        case .pulseTimeline: return "waveform.path.ecg"
        case .morningBrief: return "sun.max"
        case .tileDeck: return "square.grid.2x2"
        case .readingRoom: return "book.closed"
        case .glassHUD: return "capsule"
        }
    }

    var background: Color {
        switch self {
        case .xTile: return XTileGlyph.groundBottom
        case .quietNative: return Color(hex: "#0A84FF")
        case .terminalDesk: return Color(hex: "#121316")
        case .frontPage: return Color(hex: "#F3EDE0")
        case .cardStream: return Color(hex: "#F2634F")
        case .commandBar: return Color(hex: "#2B2E7A")
        case .pulseTimeline: return Color(hex: "#2E3440")
        case .morningBrief: return Color(hex: "#C25B3A")
        case .tileDeck: return Color(hex: "#F3F4F7")
        case .readingRoom: return Color(hex: "#1F5B44")
        case .glassHUD: return Color(hex: "#1B1C20")
        }
    }
}

/// The icon art at 1024×1024, from each sheet's "Icons · app + menu bar" panel.
struct AppIconStyleArt: View {
    let style: AppIconStyle

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 225, style: .continuous).fill(style.background)
            switch style {
            case .xTile:
                RoundedRectangle(cornerRadius: 225, style: .continuous)
                    .fill(LinearGradient(colors: [XTileGlyph.groundTop, XTileGlyph.groundBottom], startPoint: .top, endPoint: .bottom))
                XTileGlyph.path(in: 1024)
                    .fill(LinearGradient(colors: XTileGlyph.warm,
                                         startPoint: UnitPoint(x: 180 / 1024, y: 180 / 1024), endPoint: UnitPoint(x: 844 / 1024, y: 844 / 1024)))
                    .clipShape(QuadrantMask(diagonal: .back))
                XTileGlyph.path(in: 1024)
                    .fill(LinearGradient(colors: XTileGlyph.cool,
                                         startPoint: UnitPoint(x: 844 / 1024, y: 180 / 1024), endPoint: UnitPoint(x: 180 / 1024, y: 844 / 1024)))
                    .clipShape(QuadrantMask(diagonal: .forward))
                RoundedRectangle(cornerRadius: 225, style: .continuous)
                    .inset(by: 8)
                    .stroke(Color.white.opacity(0.16), lineWidth: 16)
            case .quietNative:
                Image(systemName: "newspaper.fill").font(.system(size: 520, weight: .medium)).foregroundStyle(.white)
            case .terminalDesk:
                // A stepped price print; the last tick in amber.
                Path { p in
                    let pts: [CGPoint] = [(180, 640), (300, 640), (300, 560), (420, 560), (420, 610), (540, 610), (540, 470), (660, 470), (660, 520), (780, 520), (780, 400), (860, 400)]
                        .map { CGPoint(x: $0.0, y: $0.1) }
                    p.move(to: pts[0]); for pt in pts.dropFirst() { p.addLine(to: pt) }
                }
                .stroke(Color.white.opacity(0.92), style: StrokeStyle(lineWidth: 44, lineCap: .round, lineJoin: .round))
                Circle().fill(Color(hex: "#E8B931")).frame(width: 96, height: 96).position(x: 860, y: 400)
            case .frontPage:
                VStack(spacing: 0) {
                    Rectangle().fill(Color(hex: "#1A1A1A")).frame(width: 720, height: 10)
                    Spacer().frame(height: 26)
                    Rectangle().fill(Color(hex: "#B3261E")).frame(width: 720, height: 34)
                    Text("X").font(.system(size: 470, weight: .bold, design: .serif)).foregroundStyle(Color(hex: "#151515")).padding(.top, 10)
                }
                .offset(y: -20)
            case .cardStream:
                ZStack {
                    card().rotationEffect(.degrees(-8)).offset(x: -70, y: 30)
                    card().offset(x: 0, y: 0)
                    card().rotationEffect(.degrees(8)).offset(x: 70, y: -30)
                }
            case .commandBar:
                HStack(spacing: 40) {
                    Image(systemName: "chevron.right").font(.system(size: 420, weight: .bold)).foregroundStyle(.white)
                    RoundedRectangle(cornerRadius: 20).fill(.white).frame(width: 240, height: 56).offset(y: 150)
                }
                .offset(x: -20)
            case .pulseTimeline:
                Path { p in
                    let pts: [CGPoint] = [(140, 520), (330, 520), (400, 360), (470, 680), (540, 300), (610, 720), (680, 520), (860, 520)]
                        .map { CGPoint(x: $0.0, y: $0.1) }
                    p.move(to: pts[0]); for pt in pts.dropFirst() { p.addLine(to: pt) }
                }
                .stroke(Color(hex: "#5AC8FA"), style: StrokeStyle(lineWidth: 46, lineCap: .round, lineJoin: .round))
                Circle().fill(Color(hex: "#5AC8FA")).frame(width: 100, height: 100).position(x: 860, y: 520)
            case .morningBrief:
                Image(systemName: "sun.max.fill").font(.system(size: 500, weight: .medium)).foregroundStyle(Color(hex: "#F6EFE6"))
            case .tileDeck:
                VStack(spacing: 40) {
                    HStack(spacing: 40) { tile(Color(hex: "#FF3B30")); tile(Color(hex: "#34C759")) }
                    HStack(spacing: 40) { tile(Color(hex: "#E8B931")); tile(Color(hex: "#0A84FF")) }
                }
            case .readingRoom:
                Image(systemName: "book.closed.fill").font(.system(size: 500, weight: .medium)).foregroundStyle(Color(hex: "#F3EFE6"))
            case .glassHUD:
                ZStack {
                    RoundedRectangle(cornerRadius: 170, style: .continuous)
                        .fill(Color.white.opacity(0.14))
                        .overlay(RoundedRectangle(cornerRadius: 170, style: .continuous).stroke(Color.white.opacity(0.35), lineWidth: 12))
                        .frame(width: 760, height: 340)
                    HStack(spacing: 44) {
                        Circle().fill(Color(hex: "#34C759")).frame(width: 90, height: 90)
                        RoundedRectangle(cornerRadius: 30).fill(Color.white.opacity(0.85)).frame(width: 380, height: 70)
                    }
                }
            }
        }
        .frame(width: 1024, height: 1024)
    }

    private func tile(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 56, style: .continuous).fill(color).frame(width: 300, height: 300)
    }

    private func card() -> some View {
        RoundedRectangle(cornerRadius: 48, style: .continuous)
            .fill(.white)
            .frame(width: 520, height: 360)
            .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
    }
}

/// The two diagonal quadrant pairs of a square: the X-Tile's warm arm lives in `.back`
/// (top-left + bottom-right), its cool arm in `.forward` (top-right + bottom-left).
struct QuadrantMask: Shape {
    enum Diagonal { case back, forward }
    let diagonal: Diagonal

    func path(in rect: CGRect) -> Path {
        let w = rect.width / 2, h = rect.height / 2
        var p = Path()
        switch diagonal {
        case .back:
            p.addRect(CGRect(x: rect.minX, y: rect.minY, width: w, height: h))
            p.addRect(CGRect(x: rect.midX, y: rect.midY, width: w, height: h))
        case .forward:
            p.addRect(CGRect(x: rect.midX, y: rect.minY, width: w, height: h))
            p.addRect(CGRect(x: rect.minX, y: rect.midY, width: w, height: h))
        }
        return p
    }
}

/// Settings › General › Icon: "Auto" (the master) plus the master and the ten sheet icons.
struct AppIconPicker: View {
    @AppStorage(AppIconStyle.defaultsKey) private var stored: String = AppIconStyle.autoValue
    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: columns, spacing: 10) {
                cell(raw: AppIconStyle.autoValue, name: "Auto", style: AppIconStyle.auto(for: AppDesign.current))
                ForEach(AppIconStyle.allCases, id: \.rawValue) { style in
                    cell(raw: style.rawValue, name: style.displayName, style: style)
                }
            }
            Text("Auto is the XBTDMT icon, the one notification banners always show. Any other choice applies at once to the menu bar, the Dock and the app's Finder icon.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: stored) { _, _ in AppIcon.apply() }
    }

    private func cell(raw: String, name: String, style: AppIconStyle) -> some View {
        let selected = stored == raw
        return Button {
            stored = raw
        } label: {
            VStack(spacing: 5) {
                AppIconStyleArt(style: style)
                    .scaleEffect(48 / 1024, anchor: .topLeading)
                    .frame(width: 48, height: 48)
                    .clipped()
                Text(name).font(.system(size: 10, weight: selected ? .bold : .regular)).lineLimit(1)
            }
            .padding(6)
            .frame(maxWidth: .infinity)
            .background(selected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.accentColor : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}
