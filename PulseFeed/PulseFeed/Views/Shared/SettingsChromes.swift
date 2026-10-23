import SwiftUI
import Sparkle

enum SettingsPane: String, CaseIterable, Identifiable {
    case sources, intelligence, notifications, power, general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sources: return "Sources"
        case .intelligence: return "Intelligence"
        case .notifications: return "Notifications"
        case .power: return "Power"
        case .general: return "General"
        }
    }

    var symbol: String {
        switch self {
        case .sources: return "list.bullet"
        case .intelligence: return "sparkles"
        case .notifications: return "bell"
        case .power: return "bolt"
        case .general: return "gear"
        }
    }
}

/// System Settings-style icon sidebar (Native Pro and Deck).
struct SidebarSettingsChrome: View {
    let appDB: AppDatabase
    let updater: SPUStandardUpdaterController
    @State private var pane: SettingsPane

    init(appDB: AppDatabase, updater: SPUStandardUpdaterController, initialPane: SettingsPane = .sources) {
        self.appDB = appDB
        self.updater = updater
        _pane = State(initialValue: DebugOpen.settingsPane ?? initialPane)
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $pane) { p in
                Label(p.title, systemImage: p.symbol).tag(p)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(170)
        } detail: {
            paneView(pane)
        }
        .frame(width: 640, height: 520)
    }

    @ViewBuilder
    private func paneView(_ pane: SettingsPane) -> some View {
        switch pane {
        case .sources: SourcesSettingsTab(appDB: appDB)
        case .intelligence: AISettingsTab(appDB: appDB)
        case .notifications: NotificationsSettingsTab()
        case .power: PowerPane()
        case .general: GeneralSettingsTab(appDB: appDB, updaterController: updater)
        }
    }
}

/// Tabs on the design's canvas colour with each pane in a card (Stream). Power lives inside General.
struct TabbedSettingsChrome: View {
    let appDB: AppDatabase
    let updater: SPUStandardUpdaterController
    @Environment(\.designTokens) private var tokens

    var body: some View {
        TabView {
            card { SourcesSettingsTab(appDB: appDB) }
                .tabItem { Label("Sources", systemImage: "list.bullet") }
            card { AISettingsTab(appDB: appDB) }
                .tabItem { Label("AI", systemImage: "sparkles") }
            card { NotificationsSettingsTab() }
                .tabItem { Label("Notifications", systemImage: "bell") }
            card { GeneralSettingsTab(appDB: appDB, updaterController: updater, includePower: true) }
                .tabItem { Label("General", systemImage: "gear") }
        }
        .padding(12)
        .background(tokens.canvas)
        .frame(width: 600, height: 540)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .background(tokens.card, in: RoundedRectangle(cornerRadius: tokens.radius))
            .overlay(RoundedRectangle(cornerRadius: tokens.radius).stroke(tokens.cardBorder, lineWidth: 1))
    }
}
