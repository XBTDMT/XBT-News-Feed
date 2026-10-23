import SwiftUI
import Sparkle

/// Stream settings, 620×560: a white 48pt toolbar with "Settings" and the coral pill tab bar
/// (Sources · AI · Notifications · General) at its right, then the pane in one card on the canvas.
/// General carries Power and the Design picker. `PULSEFEED_DEBUG_SETTINGS_PANE` picks the tab.
struct StreamSettings: View {
    enum Tab: String, CaseIterable, Identifiable {
        case sources, ai, notifications, general

        var id: String { rawValue }

        var title: String {
            switch self {
            case .sources: return "Sources"
            case .ai: return "AI"
            case .notifications: return "Notifications"
            case .general: return "General"
            }
        }
    }

    let appDB: AppDatabase
    let updater: SPUStandardUpdaterController
    @Environment(\.designTokens) private var tokens
    @State private var tab: Tab

    init(appDB: AppDatabase, updater: SPUStandardUpdaterController) {
        self.appDB = appDB
        self.updater = updater
        _tab = State(initialValue: Self.initialTab)
    }

    private static var initialTab: Tab {
        switch DebugOpen.settingsPane {
        case .sources: return .sources
        case .intelligence: return .ai
        case .notifications: return .notifications
        case .power, .general: return .general
        case nil: return .sources
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            pane
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
        }
        .background(tokens.canvas)
        .frame(width: 620, height: 560)
        .tint(tokens.accent)
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            Text("Settings").padding(.leading, 62)
                .font(tokens.font(14, weight: .heavy))
                .lineLimit(1)
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                ForEach(Tab.allCases) { item in
                    let isSelected = item == tab
                    Button {
                        tab = item
                    } label: {
                        Text(item.title)
                            .font(tokens.font(12, weight: isSelected ? .bold : .semibold))
                            .foregroundStyle(isSelected ? Color.white : StreamPalette.ink)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 12)
                            .frame(height: 24)
                            .background(isSelected ? tokens.accent : Color.clear, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(tokens.canvas, in: Capsule())
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(tokens.card)
        .overlay(alignment: .bottom) { Rectangle().fill(tokens.cardBorder).frame(height: 1) }
    }

    @ViewBuilder
    private var pane: some View {
        Group {
            switch tab {
            case .sources: SourcesSettingsTab(appDB: appDB)
            case .ai: AISettingsTab(appDB: appDB)
            case .notifications: NotificationsSettingsTab()
            case .general: GeneralSettingsTab(appDB: appDB, updaterController: updater, includePower: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .streamCard()
    }
}
