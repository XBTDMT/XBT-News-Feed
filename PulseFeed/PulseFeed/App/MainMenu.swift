import AppKit
import Sparkle

/// The app is a menu bar utility (LSUIElement), so it has no main menu and no Dock tile. While the
/// main window is open it steps up to a regular app so the menu bar (App · Edit · View · Window)
/// exists — Settings, Quit, Refresh and the standard Edit shortcuts — and steps back down on close.
@MainActor
enum MainMenu {
    private static var installed = false

    static func stepUp() {
        if !installed { install() }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Back to a menu bar utility when the last regular window closes.
    static func stepDownIfNoWindows() {
        let open = NSApp.windows.contains { $0.isVisible && $0.styleMask.contains(.titled) && $0.className != "NSStatusBarWindow" }
        if !open { NSApp.setActivationPolicy(.accessory) }
    }

    private static func install() {
        installed = true
        let main = NSMenu()

        let appName = AppInfo.displayName
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(title: appName); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About \(appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(MenuActions.openSettings(_:)), keyEquivalent: ",")
        settings.target = MenuActions.shared; appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit"); editItem.submenu = edit
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z"); redo.keyEquivalentModifierMask = [.command, .shift]; edit.addItem(redo)
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let viewItem = NSMenuItem(); main.addItem(viewItem)
        let view = NSMenu(title: "View"); viewItem.submenu = view
        let refresh = NSMenuItem(title: "Refresh", action: #selector(MenuActions.refresh(_:)), keyEquivalent: "r"); refresh.target = MenuActions.shared; view.addItem(refresh)
        let markAll = NSMenuItem(title: "Mark All Read", action: #selector(MenuActions.markAllRead(_:)), keyEquivalent: "a"); markAll.keyEquivalentModifierMask = [.command, .shift]; markAll.target = MenuActions.shared; view.addItem(markAll)
        let widget = NSMenuItem(title: "Toggle Headline Widget", action: #selector(MenuActions.toggleWidget(_:)), keyEquivalent: "w"); widget.keyEquivalentModifierMask = [.command, .shift]; widget.target = MenuActions.shared; view.addItem(widget)

        let windowItem = NSMenuItem(); main.addItem(windowItem)
        let window = NSMenu(title: "Window"); windowItem.submenu = window
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        NSApp.windowsMenu = window

        NSApp.mainMenu = main
    }
}

/// Targets for the menu items; wired by PulseFeedApp so the menu can reach the database and engine.
@MainActor
final class MenuActions: NSObject {
    static let shared = MenuActions()
    var appDB: AppDatabase?
    var feedEngine: FeedEngine?
    var updaterController: SPUStandardUpdaterController?

    @objc func openSettings(_ sender: Any?) {
        guard let appDB, let updaterController else { return }
        SettingsWindowController.shared.open(appDB: appDB, updaterController: updaterController)
    }
    @objc func refresh(_ sender: Any?) { feedEngine?.refreshAll() }
    @objc func markAllRead(_ sender: Any?) {
        guard let appDB else { return }
        Task { try? await appDB.markAllRead() }
    }
    @objc func toggleWidget(_ sender: Any?) {
        guard let appDB, let feedEngine else { return }
        HeadlineWidgetController.shared.toggle(appDB: appDB, feedEngine: feedEngine)
    }
}
