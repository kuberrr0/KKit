import AppKit

/// Running apps and the app-level actions the switcher offers (⌘Tab's Q and H).
/// Activation goes through `WindowService.activateApp`, which works from the background.
@MainActor
protocol SwitcherAppControlling: AnyObject {
    var frontmostPID: Int32? { get }
    /// Regular apps (with a Dock icon), not KKit.
    func runningApps() -> [SwitcherApp]
    func icon(for pid: Int32) -> NSImage?
    func hide(_ pid: Int32)
    func quit(_ pid: Int32)
    /// Calls `handler` with each app that comes to the front, until `stopObserving`.
    func observeActivations(_ handler: @escaping @MainActor @Sendable (Int32) -> Void)
    func stopObserving()
}

/// `NSWorkspace` and `NSRunningApplication`.
@MainActor
final class WorkspaceApps: SwitcherAppControlling {
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private var observer: (any NSObjectProtocol)?

    var frontmostPID: Int32? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    func runningApps() -> [SwitcherApp] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != ownPID && !$0.isTerminated }
            .map { app in
                SwitcherApp(
                    pid: app.processIdentifier,
                    name: app.localizedName ?? app.bundleIdentifier ?? "",
                    bundleID: app.bundleIdentifier,
                    isHidden: app.isHidden
                )
            }
    }

    func icon(for pid: Int32) -> NSImage? {
        NSRunningApplication(processIdentifier: pid)?.icon
    }

    func hide(_ pid: Int32) {
        NSRunningApplication(processIdentifier: pid)?.hide()
    }

    func quit(_ pid: Int32) {
        NSRunningApplication(processIdentifier: pid)?.terminate()
    }

    func observeActivations(_ handler: @escaping @MainActor @Sendable (Int32) -> Void) {
        stopObserving()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let pid = app?.processIdentifier else { return }
            MainActor.assumeIsolated {
                handler(pid)
            }
        }
    }

    func stopObserving() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
    }
}
