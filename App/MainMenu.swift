import AppKit

/// A minimal main menu. KKit has no menu bar of its own while it's an agent app, but
/// key equivalents (⌘, ⌘W ⌘Q, copy and paste in text fields) still go through it.
@MainActor
enum MainMenu {
    static func make(target: AppDelegate) -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu(title: "KKit")
        appMenu.addItem(withTitle: String(localized: "About KKit"),
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let settings = appMenu.addItem(withTitle: String(localized: "Settings…"),
                                       action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",")
        settings.target = target
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: String(localized: "Hide KKit"),
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: String(localized: "Quit KKit"),
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        add(appMenu, to: main)

        let editMenu = NSMenu(title: String(localized: "Edit"))
        editMenu.addItem(withTitle: String(localized: "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: String(localized: "Redo"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: String(localized: "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: String(localized: "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: String(localized: "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: String(localized: "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        add(editMenu, to: main)

        let windowMenu = NSMenu(title: String(localized: "Window"))
        windowMenu.addItem(withTitle: String(localized: "Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: String(localized: "Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        add(windowMenu, to: main)
        NSApp.windowsMenu = windowMenu

        return main
    }

    private static func add(_ menu: NSMenu, to main: NSMenu) {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        main.addItem(item)
    }
}
