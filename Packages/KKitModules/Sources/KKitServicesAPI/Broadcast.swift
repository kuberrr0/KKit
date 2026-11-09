import Foundation

/// Fans values out to any number of `AsyncStream` subscribers, and tells the owner
/// when the first subscriber arrives and the last one leaves. Services use it to do
/// work only while someone is listening ("nothing samples unless something is
/// looking", ARCHITECTURE.md §9).
@MainActor
public final class Broadcast<Value: Sendable> {
    private var continuations: [UUID: AsyncStream<Value>.Continuation] = [:]

    /// Called when the subscriber count goes from 0 to 1.
    public var onFirstSubscriber: (@MainActor () -> Void)?
    /// Called when the subscriber count goes back to 0.
    public var onLastSubscriberGone: (@MainActor () -> Void)?

    public init() {}

    public var subscriberCount: Int { continuations.count }
    public var hasSubscribers: Bool { !continuations.isEmpty }

    /// A new stream that starts with `initial` (if given), then every `send`.
    public func stream(initial: Value? = nil) -> AsyncStream<Value> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: Value.self,
            bufferingPolicy: .bufferingNewest(16)
        )
        let id = UUID()
        let wasEmpty = continuations.isEmpty
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.remove(id) }
        }
        if let initial {
            continuation.yield(initial)
        }
        if wasEmpty {
            onFirstSubscriber?()
        }
        return stream
    }

    public func send(_ value: Value) {
        for continuation in continuations.values {
            continuation.yield(value)
        }
    }

    private func remove(_ id: UUID) {
        guard continuations.removeValue(forKey: id) != nil else { return }
        if continuations.isEmpty {
            onLastSubscriberGone?()
        }
    }
}
