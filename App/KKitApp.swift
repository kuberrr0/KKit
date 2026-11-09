import AppKit

/// Entry point. KKit is an AppKit agent app (`LSUIElement`): no Dock icon or main
/// window by default, just the menu bar item, the hosts' panels and Settings.
@main
@MainActor
enum KKitApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
