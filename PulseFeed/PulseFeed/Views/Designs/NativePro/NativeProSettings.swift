import SwiftUI
import Sparkle

/// Native Pro settings as the sheet draws it: a 190pt #EFEFF2 sidebar carrying the traffic lights
/// (no title bar), five rows with 18pt coloured icon squares, the selected one #0A84FF; the pane
/// content on #F5F5F7. The panes themselves are the shared `SettingsPanes`.
struct NativeProSettings: View {
    let appDB: AppDatabase
    let updater: SPUStandardUpdaterController
    @State private var pane: SettingsPane

    init(appDB: AppDatabase, updater: SPUStandardUpdaterController) {
        self.appDB = appDB
        self.updater = updater
        _pane = State(initialValue: DebugOpen.settingsPane ?? .sources)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 190)
            paneView(pane)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scrollContentBackground(.hidden)
                .background(NativeProPalette.settingsCanvas.ignoresSafeArea())
        }
        // Fills the host window (the chrome below makes it full-size-content, so the sidebar
        // runs up under the traffic lights); the shared controller opens it at 640×520.
        .frame(minWidth: 640, minHeight: 520)
        .background(NativeProWindowChrome())
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsPane.allCases) { p in
                sidebarRow(p)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            // Under the transparent title bar too, so the traffic lights sit on #EFEFF2.
            ZStack(alignment: .trailing) {
                NativeProPalette.sidebar
                NativeProPalette.sidebarBorder.frame(width: 1)
            }
            .ignoresSafeArea()
        }
    }

    /// One row: an 18pt icon square (5pt radius) in the pane's colour with a white glyph, 13pt
    /// label, 6/8 padding, 6pt radius. Selected: #0A84FF row, white text, white square, blue glyph.
    private func sidebarRow(_ p: SettingsPane) -> some View {
        let isSelected = pane == p
        let tint = Self.tint(p)
        return Button {
            pane = p
        } label: {
            HStack(spacing: 8) {
                Image(systemName: Self.glyph(p))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isSelected ? tint : Color.white)
                    .frame(width: 18, height: 18)
                    .background(isSelected ? Color.white : tint, in: RoundedRectangle(cornerRadius: 5))
                Text(p.title)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? Color.white : NativeProPalette.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(isSelected ? NativeProPalette.blue : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The sheet's icon colours: Sources blue, Intelligence #AF52DE, Notifications #FF3B30,
    /// Power #34C759, General #8E8E93.
    private static func tint(_ p: SettingsPane) -> Color {
        switch p {
        case .sources: return NativeProPalette.blue
        case .intelligence: return NativeProPalette.purple
        case .notifications: return NativeProPalette.breaking
        case .power: return NativeProPalette.ok
        case .general: return NativeProPalette.flat
        }
    }

    private static func glyph(_ p: SettingsPane) -> String {
        switch p {
        case .sources: return "dot.radiowaves.up.forward"
        case .intelligence: return "sparkles"
        case .notifications: return "bell.fill"
        case .power: return "bolt.fill"
        case .general: return "gearshape.fill"
        }
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
