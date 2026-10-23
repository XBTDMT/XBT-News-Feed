import SwiftUI
import AppKit

/// The app icon for each design, drawn from the sheets' "Icons" panels at 1024×1024.
struct AppIconArt: View {
    let design: AppDesign

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 225, style: .continuous).fill(background)
            switch design {
            case .nativePro:
                Image(systemName: "newspaper.fill")
                    .font(.system(size: 520, weight: .medium))
                    .foregroundStyle(.white)
            case .deck:
                VStack(spacing: 40) {
                    HStack(spacing: 40) { tile(Color(hex: "#FF3B30")); tile(Color(hex: "#34C759")) }
                    HStack(spacing: 40) { tile(Color(hex: "#E8B931")); tile(Color(hex: "#0A84FF")) }
                }
            case .stream:
                ZStack {
                    card().rotationEffect(.degrees(-8)).offset(x: -70, y: 30)
                    card().rotationEffect(.degrees(0)).offset(x: 0, y: 0)
                    card().rotationEffect(.degrees(8)).offset(x: 70, y: -30)
                }
            }
        }
        .frame(width: 1024, height: 1024)
    }

    private var background: Color {
        switch design {
        case .nativePro: return Color(hex: "#0A84FF")
        case .deck: return Color(hex: "#F3F4F7")
        case .stream: return Color(hex: "#F2634F")
        }
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

enum AppIconRenderer {
    @MainActor
    static func image(for design: AppDesign) -> NSImage? {
        image(for: AppIconStyle.auto(for: design))
    }

    @MainActor
    static func image(for style: AppIconStyle) -> NSImage? {
        let renderer = ImageRenderer(content: AppIconStyleArt(style: style))
        renderer.proposedSize = ProposedViewSize(width: 1024, height: 1024)
        return renderer.nsImage
    }

    /// Writes a style at exactly 1024 × 1024 px as PNG — the master's source for AppIcon.icns
    /// (`make icon`), so the bundle icon is the app's own drawing and nothing else.
    @MainActor
    static func writePNG(style: AppIconStyle, to url: URL) -> Bool {
        let renderer = ImageRenderer(content: AppIconStyleArt(style: style))
        renderer.proposedSize = ProposedViewSize(width: 1024, height: 1024)
        renderer.scale = 1
        guard let cg = renderer.cgImage,
              let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return false }
        do { try data.write(to: url); return true } catch {
            print("PulseFeed: [Icon] write failed: \(error)")
            return false
        }
    }
}

/// Applies the running design's icon to the .app as a Finder custom icon (an extended attribute;
/// the bundle's contents and signature are untouched) and to the running process.
enum AppIcon {
    @MainActor
    static func apply() {
        let style = AppIconStyle.current
        let inBundle = Bundle.main.bundleURL.pathExtension == "app"
        if style.isMaster {
            // The master is baked into AppIcon.icns, which Finder, the Dock and notification banners
            // all read through LaunchServices; drop any custom Finder icon an earlier choice left.
            NSApp.applicationIconImage = nil
            if inBundle { _ = NSWorkspace.shared.setIcon(nil, forFile: Bundle.main.bundlePath, options: []) }
            print("PulseFeed: [Icon] master \(style.rawValue) from AppIcon.icns")
            return
        }
        guard let image = AppIconRenderer.image(for: style) else {
            print("PulseFeed: [Icon] render failed for \(style.rawValue)")
            return
        }
        NSApp.applicationIconImage = image
        guard inBundle else {
            print("PulseFeed: [Icon] not running from a .app bundle; Finder icon unchanged")
            return
        }
        let ok = NSWorkspace.shared.setIcon(image, forFile: Bundle.main.bundlePath, options: [])
        print("PulseFeed: [Icon] \(style.rawValue) icon applied to bundle: \(ok)")
    }
}
