import SwiftUI
import AppKit

/// The R1-NativePro-B sheet's colours, by the role each plays there. Light values are the sheet's
/// hex; dark values are the nearest system material so the design still reads in Dark.
enum NativeProPalette {
    static let blue = Color(hex: "#0A84FF")
    /// Popover, list and detail surfaces (#FFFFFF).
    static let surface = Color(light: "#FFFFFF", dark: "#1E1E20")
    /// The markets strip (#F5F5F7).
    static let strip = Color(light: "#F5F5F7", dark: "#2A2A2D")
    /// Search fields and unselected chips (#F2F2F7).
    static let field = Color(light: "#F2F2F7", dark: "#2C2C2E")
    /// The rule between rows (#F2F2F7).
    static let hairline = Color(light: "#F2F2F7", dark: "#2C2C2E")
    /// The heavier rule above the list and above the footer (#E5E5EA).
    static let rule = Color(light: "#E5E5EA", dark: "#3A3A3C")
    static let text = Color(light: "#1D1D1F", dark: "#F5F5F7")
    /// Read titles and the strip labels (#3A3A3C).
    static let textRead = Color(light: "#3A3A3C", dark: "#D4D4D4")
    /// Snippets and the footer (#6E6E73).
    static let textSecondary = Color(light: "#6E6E73", dark: "#A1A1A6")
    /// Meta lines, times, counts (#8E8E93).
    static let textTertiary = Color(hex: "#8E8E93")
    /// Unfilled star and bookmark glyphs (#AEAEB2).
    static let iconMuted = Color(light: "#AEAEB2", dark: "#636366")
    /// The hovered row (#F7F7FA).
    static let hover = Color(light: "#F7F7FA", dark: "#26262A")
    /// The since-you-last-looked band (#F2F6FF).
    static let sinceBand = Color(light: "#F2F6FF", dark: "#1A2536")
    /// The selected list row in the window (#EAF2FF).
    static let selectedRow = Color(light: "#EAF2FF", dark: "#1C2B44")
    static let sidebar = Color(light: "#EFEFF2", dark: "#232326")
    static let sidebarBorder = Color(light: "#D9D9DE", dark: "#3A3A3C")
    static let controlBorder = Color(light: "#D2D2D7", dark: "#48484A")
    /// The settings content pane (#F5F5F7).
    static let settingsCanvas = Color(light: "#F5F5F7", dark: "#1E1E20")
    /// Change text: green #1E8E3E / red #D93025; the sparkline itself uses the system green/red.
    static let up = Color(light: "#1E8E3E", dark: "#30D158")
    static let down = Color(light: "#D93025", dark: "#FF453A")
    static let upLine = Color(hex: "#34C759")
    static let downLine = Color(hex: "#FF3B30")
    static let flat = Color(hex: "#8E8E93")
    static let star = Color(hex: "#FFCC00")
    static let breaking = Color(hex: "#FF3B30")
    static let importantDot = Color(hex: "#FFCC00")
    static let importantText = Color(light: "#B7950B", dark: "#FFD60A")
    static let ok = Color(hex: "#34C759")
    static let purple = Color(hex: "#AF52DE")
    /// The hover capsule (#1D1D1F).
    static let capsule = Color(light: "#1D1D1F", dark: "#48484A")
}

/// The sheet's search field: magnifier in a rounded grey field. `.popover` is 13pt in an 8pt-radius
/// field with 10/6 padding; `.list` is the window's 12pt field with 8/5 padding and a 6pt radius.
struct NativeProSearchField: View {
    enum Size { case popover, list }

    @Binding var text: String
    var placeholder: String
    var size: Size = .popover

    private var fontSize: CGFloat { size == .popover ? 13 : 12 }

    var body: some View {
        HStack(spacing: size == .popover ? 8 : 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: fontSize - 1, weight: .semibold))
                .foregroundStyle(NativeProPalette.textTertiary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: fontSize))
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: fontSize - 1))
                        .foregroundStyle(NativeProPalette.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Clear")
            }
        }
        .padding(.horizontal, size == .popover ? 10 : 8)
        .padding(.vertical, size == .popover ? 6 : 5)
        .background(NativeProPalette.field, in: RoundedRectangle(cornerRadius: size == .popover ? 8 : 6))
    }
}

/// The light rule between rows (the sheet's #F2F2F7).
struct NativeProHairline: View {
    var body: some View {
        Rectangle()
            .fill(NativeProPalette.hairline)
            .frame(height: 1)
    }
}

/// The heavier rule above the list and above the footer (the sheet's #E5E5EA).
struct NativeProRule: View {
    var body: some View {
        Rectangle()
            .fill(NativeProPalette.rule)
            .frame(height: 1)
    }
}

