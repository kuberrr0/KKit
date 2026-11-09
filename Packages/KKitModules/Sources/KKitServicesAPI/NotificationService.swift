import Foundation

/// System notifications, for when the Island isn't enough (a timer that ends while
/// you're in another Space). Does nothing until the Notifications permission is granted.
@MainActor
public protocol NotificationService: AnyObject {
    func deliver(id: String, title: String, body: String?)
}
