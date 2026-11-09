import AppKit
import ApplicationServices
import CoreGraphics
import KKitCore
import KKitServicesAPI
import Observation

/// The one `CGEventTap` in KKit (ARCHITECTURE.md §7).
///
/// The tap sits at the HID level so rewritten events (the Hyper key's ⌃⌥⇧⌘) reach other
/// apps' shortcuts too. It runs on the main run loop and calls handlers in priority
/// order; the first `.consume` wins. The mask is the union of what handlers ask for and
/// what they've armed, so with no handlers there's no tap at all, and mouse motion is
/// only tapped while something arms it. macOS can't change a tap's mask, so the tap is
/// recreated when the mask changes (on arm/disarm, a few milliseconds).
@MainActor
@Observable
public final class CGEventTapInputService: InputTapService {
    private struct Handler {
        let token: InputHandlerToken
        let owner: FeatureID
        let priority: InputPriority
        let interests: Set<InputEventType>
        var armed: Set<InputEventType>
        let handle: @MainActor (InputEvent) -> InputDecision

        func wants(_ type: InputEventType) -> Bool {
            armed.contains(type) || (interests.contains(type) && !type.isHighFrequency)
        }
    }

    public private(set) var status: InputTapStatus = .idle

    /// Whether a feature is still starting or running; the app sets it. Handlers of
    /// features that stopped are removed.
    @ObservationIgnored public var isOwnerActive: (@MainActor (FeatureID) -> Bool)?

    @ObservationIgnored private var handlers: [Handler] = []
    @ObservationIgnored private var nextID: UInt64 = 1
    @ObservationIgnored private var tap: CFMachPort?
    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var installedMask: CGEventMask = 0
    @ObservationIgnored private var isDispatching = false
    @ObservationIgnored private var rebuildPending = false
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    private let eventSource = CGEventSource(stateID: .hidSystemState)
    @ObservationIgnored private var lastSlowLog = Date.distantPast
    private let remapper = HIDKeyRemapper()
    private let log = KKitLog.logger("input")

    /// Marks events KKit posts, so its handlers let them through untouched ("KKIT").
    static let ownEventMarker: Int64 = 0x4B4B_4954

    public init(events: EventBus) {
        let stream = events.stream { event in
            if case .featureStateChanged = event { return true }
            return false
        }
        eventTask = Task { [weak self] in
            for await event in stream {
                guard let self, case .featureStateChanged(let id) = event else { continue }
                if self.isOwnerActive?(id) == false {
                    self.removeHandlers(owner: id)
                }
            }
        }
    }

    // MARK: InputTapService

