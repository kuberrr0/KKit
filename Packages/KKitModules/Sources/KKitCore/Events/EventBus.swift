import Foundation

/// Loose "something happened" signals that several features may care about.
/// Rule of thumb: services for doing, events for telling.
///
/// New cases are added with the features that need them; `custom` is the escape hatch.
public enum AppEvent: Sendable, Hashable {
    case featureStateChanged(FeatureID)
    case displaysChanged
    case frontmostAppChanged(bundleID: String?)
    case custom(name: String, payload: [String: String])
}

/// Typed publish/subscribe for `AppEvent`s.
///
/// ```swift
/// for await event in context.events.stream(where: { $0 == .displaysChanged }) { … }
/// ```
@MainActor
public final class EventBus {
    private struct Subscriber {
        let matches: @Sendable (AppEvent) -> Bool
        let continuation: AsyncStream<AppEvent>.Continuation
    }

    private var subscribers: [UUID: Subscriber] = [:]

    public init() {}

    public var subscriberCount: Int { subscribers.count }

    public func publish(_ event: AppEvent) {
        for subscriber in subscribers.values where subscriber.matches(event) {
            subscriber.continuation.yield(event)
        }
    }

    /// Events matching `predicate` from now on, until the consuming task is cancelled.
    public func stream(
        where predicate: @escaping @Sendable (AppEvent) -> Bool = { _ in true }
    ) -> AsyncStream<AppEvent> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: AppEvent.self,
            bufferingPolicy: .bufferingNewest(64)
        )
        let id = UUID()
        subscribers[id] = Subscriber(matches: predicate, continuation: continuation)
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.subscribers[id] = nil }
        }
        return stream
    }
}
