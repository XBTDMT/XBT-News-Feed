import AppKit
import Network

/// The fixture's story pictures, drawn in code (skies, seas, hills, a city, an arena; nothing downloaded, so
/// nothing to license) and served to the views' `AsyncImage` from memory by a small HTTP server on the loopback
/// address, started only in a showcase run (AsyncImage's session ignores a registered `URLProtocol`). Stream's
/// point is pictures where they earn their place; without these its README pictures showed flat placeholders.
/// Outside a showcase run (the fixture's tests) the URLs name the reserved host `pictures.example`.
enum ShowcasePictures {
    static let names = ["merrow", "sorrel", "comets", "trains", "ports", "bridge", "heat", "island", "stocks", "laptops"]

    static func url(_ name: String) -> String { "\(server.base ?? "https://pictures.example")/\(name).jpg" }

    /// Draws every picture once and starts the server. Showcase runs only, before the fixture is written.
    @MainActor
    static func install() {
        var data: [String: Data] = [:]
        for name in names { data[name] = jpeg(name) }
        server.start(serving: data)
    }

    static let server = Server()

    /// The picture a request line asks for: the last path component without its extension or query, read as
    /// text only (never a file-system path, so no request can make the server look at the disk).
    static func pictureName(requestLine: String) -> String {
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return "" }
        let path = String(parts[1].split(separator: "?", maxSplits: 1).first ?? "")
        return ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    /// One loopback listener answering `GET /<name>.jpg`; it never binds beyond 127.0.0.1.
    final class Server: @unchecked Sendable {
        private let lock = NSLock()
        private var pictures: [String: Data] = [:]
        private var listener: NWListener?
        private var port: UInt16?
        private let queue = DispatchQueue(label: "showcase.pictures")

        var base: String? {
            lock.lock(); defer { lock.unlock() }
            return port.map { "http://127.0.0.1:\($0)" }
        }

        func start(serving data: [String: Data]) {
            lock.lock(); pictures = data; lock.unlock()
            let params = NWParameters.tcp
            params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            guard let listener = try? NWListener(using: params) else { return }
            let ready = DispatchSemaphore(value: 0)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready, .failed, .cancelled: ready.signal()
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
            listener.start(queue: queue)
            _ = ready.wait(timeout: .now() + 5)
            lock.lock(); self.listener = listener; port = listener.port?.rawValue; lock.unlock()
        }

        private func serve(_ connection: NWConnection) {
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
                guard let self else { connection.cancel(); return }
                let line = data.flatMap { String(data: $0.prefix(512), encoding: .utf8) }?.components(separatedBy: "\r\n").first ?? ""
                let name = ShowcasePictures.pictureName(requestLine: line)
                self.lock.lock(); let body = self.pictures[name]; self.lock.unlock()
                var reply = Data((body == nil
                    ? "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                    : "HTTP/1.1 200 OK\r\nContent-Type: image/jpeg\r\nContent-Length: \(body!.count)\r\nConnection: close\r\n\r\n").utf8)
                if let body { reply.append(body) }
                connection.send(content: reply, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
    }

    // MARK: Drawing

    static let size = NSSize(width: 1280, height: 720)

    @MainActor
    static func jpeg(_ name: String) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        var rng = Seeded(name)
        draw(name, &rng)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.86])
    }

    /// A small deterministic generator, so every run draws the same pictures.
    struct Seeded {
        var state: UInt64
        init(_ name: String) { state = name.utf8.reduce(1469598103934665603) { ($0 ^ UInt64($1)) &* 1099511628211 } }
        mutating func next() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(state >> 33) / CGFloat(1 << 31)
        }
        mutating func range(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * next() }
    }

    static func c(_ hex: Int, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: a)
    }

