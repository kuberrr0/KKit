import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics
import CoreLocation
import IOKit.hid
import KKitCore
import KKitServicesAPI
import Observation
import UserNotifications

/// Reads and requests macOS privacy permissions with public APIs.
///
/// Statuses are re-read when Accessibility trust changes (macOS posts
/// `com.apple.accessibility.api`), when KKit becomes active, and whenever
/// `refresh()` is called (the feature manager does that every few seconds while a
/// feature is waiting for a permission).
@MainActor
@Observable
public final class SystemPermissionsService: PermissionsService {
    public private(set) var statuses: [Permission: PermissionStatus] = [:]
    @ObservationIgnored public var onChange: (@MainActor () -> Void)?

    @ObservationIgnored private var notificationStatus: PermissionStatus = .notDetermined
    @ObservationIgnored private var locationManager: CLLocationManager?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    public init() {
        refresh()
        startObserving()
    }

    public func status(of permission: Permission) -> PermissionStatus {
        statuses[permission] ?? .unknown
    }

    public func refresh() {
        var updated: [Permission: PermissionStatus] = [:]
        for permission in Permission.allCases {
            updated[permission] = currentStatus(of: permission)
        }
        if updated != statuses {
            statuses = updated
            onChange?()
        }
        refreshNotificationStatus()
    }

    @discardableResult
    public func request(_ permission: Permission) async -> PermissionStatus {
        switch permission {
        case .accessibility:
            // The string value of kAXTrustedCheckOptionPrompt (a C global that Swift 6
            // won't let us read directly).
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            if !AXIsProcessTrustedWithOptions(options) {
                openSystemSettings(for: permission)
            }
        case .inputMonitoring:
            if !IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) {
                openSystemSettings(for: permission)
            }
        case .screenRecording:
            if !CGRequestScreenCaptureAccess() {
                openSystemSettings(for: permission)
            }
        case .microphone:
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .audio)
            } else {
                openSystemSettings(for: permission)
            }
        case .notifications:
            if notificationStatus == .notDetermined {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
                        continuation.resume()
                    }
                }
            } else {
                openSystemSettings(for: permission)
            }
        case .automation, .location:
            // Automation is asked per target app the first time KKit scripts it;
            // location is asked by the feature that needs it.
            openSystemSettings(for: permission)
        }
        refresh()
        return status(of: permission)
    }

    public func openSystemSettings(for permission: Permission) {
        let anchor: String
        switch permission {
        case .accessibility: anchor = "com.apple.preference.security?Privacy_Accessibility"
        case .inputMonitoring: anchor = "com.apple.preference.security?Privacy_ListenEvent"
        case .screenRecording: anchor = "com.apple.preference.security?Privacy_ScreenCapture"
        case .microphone: anchor = "com.apple.preference.security?Privacy_Microphone"
        case .automation: anchor = "com.apple.preference.security?Privacy_Automation"
        case .location: anchor = "com.apple.preference.security?Privacy_LocationServices"
        case .notifications: anchor = "com.apple.preference.notifications"
        }
        if let url = URL(string: "x-apple.systempreferences:\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Private

    private func currentStatus(of permission: Permission) -> PermissionStatus {
        switch permission {
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .denied
        case .inputMonitoring:
            let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
            if access.rawValue == kIOHIDAccessTypeGranted.rawValue { return .granted }
            if access.rawValue == kIOHIDAccessTypeDenied.rawValue { return .denied }
            return .notDetermined
        case .screenRecording:
            return CGPreflightScreenCaptureAccess() ? .granted : .denied
        case .microphone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: return .granted
            case .denied, .restricted: return .denied
            case .notDetermined: return .notDetermined
            @unknown default: return .unknown
            }
        case .automation:
            return .unknown
        case .notifications:
            return notificationStatus
        case .location:
            let manager = locationManager ?? CLLocationManager()
            locationManager = manager
            switch manager.authorizationStatus {
            case .notDetermined: return .notDetermined
            case .denied, .restricted: return .denied
            default: return .granted
            }
        }
    }

    private func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status: PermissionStatus
            switch settings.authorizationStatus {
            case .authorized, .provisional: status = .granted
            case .denied: status = .denied
            case .notDetermined: status = .notDetermined
            default: status = .unknown
            }
            Task { @MainActor in
                self.updateNotificationStatus(status)
            }
        }
    }

    private func updateNotificationStatus(_ status: PermissionStatus) {
        guard status != notificationStatus else { return }
        notificationStatus = status
        refresh()
    }

    private func startObserving() {
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleRefresh()
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        })
    }

    /// The accessibility notification arrives slightly before `AXIsProcessTrusted`
    /// reports the new value.
    private func scheduleRefresh() {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            self?.refresh()
        }
    }
}
