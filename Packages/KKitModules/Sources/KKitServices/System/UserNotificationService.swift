import Foundation
import KKitServicesAPI
import UserNotifications

/// Delivers system notifications. macOS drops them silently while the Notifications
/// permission isn't granted.
@MainActor
public final class UserNotificationService: NotificationService {
    public init() {}

    public func deliver(id: String, title: String, body: String?) {
        let content = UNMutableNotificationContent()
        content.title = title
        if let body {
            content.body = body
        }
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}
