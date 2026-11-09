import AppKit
import KKitCore

/// Turns `NSWorkspace` notifications into `AppEvent`s: frontmost app, sleep and wake.
@MainActor
public final class WorkspaceEventsPublisher {
    private let events: EventBus
    private var observers: [NSObjectProtocol] = []

    public init(events: EventBus) {
        self.events = events
        let center = NSWorkspace.shared.notificationCenter
        observe(center, NSWorkspace.didActivateApplicationNotification) { notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            return .frontmostAppChanged(bundleID: app?.bundleIdentifier)
        }
        observe(center, NSWorkspace.willSleepNotification) { _ in .systemWillSleep }
        observe(center, NSWorkspace.didWakeNotification) { _ in .systemDidWake }
        observe(center, NSWorkspace.screensDidSleepNotification) { _ in .screensDidSleep }
        observe(center, NSWorkspace.screensDidWakeNotification) { _ in .screensDidWake }
    }

    private func observe(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        event: @escaping @Sendable (Notification) -> AppEvent
    ) {
        observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
            let appEvent = event(notification)
            MainActor.assumeIsolated {
                self?.events.publish(appEvent)
            }
        })
    }
}
