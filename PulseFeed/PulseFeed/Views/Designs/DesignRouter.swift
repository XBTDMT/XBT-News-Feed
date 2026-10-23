import SwiftUI
import Sparkle

/// The only place that names all three designs. Callers pass `AppDesign.current`; the engine is
/// injected by the caller, the tokens here.
@MainActor
extension AppDesign {
    var popoverSize: CGSize {
        switch self {
        case .nativePro: return CGSize(width: 420, height: 640)
        case .deck: return CGSize(width: 400, height: 600)
        case .stream: return CGSize(width: 420, height: 660)
        }
    }

    var mainWindowMinSize: CGSize {
        switch self {
        case .nativePro: return CGSize(width: 900, height: 600)
        case .deck: return CGSize(width: 1280, height: 720)   // the D2 Board's six columns (the window option chosen on 2026-09-07)
        case .stream: return CGSize(width: 1100, height: 720)
        }
    }

    /// The size a fresh main window opens at (the sheets' window frames); the user's autosaved frame wins after that.
    var mainWindowDefaultSize: CGSize {
        switch self {
        case .nativePro: return CGSize(width: 1144, height: 760)
        case .deck: return CGSize(width: 1440, height: 900)
        case .stream: return CGSize(width: 1280, height: 820)
        }
    }

    var readerTheme: ReaderTheme {
        switch self {
        case .nativePro, .deck: return .dark(link: "#0A84FF")
        case .stream: return .light(link: "#F2634F")
        }
    }

    @ViewBuilder
    func popover(appDB: AppDatabase, updater: SPUStandardUpdaterController) -> some View {
        Group {
            switch self {
            case .nativePro: NativeProPopover(appDB: appDB, updater: updater)
            case .deck: DeckPopover(appDB: appDB, updater: updater)
            case .stream: StreamPopover(appDB: appDB, updater: updater)
            }
        }
        .environment(\.designTokens, tokens)
    }

    @ViewBuilder
    func mainWindow(appDB: AppDatabase) -> some View {
        Group {
            switch self {
            case .nativePro: NativeProWindow(appDB: appDB)
            case .deck: DeckWindow(appDB: appDB)
            case .stream: StreamWindow(appDB: appDB)
            }
        }
        .environment(\.designTokens, tokens)
    }

    @ViewBuilder
    func settings(appDB: AppDatabase, updater: SPUStandardUpdaterController) -> some View {
        Group {
            switch self {
            case .nativePro: NativeProSettings(appDB: appDB, updater: updater)
            case .deck: DeckSettings(appDB: appDB, updater: updater)
            case .stream: StreamSettings(appDB: appDB, updater: updater)
            }
        }
        .environment(\.designTokens, tokens)
    }

    @ViewBuilder
    func widget(appDB: AppDatabase) -> some View {
        Group {
            switch self {
            case .nativePro: NativeProWidget(appDB: appDB)
            case .deck: DeckWidget(appDB: appDB)
            case .stream: StreamWidget(appDB: appDB)
            }
        }
        .environment(\.designTokens, tokens)
    }
}
