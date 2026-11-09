import Foundation
import KKitServicesAPI

/// Demand-driven system sampling: one loop runs while at least one stream is open, at
/// the shortest interval any subscriber asked for, and stops when the last stream ends.
@MainActor
public final class MachSystemInfoService: SystemInfoService {
    private struct Subscriber {
        var interval: Duration
        var includeProcesses: Bool
        var continuation: AsyncStream<SystemSample>.Continuation
    }

    private var subscribers: [UUID: Subscriber] = [:]
    private var loop: Task<Void, Never>?
    private var loopConfiguration: (interval: Duration, processes: Bool)?
    private let sampler = SystemSampler()
    private var latest: SystemSample?
    private let pressure = Broadcast<MemoryPressure>()
    private var pressureSource: (any DispatchSourceMemoryPressure)?

    public init() {
        pressure.onFirstSubscriber = { [weak self] in self?.startPressureSource() }
        pressure.onLastSubscriberGone = { [weak self] in self?.stopPressureSource() }
    }

    public func memoryPressureUpdates() -> AsyncStream<MemoryPressure> {
        pressure.stream(initial: SystemSampler.memoryPressure())
    }

    private func startPressureSource() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.pressure.send(SystemSampler.memoryPressure())
            }
        }
        source.resume()
        pressureSource = source
    }

    private func stopPressureSource() {
        pressureSource?.cancel()
        pressureSource = nil
    }

    public func samples(every interval: Duration, includeProcesses: Bool) -> AsyncStream<SystemSample> {
        let (stream, continuation) = AsyncStream.makeStream(of: SystemSample.self, bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        subscribers[id] = Subscriber(interval: max(interval, .milliseconds(500)), includeProcesses: includeProcesses, continuation: continuation)
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.remove(id) }
        }
        if let latest {
            continuation.yield(latest)
        }
        updateLoop()
        return stream
    }

    private func remove(_ id: UUID) {
        guard subscribers.removeValue(forKey: id) != nil else { return }
        updateLoop()
    }

    private func updateLoop() {
        guard let interval = subscribers.values.map(\.interval).min() else {
            loop?.cancel()
            loop = nil
            loopConfiguration = nil
            latest = nil
            return
        }
        let processes = subscribers.values.contains { $0.includeProcesses }
        if let current = loopConfiguration, current.interval == interval, current.processes == processes {
            return
        }
        loopConfiguration = (interval, processes)
        loop?.cancel()
        let sampler = self.sampler
        let isFirstStart = latest == nil
        loop = Task { [weak self] in
            if isFirstStart {
                // Rates need two readings; take the first one now.
                _ = await sampler.sample(includeProcesses: processes)
                try? await Task.sleep(for: .milliseconds(400))
            }
            while !Task.isCancelled {
                let sample = await sampler.sample(includeProcesses: processes)
                guard !Task.isCancelled, let self else { return }
                self.deliver(sample)
                try? await Task.sleep(for: interval)
            }
        }
    }

    private func deliver(_ sample: SystemSample) {
        latest = sample
        for subscriber in subscribers.values {
            subscriber.continuation.yield(sample)
        }
    }
}