    @discardableResult
    public func addHandler(
        owner: FeatureID,
        priority: InputPriority,
        interests: Set<InputEventType>,
        handler: @escaping @MainActor (InputEvent) -> InputDecision
    ) -> InputHandlerToken {
        let token = InputHandlerToken(id: nextID)
        nextID &+= 1
        handlers.append(Handler(token: token, owner: owner, priority: priority, interests: interests, armed: [], handle: handler))
        // Stable: higher priority first, then the order handlers were added.
        handlers = handlers.enumerated().sorted { lhs, rhs in
            if lhs.element.priority != rhs.element.priority {
                return lhs.element.priority > rhs.element.priority
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
        scheduleRebuild()
        return token
    }

    public func removeHandler(_ token: InputHandlerToken) {
        let before = handlers.count
        handlers.removeAll { $0.token == token }
        if handlers.count != before {
            scheduleRebuild()
        }
    }

    public func removeHandlers(owner: FeatureID) {
        let before = handlers.count
        handlers.removeAll { $0.owner == owner }
        if handlers.count != before {
            scheduleRebuild()
        }
    }

    public func arm(_ types: Set<InputEventType>, for token: InputHandlerToken) {
        guard let index = handlers.firstIndex(where: { $0.token == token }) else { return }
        guard handlers[index].armed != types else { return }
        handlers[index].armed = types
        scheduleRebuild()
    }

    public func disarm(_ token: InputHandlerToken) {
        arm([], for: token)
    }

    public func postKey(_ keyCode: Int, down: Bool, modifiers: Shortcut.Modifiers) {
        guard let event = CGEvent(keyboardEventSource: eventSource, virtualKey: CGKeyCode(keyCode), keyDown: down) else {
            return
        }
        event.flags = InputEvent.flags(from: modifiers)
        event.setIntegerValueField(.eventSourceUserData, value: Self.ownEventMarker)
        event.post(tap: .cghidEventTap)
    }

    public func setCapsLockRemap(_ remap: CapsLockRemap?) async {
        do {
            try await remapper.setCapsLock(to: remap?.hidUsage)
        } catch {
            log.error("Caps Lock remap failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func retry() {
        installedMask = 0
        rebuildTap(force: true)
    }

    // MARK: The tap

    private func neededMask() -> CGEventMask {
        var mask: CGEventMask = 0
        for handler in handlers {
            for type in InputEventType.allCases where handler.wants(type) {
                mask |= CGEventMask(1) << CGEventMask(type.cgType.rawValue)
            }
        }
        return mask
    }

    /// Rebuilding inside the tap's own callback would tear the tap down under itself, so
    /// changes made by handlers are applied right after the event.
    private func scheduleRebuild() {
        if isDispatching {
            guard !rebuildPending else { return }
            rebuildPending = true
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.rebuildPending = false
                    self.rebuildTap(force: false)
                }
            }
        } else {
            rebuildTap(force: false)
        }
    }

    private func rebuildTap(force: Bool) {
        let mask = neededMask()
        if !force, mask == installedMask, (tap != nil) == (mask != 0) {
            return
        }
        destroyTap()
        guard mask != 0 else {
            status = .idle
            return
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let newTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: kkitInputTapCallback,
            userInfo: context
        ) else {
            installedMask = 0
            status = AXIsProcessTrusted()
                ? .failed(String(localized: "macOS refused KKit's keyboard and mouse tap."))
                : .needsPermission
            log.error("CGEvent.tapCreate failed (trusted: \(AXIsProcessTrusted()))")
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        tap = newTap
        runLoopSource = source
        installedMask = mask
        status = .running
    }

    private func destroyTap() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        installedMask = 0
    }

    /// Called by the tap callback on the main thread. Returns `true` to swallow the event.
    fileprivate func dispatch(type cgType: CGEventType, event: CGEvent) -> Bool {
        if cgType == .tapDisabledByTimeout || cgType == .tapDisabledByUserInput {
            // macOS turns a slow tap off; turn it back on (a stuck Clean Mode lock fails
            // open in between, which is the safe direction).
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            log.error("The input tap was disabled by macOS (\(cgType == .tapDisabledByTimeout ? "timeout" : "user input", privacy: .public)); re-enabled")
            return false
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.ownEventMarker {
            return false
        }
        guard let type = InputEventType(cgType: cgType) else { return false }

        var mediaKey: MediaKeyEvent?
        if type == .systemDefined {
            guard let nsEvent = NSEvent(cgEvent: event) else { return false }
            mediaKey = MediaKeyEvent(subtype: Int(nsEvent.subtype.rawValue), data1: nsEvent.data1)
            // Other system-defined events (power button, eject…) aren't for handlers.
            guard mediaKey != nil else { return false }
        }
        let input = InputEvent(type: type, cgEvent: event, mediaKey: mediaKey)

        isDispatching = true
        defer { isDispatching = false }
        for handler in handlers where handler.wants(type) {
            let started = DispatchTime.now().uptimeNanoseconds
            let decision = handler.handle(input)
            let elapsed = DispatchTime.now().uptimeNanoseconds &- started
            if elapsed > 2_000_000, Date().timeIntervalSince(lastSlowLog) > 5 {
                lastSlowLog = Date()
                log.error("Slow input handler from \(handler.owner.rawValue, privacy: .public): \(elapsed / 1_000) µs")
            }
            if decision == .consume {
                return true
            }
        }
        return false
    }
}

/// Carries a `CGEvent` into the main actor; the tap callback runs on the main thread.
private struct UncheckedEvent: @unchecked Sendable {
    let event: CGEvent
}

/// The C callback. The tap's run loop source is on the main run loop, so this runs on
/// the main thread.
private func kkitInputTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let service = Unmanaged<CGEventTapInputService>.fromOpaque(userInfo).takeUnretainedValue()
    let boxed = UncheckedEvent(event: event)
    let consume = MainActor.assumeIsolated {
        service.dispatch(type: type, event: boxed.event)
    }
    return consume ? nil : Unmanaged.passUnretained(event)
}
