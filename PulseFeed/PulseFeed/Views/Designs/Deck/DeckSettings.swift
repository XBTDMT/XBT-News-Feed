import SwiftUI
import Sparkle

/// Deck settings: the System Settings-style sidebar the sheet draws — a coloured rounded-square
/// icon per pane, 190pt wide, opening on Power — with the shared pane content on the right.
/// Power is drawn here so it matches the sheet's cards; the other panes are the shared forms.
struct DeckSettings: View {
    let appDB: AppDatabase
    let updater: SPUStandardUpdaterController
    @State private var pane: SettingsPane

    init(appDB: AppDatabase, updater: SPUStandardUpdaterController) {
        self.appDB = appDB
        self.updater = updater
        _pane = State(initialValue: DebugOpen.settingsPane ?? .power)
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $pane) { p in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Self.iconColor(p))
                        .frame(width: 18, height: 18)
                        .overlay {
                            Image(systemName: p.symbol)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    Text(p.title)
                }
                .tag(p)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(190)
        } detail: {
            paneView(pane)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(light: "#F5F5F7", dark: "#1E1E1E"))
        }
        .frame(width: 640, height: 520)
    }

    private static func iconColor(_ pane: SettingsPane) -> Color {
        switch pane {
        case .sources: return Color(hex: "#0A84FF")
        case .intelligence: return Color(hex: "#AF52DE")
        case .notifications: return Color(hex: "#FF3B30")
        case .power: return Color(hex: "#34C759")
        case .general: return Color(hex: "#8E8E93")
        }
    }

    @ViewBuilder
    private func paneView(_ pane: SettingsPane) -> some View {
        switch pane {
        case .sources: SourcesSettingsTab(appDB: appDB)
        case .intelligence: AISettingsTab(appDB: appDB)
        case .notifications: NotificationsSettingsTab()
        case .power: ScrollView { DeckPowerPane() }
        case .general: GeneralSettingsTab(appDB: appDB, updaterController: updater)
        }
    }
}

/// The Power pane as the sheet draws it: a "Power" title, one card with the tier row (name, level
/// and a status dot over its caption), the battery and low-battery schedules, then a MENU BAR card
/// carrying the BTC capsule switch with a live preview, and the last-poll line underneath.
struct DeckPowerPane: View {
    /// Optional: the settings window does not inject the engine; the preview and the poll line
    /// then fall back to placeholders.
    @Environment(FeedEngine.self) private var engine: FeedEngine?
    @ObservedObject private var power = PowerMonitor.shared
    @AppStorage("menubar_btc_capsule") private var btcCapsule = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Power").font(.system(size: 20, weight: .bold))

            card {
                cardRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tierTitle).font(.system(size: 13, weight: .semibold))
                        Text(tierCaption).font(.system(size: 11)).foregroundStyle(DeckPalette.tertiary)
                    }
                } trailing: {
                    Circle().fill(tierColor).frame(width: 10, height: 10)
                }
                DeckRule()
                cardRow {
                    Text("On battery, poll every").font(.system(size: 13))
                } trailing: {
                    valueChip("5 min")
                }
                DeckRule()
                cardRow {
                    Text("Below 20%: news only, every 30 min").font(.system(size: 13))
                } trailing: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(DeckPalette.green)
                        .help("Always on: RSS only, no quotes, no AI, until charging")
                }
            }

            Text("MENU BAR")
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.66)
                .foregroundStyle(DeckPalette.tertiary)
                .padding(.top, 2)

            card {
                cardRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("BTC change beside the icon").font(.system(size: 13, weight: .semibold))
                        Text("A small capsule; the breaking dot stays either way. Hidden on battery.")
                            .font(.system(size: 11)).foregroundStyle(DeckPalette.tertiary)
                    }
                } trailing: {
                    HStack(spacing: 10) {
                        capsulePreview
                        Toggle("BTC change beside the icon", isOn: $btcCapsule)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                }
            }

            Text("DATA SOURCES")
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.66)
                .foregroundStyle(DeckPalette.tertiary)
                .padding(.top, 2)

            card {
                DataSourcesContent().padding(14)
            }

            Text(lastPollLine)
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(DeckPalette.tertiary)
                .lineLimit(1)
        }
        .padding(EdgeInsets(top: 36, leading: 24, bottom: 20, trailing: 24))
    }

    // MARK: - Pieces

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(DeckPalette.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(DeckPalette.listRule, lineWidth: 1))
    }

    private func cardRow<Leading: View, Trailing: View>(
        @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 12) {
            leading()
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func valueChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(DeckPalette.card, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(light: "#D2D2D7", dark: "#48484A"), lineWidth: 1))
    }

    /// The menu bar item at 1:1 — glyph plus the live BTC capsule — so the switch shows what it does.
    private var capsulePreview: some View {
        HStack(spacing: 5) {
            Image(systemName: "square.grid.2x2").font(.system(size: 13, weight: .medium))
            if let change = engine?.latestPrices["bitcoin"]?.change24h, let text = PriceFormatting.change(change) {
                DeckChangeCapsule(text: text, isUp: change >= 0)
            } else {
                DeckChangeCapsule(text: "+0.0%", isUp: nil)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
        .opacity(btcCapsule ? 1 : 0.5)
    }

    private var tierTitle: String {
        let base: String
        switch power.tier {
        case .ac: base = "AC Power"
        case .battery: base = "Battery"
        case .critical: base = "Low battery"
        }
        if let level = power.batteryLevel { return "\(base) · \(Int(level * 100))%" }
        return base
    }

    private var tierCaption: String {
        switch power.tier {
        case .ac: return "Each source polls on its own schedule (1 min floor). Live prices."
        case .battery: return "Every source polls every 5 minutes. Quotes every 30 minutes."
        case .critical: return "RSS only, every 30 minutes. No quotes, no AI, until charging."
        }
    }

    private var tierColor: Color {
        switch power.tier {
        case .ac: return DeckPalette.green
        case .battery: return DeckPalette.gold
        case .critical: return DeckPalette.red
        }
    }

    /// "Last poll 2m ago · 18 sources · 18 requests · 0.6 MB"; parts we do not have are omitted.
    private var lastPollLine: String {
        var parts: [String] = []
        if let at = engine?.lastTickAt {
            parts.append("Last poll \(StatusLine.relative(Date().timeIntervalSince(at))) ago")
        }
        if let stats = engine?.lastTickStats {
            parts.append("\(stats.feeds) sources")
            parts.append("\(stats.requests) requests")
            parts.append(StatusLine.megabytes(stats.bytes))
        }
        return parts.isEmpty ? "No poll yet" : parts.joined(separator: " · ")
    }
}