extension NativeProSearchField {
    /// "Search all 16,680 articles", or "Search articles" until the count is known.
    static func placeholder(totalArticles: Int) -> String {
        guard totalArticles > 0 else { return "Search articles" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        let n = formatter.string(from: NSNumber(value: totalArticles)) ?? "\(totalArticles)"
        return "Search all \(n) articles"
    }
}

// MARK: - Markets

/// The sheet's micro-sparkline: a 1.5pt round-capped line and nothing under it.
struct NativeProSparkline: View {
    let data: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            if data.count >= 2, let lo = data.min(), let hi = data.max() {
                let w = geo.size.width
                let h = geo.size.height - 2
                let range = hi - lo
                Path { path in
                    for (i, v) in data.enumerated() {
                        let x = w * CGFloat(i) / CGFloat(data.count - 1)
                        let y = range > 0 ? 1 + h - h * CGFloat((v - lo) / range) : 1 + h / 2
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

extension MarketRow {
    /// "0.0%" either way is flat, and the sheet draws it grey.
    var isFlat: Bool {
        guard let changeText else { return true }
        let digits = changeText.filter { $0.isNumber || $0 == "." }
        return Double(digits).map { $0 < 0.05 } ?? false
    }

    /// Change text: the sheet's darker green/red (#1E8E3E / #D93025), grey when flat.
    var changeColor: Color {
        guard !isFlat, let isUp else { return NativeProPalette.flat }
        return isUp ? NativeProPalette.up : NativeProPalette.down
    }

    /// The sparkline: system green/red (#34C759 / #FF3B30), grey when flat.
    var lineColor: Color {
        guard !isFlat, let isUp else { return NativeProPalette.flat }
        return isUp ? NativeProPalette.upLine : NativeProPalette.downLine
    }
}

/// The popover's markets strip as the sheet draws it: five equal columns in a #F5F5F7 card with an
/// 8pt radius, 7/6 padding and 4pt gaps; label 11 bold, change 11 semibold, price 12.5 bold, a 14pt
/// line-only sparkline. The price credit normally sits outside the card (the popover's header, the
/// window's bar); `credit` is the fallback, a 10pt line closing the card at the right in the meta grey.
struct NativeProMarketsStrip: View {
    let rows: [MarketRow]
    var credit: String? = nil

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            columns
            if let credit {
                MarketsCredit(text: credit, font: .system(size: 10), color: NativeProPalette.textTertiary)
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 6)
        .background(NativeProPalette.strip, in: RoundedRectangle(cornerRadius: 8))
    }

    private var columns: some View {
        HStack(spacing: 4) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 2) {
                        Text(row.label)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(NativeProPalette.textRead)
                            .lineLimit(1).fixedSize()
                        Spacer(minLength: 2)
                        if let change = row.changeText {
                            Text(change)
                                .font(.system(size: 11, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(row.changeColor)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                    Text(row.priceText)
                        .font(.system(size: 12.5, weight: .bold))
                        .monospacedDigit()
                        .tracking(-0.12)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    NativeProSparkline(data: row.sparkline, color: row.lineColor)
                        .frame(height: 14)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Since you last looked

/// Idea ① as the sheet draws it: a #F2F6FF band, "SINCE YOU LAST LOOKED · 4 NEW" 11pt bold blue,
/// a 2pt blue rule, and "last open 13:40" at the right. Text comes from `SinceLastLooked`.
struct NativeProSinceDivider: View {
    let newCount: Int
    let lastLooked: Date?
    var inset: CGFloat = 14

    private var parts: (head: String, time: String?) {
        let full = SinceLastLooked.dividerText(newCount: newCount, lastLooked: lastLooked)
        guard lastLooked != nil, let r = full.range(of: " · ", options: .backwards) else { return (full, nil) }
        return (String(full[..<r.lowerBound]), String(full[r.upperBound...]))
    }

    var body: some View {
        let p = parts
        HStack(spacing: 8) {
            Text(p.head.uppercased())
                .font(.system(size: 11, weight: .bold))
                .kerning(0.66)
                .foregroundStyle(NativeProPalette.blue)
                .lineLimit(1)
                .fixedSize()
            Capsule().fill(NativeProPalette.blue).frame(height: 2)
            if let time = p.time {
                Text("last open \(time)")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(NativeProPalette.textTertiary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, inset)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(NativeProPalette.sinceBand)
    }
}

// MARK: - Status line

/// Idea ③ as the sheet's footer draws it: a 7pt tier dot, then "AC · polled 2m ago · next in 3m ·
/// 18 requests, 0.6 MB" at 11pt with the tier word in the text colour, refreshed every 30 s.
struct NativeProStatusLine: View {
    @Environment(FeedEngine.self) private var engine
    @ObservedObject private var power = PowerMonitor.shared
    @State private var now = Date()

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(dotColor).frame(width: 7, height: 7)
            lineText
                .font(.system(size: 11))
                .monospacedDigit()
                .lineLimit(1)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                now = Date()
            }
        }
    }

    private var lineText: Text {
        let line = StatusLine.format(
            tier: power.tier, now: now, lastTickAt: engine.lastTickAt, nextTickAt: engine.nextTickAt,
            requests: engine.lastTickStats?.requests, bytes: engine.lastTickStats?.bytes)
        guard let r = line.range(of: " · ") else {
            return Text(line).fontWeight(.semibold).foregroundStyle(NativeProPalette.text)
        }
        return Text(line[..<r.lowerBound]).fontWeight(.semibold).foregroundStyle(NativeProPalette.text)
            + Text(line[r.lowerBound...]).foregroundStyle(NativeProPalette.textSecondary)
    }

    private var dotColor: Color {
        switch power.tier {
        case .ac: return NativeProPalette.ok
        case .battery: return NativeProPalette.importantDot
        case .critical: return NativeProPalette.breaking
        }
    }
}

// MARK: - Window chrome

/// The sheet draws the main window and Settings with the traffic lights inside the sidebar and no
/// title bar. Attach as a background: it makes the host window's title bar transparent and lets the
/// content run under it, so the sidebar carries the lights.
struct NativeProWindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ChromeView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class ChromeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
        }
    }
}
