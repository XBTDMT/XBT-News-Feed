import SwiftUI

/// Idea ③: "AC · polled 2m ago · next in 3m · 18 requests, 0.6 MB" with a tier dot.
struct StatusFooterView: View {
    @Environment(FeedEngine.self) private var engine
    @Environment(\.designTokens) private var tokens
    @ObservedObject private var power = PowerMonitor.shared
    @State private var now = Date()

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: tierSymbol).font(.system(size: 10)).foregroundStyle(tokens.secondaryText)
            Circle().fill(dotColor).frame(width: 7, height: 7)
            Text(line)
                .font(tokens.font(11)).monospacedDigit()
                .foregroundStyle(tokens.secondaryText)
                .lineLimit(1)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                now = Date()
            }
        }
    }

    private var line: String {
        StatusLine.format(
            tier: power.tier, now: now, lastTickAt: engine.lastTickAt, nextTickAt: engine.nextTickAt,
            requests: engine.lastTickStats?.requests, bytes: engine.lastTickStats?.bytes)
    }

    private var tierSymbol: String {
        switch power.tier {
        case .ac: return "powerplug"
        case .battery: return "battery.50percent"
        case .critical: return "battery.25percent"
        }
    }

    private var dotColor: Color {
        switch power.tier {
        case .ac: return tokens.ok
        case .battery: return tokens.important
        case .critical: return tokens.breaking
        }
    }
}