    /// Vertical wash from `top` (at the top of `rect`) to `bottom`. The context is unflipped: y grows upward.
    static func wash(_ rect: NSRect, _ top: NSColor, _ bottom: NSColor) {
        NSGradient(starting: bottom, ending: top)?.draw(in: rect, angle: 90)
    }

    static func glow(_ center: NSPoint, _ radius: CGFloat, _ color: NSColor) {
        NSGradient(starting: color, ending: color.withAlphaComponent(0))?
            .draw(fromCenter: center, radius: 0, toCenter: center, radius: radius, options: [])
    }

    /// A ridge line across the picture, filled down to `floor`.
    static func ridge(base: CGFloat, amplitude: CGFloat, waves: Int, floor: CGFloat = 0, color: NSColor, _ rng: inout Seeded) {
        let w = size.width
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 0, y: floor))
        let phases = (0..<waves).map { _ in rng.range(0, .pi * 2) }
        let freqs = (0..<waves).map { i in CGFloat(i + 1) * rng.range(0.8, 1.6) }
        for x in stride(from: CGFloat(0), through: w, by: 8) {
            var y = base
            for i in 0..<waves { y += amplitude / CGFloat(i + 1) * sin(x / w * .pi * 2 * freqs[i] + phases[i]) }
            path.line(to: NSPoint(x: x, y: y))
        }
        path.line(to: NSPoint(x: w, y: floor))
        path.close()
        color.setFill()
        path.fill()
    }

    static func cloud(_ center: NSPoint, _ scale: CGFloat, _ color: NSColor) {
        color.setFill()
        for (dx, dy, r) in [(-60.0, 0.0, 46.0), (-10, 18, 58), (45, 4, 48), (85, -8, 34), (-95, -10, 30)] {
            NSBezierPath(ovalIn: NSRect(x: center.x + dx * scale - r * scale, y: center.y + dy * scale - r * scale * 0.7,
                                        width: r * scale * 2, height: r * scale * 1.4)).fill()
        }
    }

    static func draw(_ name: String, _ rng: inout Seeded) {
        let all = NSRect(origin: .zero, size: size), w = size.width, h = size.height
        switch name {
        case "merrow":   // an open model: nodes and links glowing on deep violet
            wash(all, c(0x1B1446), c(0x3B1C6E))
            glow(NSPoint(x: w * 0.7, y: h * 0.55), 520, c(0x8E5CFF, 0.55))
            glow(NSPoint(x: w * 0.2, y: h * 0.2), 380, c(0x2EC5FF, 0.35))
            let nodes = (0..<46).map { _ in NSPoint(x: rng.range(40, w - 40), y: rng.range(40, h - 40)) }
            for (i, a) in nodes.enumerated() {
                for b in nodes[(i + 1)...] where hypot(a.x - b.x, a.y - b.y) < 190 {
                    let line = NSBezierPath()
                    line.move(to: a); line.line(to: b)
                    line.lineWidth = 1.6
                    c(0xC9B8FF, 0.28).setStroke()
                    line.stroke()
                }
            }
            for p in nodes {
                let r = rng.range(3, 8)
                glow(p, r * 5, c(0xE4DAFF, 0.35))
                c(0xF4EEFF).setFill()
                NSBezierPath(ovalIn: NSRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)).fill()
            }
            for k in 0..<4 {
                let r = CGFloat(120 + k * 70)
                let ring = NSBezierPath(ovalIn: NSRect(x: w * 0.7 - r, y: h * 0.55 - r, width: r * 2, height: r * 2))
                ring.lineWidth = 2
                c(0xB79BFF, 0.22 - CGFloat(k) * 0.04).setStroke()
                ring.stroke()
            }
        case "sorrel":   // a calm sea at morning, an island on the horizon
            wash(NSRect(x: 0, y: h * 0.42, width: w, height: h * 0.58), c(0x8FB8E0), c(0xF6D7B8))
            glow(NSPoint(x: w * 0.62, y: h * 0.47), 300, c(0xFFF1D6, 0.9))
            ridge(base: h * 0.45, amplitude: 22, waves: 3, floor: h * 0.42, color: c(0x5B7189), &rng)
            wash(NSRect(x: 0, y: 0, width: w, height: h * 0.42), c(0x5E8FA8), c(0x1F4A63))
            for i in 0..<34 {
                let y = h * 0.42 * CGFloat(i) / 34, len = rng.range(60, 260)
                let x = rng.range(0, w - len)
                c(0xFFFFFF, 0.06 + 0.12 * CGFloat(i) / 34).setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: y, width: len, height: 3), xRadius: 1.5, yRadius: 1.5).fill()
            }
            c(0xFFF4DE, 0.5).setFill()
            NSBezierPath(rect: NSRect(x: w * 0.6, y: h * 0.12, width: 40, height: h * 0.3)).fill()
        case "comets":   // an arena at night: floodlights over a wooden court
            wash(all, c(0x0E1630), c(0x1D2A52))
            for i in 0..<5 {
                let p = NSPoint(x: w * (0.1 + 0.2 * CGFloat(i)), y: h * 0.9)
                glow(p, 260, c(0xFFF3C4, 0.45))
                c(0xFFFBEA).setFill()
                NSBezierPath(ovalIn: NSRect(x: p.x - 10, y: p.y - 10, width: 20, height: 20)).fill()
            }
            let floor = NSBezierPath()
            floor.move(to: NSPoint(x: 0, y: 0)); floor.line(to: NSPoint(x: w, y: 0))
            floor.line(to: NSPoint(x: w * 0.82, y: h * 0.42)); floor.line(to: NSPoint(x: w * 0.18, y: h * 0.42)); floor.close()
            NSGraphicsContext.saveGraphicsState(); floor.addClip()
            wash(NSRect(x: 0, y: 0, width: w, height: h * 0.42), c(0xD9A066), c(0x9C5E2C))
            NSGraphicsContext.restoreGraphicsState()
            let arc = NSBezierPath()
            arc.appendArc(withCenter: NSPoint(x: w / 2, y: h * 0.42), radius: 150, startAngle: 180, endAngle: 360)
            arc.lineWidth = 5; c(0xFFFFFF, 0.8).setStroke(); arc.stroke()
            let mid = NSBezierPath(); mid.move(to: NSPoint(x: w / 2, y: 0)); mid.line(to: NSPoint(x: w / 2, y: h * 0.42))
            mid.lineWidth = 5; mid.stroke()
            for _ in 0..<160 {   // the crowd
                let p = NSPoint(x: rng.range(0, w), y: rng.range(h * 0.44, h * 0.7))
                c([0xF25F5C, 0xFFE066, 0x70C1B3, 0xFFFFFF][Int(rng.range(0, 3.99))], 0.35).setFill()
                NSBezierPath(ovalIn: NSRect(x: p.x, y: p.y, width: 6, height: 6)).fill()
            }
        case "trains":   // dusk over hills, a lit train crossing
            wash(all, c(0x3D2C6B), c(0xF29E6D))
            glow(NSPoint(x: w * 0.3, y: h * 0.38), 240, c(0xFFD8A8, 0.8))
            ridge(base: h * 0.46, amplitude: 50, waves: 3, color: c(0x5A3F78), &rng)
            ridge(base: h * 0.34, amplitude: 40, waves: 3, color: c(0x3B2A57), &rng)
            c(0x241A38).setFill()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: w, height: h * 0.25)).fill()
            c(0x15101F).setFill()
            NSBezierPath(rect: NSRect(x: 0, y: h * 0.25, width: w, height: 6)).fill()
            for i in 0..<9 {
                let x = w * 0.18 + CGFloat(i) * 92
                c(0x15101F).setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: h * 0.25 + 6, width: 86, height: 40), xRadius: 6, yRadius: 6).fill()
                for k in 0..<4 {
                    c(0xFFD27A, 0.95).setFill()
                    NSBezierPath(rect: NSRect(x: x + 8 + CGFloat(k) * 19, y: h * 0.25 + 26, width: 12, height: 10)).fill()
                }
            }
        case "ports":    // a harbour after a storm: grey sky clearing, cranes on the quay
            wash(all, c(0x9DB0C2), c(0xDCE3E8))
            for _ in 0..<6 { cloud(NSPoint(x: rng.range(0, w), y: rng.range(h * 0.6, h * 0.95)), rng.range(0.8, 1.6), c(0xFFFFFF, 0.55)) }
            wash(NSRect(x: 0, y: 0, width: w, height: h * 0.32), c(0x6E8DA3), c(0x34536A))
            c(0x2B3B48).setFill()
            NSBezierPath(rect: NSRect(x: 0, y: h * 0.32, width: w, height: 18)).fill()
            for i in 0..<4 {
                let x = w * (0.18 + 0.2 * CGFloat(i)), top = h * rng.range(0.62, 0.75)
                let crane = NSBezierPath()
                crane.move(to: NSPoint(x: x, y: h * 0.32)); crane.line(to: NSPoint(x: x, y: top))
                crane.move(to: NSPoint(x: x - 60, y: top)); crane.line(to: NSPoint(x: x + 140, y: top))
                crane.move(to: NSPoint(x: x + 120, y: top)); crane.line(to: NSPoint(x: x + 120, y: top - 90))
                crane.lineWidth = 9; c(0xD9643A).setStroke(); crane.stroke()
            }
            for i in 0..<14 {
                c([0x3A7CA5, 0xD9643A, 0xF2C14E, 0x5B8E7D][i % 4]).setFill()
                NSBezierPath(rect: NSRect(x: 40 + CGFloat(i) * 52, y: h * 0.32 + 18, width: 48, height: 24)).fill()
            }
        case "bridge":   // a long timber footbridge at sunset
            wash(all, c(0xF08A5D), c(0xFCE3B0))
            glow(NSPoint(x: w * 0.5, y: h * 0.45), 320, c(0xFFF4D6, 0.85))
            ridge(base: h * 0.4, amplitude: 14, waves: 4, color: c(0x7A4E5A), &rng)
            for i in 0..<18 {   // the old town
                let bw = rng.range(30, 70), bh = rng.range(30, 120)
                c(0x5E3A48).setFill()
                NSBezierPath(rect: NSRect(x: CGFloat(i) * 72, y: h * 0.38, width: bw, height: bh)).fill()
            }
            wash(NSRect(x: 0, y: 0, width: w, height: h * 0.38), c(0xE7A27A), c(0x8C5A6B))
            let deck = NSBezierPath()
            deck.move(to: NSPoint(x: -20, y: h * 0.3))
            deck.curve(to: NSPoint(x: w + 20, y: h * 0.3), controlPoint1: NSPoint(x: w * 0.3, y: h * 0.42),
                       controlPoint2: NSPoint(x: w * 0.7, y: h * 0.42))
            deck.lineWidth = 14; c(0x3B2430).setStroke(); deck.stroke()
            for i in 1..<12 {
                let x = w * CGFloat(i) / 12
                let leg = NSBezierPath(); leg.move(to: NSPoint(x: x, y: 0)); leg.line(to: NSPoint(x: x, y: h * 0.33 + sin(CGFloat(i) / 12 * .pi) * h * 0.06))
                leg.lineWidth = 6; leg.stroke()
            }
        case "heat":     // a hot sky easing over flat fields
            wash(all, c(0xF5B65B), c(0xFBE8C4))
            glow(NSPoint(x: w * 0.72, y: h * 0.72), 260, c(0xFFF8E1, 0.95))
            c(0xFFF9EC).setFill()
            NSBezierPath(ovalIn: NSRect(x: w * 0.72 - 70, y: h * 0.72 - 70, width: 140, height: 140)).fill()
            for i in 0..<9 {
                let y0 = h * 0.4 * CGFloat(i) / 9
                c([0xC9A24A, 0xA9B65A, 0xD8B865, 0x8FA34B][i % 4]).setFill()
                NSBezierPath(rect: NSRect(x: 0, y: y0, width: w, height: h * 0.4 / 9 + 1)).fill()
            }
            ridge(base: h * 0.41, amplitude: 6, waves: 3, floor: h * 0.38, color: c(0x7E8F45), &rng)
        case "island":   // turquoise water and an island
            wash(all, c(0x4FA9E8), c(0xBFE6F6))
            for _ in 0..<4 { cloud(NSPoint(x: rng.range(0, w), y: rng.range(h * 0.7, h * 0.92)), rng.range(0.7, 1.2), c(0xFFFFFF, 0.8)) }
            wash(NSRect(x: 0, y: 0, width: w, height: h * 0.45), c(0x34C3C9), c(0x0F6E8C))
            let island = NSBezierPath(ovalIn: NSRect(x: w * 0.35, y: h * 0.36, width: w * 0.36, height: h * 0.2))
            c(0xF3E0B5).setFill(); island.fill()
            let green = NSBezierPath(ovalIn: NSRect(x: w * 0.4, y: h * 0.42, width: w * 0.26, height: h * 0.2))
            c(0x2E8B57).setFill(); green.fill()
        case "stocks":   // a rising line on a dark trading screen
            wash(all, c(0x0B1F1A), c(0x123A2F))
            for i in 0..<9 {
                let y = h * CGFloat(i) / 8
                c(0xFFFFFF, 0.06).setFill(); NSBezierPath(rect: NSRect(x: 0, y: y, width: w, height: 1.5)).fill()
            }
            let line = NSBezierPath()
            var y = h * 0.3
            line.move(to: NSPoint(x: 0, y: y))
            for x in stride(from: CGFloat(24), through: w, by: 24) {
                y = min(h * 0.85, max(h * 0.15, y + rng.range(-22, 30)))
                line.line(to: NSPoint(x: x, y: y))
            }
            let fill = line.copy() as! NSBezierPath
            fill.line(to: NSPoint(x: w, y: 0)); fill.line(to: NSPoint(x: 0, y: 0)); fill.close()
            NSGraphicsContext.saveGraphicsState(); fill.addClip()
            wash(all, c(0x34C759, 0.35), c(0x34C759, 0))
            NSGraphicsContext.restoreGraphicsState()
            line.lineWidth = 5; c(0x5CF08A).setStroke(); line.stroke()
        default:         // laptops: a product shot on a soft grey sweep
            wash(all, c(0xF4F5F7), c(0xC9CDD4))
            glow(NSPoint(x: w * 0.5, y: h * 0.6), 420, c(0xFFFFFF, 0.8))
            let shadow = NSShadow()
            shadow.shadowBlurRadius = 40; shadow.shadowOffset = NSSize(width: 0, height: -18)
            shadow.shadowColor = c(0x000000, 0.3)
            NSGraphicsContext.saveGraphicsState(); shadow.set()
            c(0x2B2E33).setFill()
            NSBezierPath(roundedRect: NSRect(x: w * 0.27, y: h * 0.36, width: w * 0.46, height: h * 0.44), xRadius: 18, yRadius: 18).fill()
            c(0xA8ADB5).setFill()
            NSBezierPath(roundedRect: NSRect(x: w * 0.22, y: h * 0.28, width: w * 0.56, height: h * 0.08), xRadius: 10, yRadius: 10).fill()
            NSGraphicsContext.restoreGraphicsState()
            wash(NSRect(x: w * 0.29, y: h * 0.39, width: w * 0.42, height: h * 0.38), c(0x7DD3FC), c(0x6366F1))
        }
    }
}
