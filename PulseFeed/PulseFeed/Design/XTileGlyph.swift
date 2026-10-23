import SwiftUI
import AppKit

/// The master icon's letter — the "X" of Archivo Black (SIL OFL) outlined to its 14 points, so the
/// app never needs the font. Placed as on the design sheet (option 4, "X-Tile"): 900 px on a
/// 1024 px tile, centred at x 512, baseline at y 830.
enum XTileGlyph {
    /// Font units (1000 per em, y up), in outline order.
    static let fontPoints: [(x: Double, y: Double)] = [
        (778, 0), (510, 0), (383, 214), (379, 214), (252, 0), (4, 0), (250, 364),
        (28, 688), (295, 688), (399, 512), (403, 512), (508, 688), (755, 688), (532, 363),
    ]
    static let advance: Double = 778
    static let fontSize: Double = 900
    static let baseline: Double = 830

    /// The outline in icon space (1024 × 1024, y down).
    static let points: [CGPoint] = {
        let scale = fontSize / 1000
        let originX = 512 - advance * scale / 2
        return fontPoints.map { CGPoint(x: originX + $0.x * scale, y: baseline - $0.y * scale) }
    }()

    static let bounds: CGRect = path(in: 1024).boundingRect

    /// The closed outline scaled to a tile `size` points square.
    static func path(in size: CGFloat) -> Path {
        let k = size / 1024
        var p = Path()
        p.move(to: CGPoint(x: points[0].x * k, y: points[0].y * k))
        for pt in points.dropFirst() { p.addLine(to: CGPoint(x: pt.x * k, y: pt.y * k)) }
        p.closeSubpath()
        return p
    }

    // The sheet's colours: the Deck tiles woven through the letter — warm along the back-slash
    // arm (red into amber), cool along the forward-slash arm (green into blue) — on a lifted
    // near-black ground with a faint rim so the tile keeps its edge on a dark Dock.
    static let warm = [Color(hex: "#FF3B30"), Color(hex: "#E8B931")]
    static let cool = [Color(hex: "#34C759"), Color(hex: "#0A84FF")]
    static let groundTop = Color(hex: "#30333C")
    static let groundBottom = Color(hex: "#1E2026")

    /// The menu bar item: the same letter as an 18 pt template image (the menu bar tints it).
    @MainActor static let menuBarImage: NSImage = {
        let side: CGFloat = 18
        let glyph = bounds
        let k: CGFloat = 13 / glyph.width
        let dx = (side - glyph.width * k) / 2 - glyph.minX * k
        let dy = (side - glyph.height * k) / 2 - glyph.minY * k
        let pts = points.map { NSPoint(x: $0.x * k + dx, y: $0.y * k + dy) }
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { _ in
            let p = NSBezierPath()
            p.move(to: pts[0])
            for pt in pts.dropFirst() { p.line(to: pt) }
            p.close()
            NSColor.black.setFill()
            p.fill()
            return true
        }
        image.isTemplate = true
        return image
    }()

    // MARK: Option D — "turning quadrants" (2026-09-08)
    //
    // The same letter filled (white on a dark bar, the icon ground on a light one) with a coloured OUTLINE, with the icon's four-way colour
    // split rotating as a whole, clockwise, once per `quadrantsPeriod`. Not a template image, so the
    // menu bar does not tint it. `UserDefaults` "menubar_x_animation" (Settings › Power › Menu bar)
    // turns it on; off, the label shows the plain template letter as before.

    static let animationDefaultsKey = "menubar_x_animation"
    static let quadrantsPeriod: TimeInterval = 24
    static let quadrantsFPS: Double = 12
    /// Wedge colours, clockwise from the top-left arm-end: the Deck tiles.
    static let quadrantColors: [NSColor] = ["#FF3B30", "#34C759", "#E8B931", "#0A84FF"].map { NSColor(Color(hex: $0)) }

    nonisolated(unsafe) private static var frameCache: [Int: NSImage] = [:]

    /// The frame for `time` (seconds): the wedge split turned by `time / period` of a full turn.
    @MainActor static func quadrantsFrame(at time: TimeInterval) -> NSImage {
        let frames = Int(quadrantsPeriod * quadrantsFPS)
        let index = Int((time.truncatingRemainder(dividingBy: quadrantsPeriod) / quadrantsPeriod * Double(frames)).rounded(.down)) % frames
        if let cached = frameCache[index] { return cached }
        let image = renderQuadrants(turn: Double(index) / Double(frames))
        frameCache[index] = image
        return image
    }

    /// The outline stroked in four wedges (centre of the 18 pt square outwards), rotated by `turn` (0…1).
    private static func renderQuadrants(turn: Double) -> NSImage {
        let side: CGFloat = 18
        let glyph = bounds
        let k: CGFloat = 13 / glyph.width
        let dx = (side - glyph.width * k) / 2 - glyph.minX * k
        let dy = (side - glyph.height * k) / 2 - glyph.minY * k
        let pts = points.map { NSPoint(x: $0.x * k + dx, y: $0.y * k + dy) }
        let centre = NSPoint(x: side / 2, y: side / 2)
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { _ in
            let outline = NSBezierPath()
            outline.move(to: pts[0])
            for pt in pts.dropFirst() { outline.line(to: pt) }
            outline.close()
            outline.lineWidth = 48 * k
            outline.lineJoinStyle = .miter
            // Drawing-handler images are re-drawn per appearance: white letter on a dark menu bar,
            // the icon's ground on a light one.
            let dark = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            (dark ? NSColor.white : NSColor(groundBottom)).setFill()
            outline.fill()
            // Wedge 0 spans the top-left quarter (angles 180°…270° in flipped space) and turns clockwise.
            let base = Double.pi + turn * 2 * .pi
            for (i, color) in quadrantColors.enumerated() {
                let start = base + Double(i) * .pi / 2
                let wedge = NSBezierPath()
                wedge.move(to: centre)
                wedge.appendArc(withCenter: centre, radius: side, startAngle: start * 180 / .pi, endAngle: (start + .pi / 2) * 180 / .pi, clockwise: false)
                wedge.close()
                NSGraphicsContext.saveGraphicsState()
                wedge.addClip()
                color.setStroke()
                outline.stroke()
                NSGraphicsContext.restoreGraphicsState()
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
