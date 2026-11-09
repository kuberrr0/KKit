import CoreGraphics
import Foundation
import KKitCore
import KKitServicesAPI
import SwiftUI

/// An input tap you drive by hand: `sendKey`, `sendMedia`, `sendMouse` run the
/// handlers like the real tap and return whether one consumed the event.
@MainActor
public final class FakeInputTapService: InputTapService {
    public struct Handler {
        public let token: InputHandlerToken
        public let owner: FeatureID
        public let priority: InputPriority
        public let interests: Set<InputEventType>
        public var armed: Set<InputEventType>
        let handle: @MainActor (InputEvent) -> InputDecision

        func wants(_ type: InputEventType) -> Bool {
            armed.contains(type) || (interests.contains(type) && !type.isHighFrequency)
        }
    }

    public struct PostedKey: Equatable, Sendable {
        public var keyCode: Int
        public var down: Bool
        public var modifiers: Shortcut.Modifiers
    }

    public var status: InputTapStatus = .running
    public private(set) var handlers: [Handler] = []
    public private(set) var posted: [PostedKey] = []
    public private(set) var capsLockRemap: CapsLockRemap?
    public private(set) var retryCount = 0
    private var nextID: UInt64 = 1

    public init() {}

    @discardableResult
    public func addHandler(
        owner: FeatureID,
        priority: InputPriority,
        interests: Set<InputEventType>,
        handler: @escaping @MainActor (InputEvent) -> InputDecision
    ) -> InputHandlerToken {
        let token = InputHandlerToken(id: nextID)
        nextID += 1
        handlers.append(Handler(token: token, owner: owner, priority: priority, interests: interests, armed: [], handle: handler))
        handlers = handlers.enumerated().sorted { lhs, rhs in
            lhs.element.priority != rhs.element.priority
                ? lhs.element.priority > rhs.element.priority
                : lhs.offset < rhs.offset
        }.map(\.element)
        return token
    }

    public func removeHandler(_ token: InputHandlerToken) {
        handlers.removeAll { $0.token == token }
    }

    public func removeHandlers(owner: FeatureID) {
        handlers.removeAll { $0.owner == owner }
    }

    public func arm(_ types: Set<InputEventType>, for token: InputHandlerToken) {
        guard let index = handlers.firstIndex(where: { $0.token == token }) else { return }
        handlers[index].armed = types
    }

    public func disarm(_ token: InputHandlerToken) {
        arm([], for: token)
    }

    public func postKey(_ keyCode: Int, down: Bool, modifiers: Shortcut.Modifiers) {
        posted.append(PostedKey(keyCode: keyCode, down: down, modifiers: modifiers))
    }

    public func setCapsLockRemap(_ remap: CapsLockRemap?) async {
        capsLockRemap = remap
    }

    public func retry() {
        retryCount += 1
    }

    /// Event types some handler gets right now (interests plus armed).
    public var tappedTypes: Set<InputEventType> {
        Set(InputEventType.allCases.filter { type in handlers.contains { $0.wants(type) } })
    }

    public func handlers(owner: FeatureID) -> [Handler] {
        handlers.filter { $0.owner == owner }
    }

    // MARK: Sending events

    @discardableResult
    public func send(_ event: InputEvent) -> Bool {
        for handler in handlers where handler.wants(event.type) {
            if handler.handle(event) == .consume {
                return true
            }
        }
        return false
    }

    /// A key press or release. Returns whether it was consumed; `lastEvent` is the
    /// event as handlers left it (rewritten flags).
    @discardableResult
    public func sendKey(_ keyCode: Int, down: Bool, modifiers: Shortcut.Modifiers = [], isRepeat: Bool = false) -> Bool {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: down) else {
            return false
        }
        event.flags = InputEvent.flags(from: modifiers)
        if isRepeat {
            event.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        }
        lastEvent = event
        return send(InputEvent(type: down ? .keyDown : .keyUp, cgEvent: event))
    }

    /// A press and release; returns whether the press was consumed.
    @discardableResult
    public func tapKey(_ keyCode: Int, modifiers: Shortcut.Modifiers = []) -> Bool {
        let consumed = sendKey(keyCode, down: true, modifiers: modifiers)
        sendKey(keyCode, down: false, modifiers: modifiers)
        return consumed
    }

    /// A modifier key going down or up: `modifiers` is what's held afterwards.
    @discardableResult
    public func sendFlags(_ modifiers: Shortcut.Modifiers, keyCode: Int = Shortcut.Key.leftOption, function: Bool = false) -> Bool {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: true) else {
            return false
        }
        event.type = .flagsChanged
        var flags = InputEvent.flags(from: modifiers)
        if function {
            flags.insert(.maskSecondaryFn)
        }
        event.flags = flags
        lastEvent = event
        return send(InputEvent(type: .flagsChanged, cgEvent: event))
    }

    @discardableResult
    public func sendMedia(_ key: MediaKey, down: Bool = true, modifiers: Shortcut.Modifiers = [], isRepeat: Bool = false) -> Bool {
        guard let event = CGEvent(source: nil) else { return false }
        event.flags = InputEvent.flags(from: modifiers)
        lastEvent = event
        return send(InputEvent(
            type: .systemDefined,
            cgEvent: event,
            mediaKey: MediaKeyEvent(key: key, isDown: down, isRepeat: isRepeat)
        ))
    }

    /// A mouse event at `point` (Core Graphics coordinates, top-left origin).
    @discardableResult
    public func sendMouse(_ type: InputEventType, at point: CGPoint, modifiers: Shortcut.Modifiers = [], clickCount: Int = 1) -> Bool {
        let button: CGMouseButton
        switch type {
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged: button = .right
        case .otherMouseDown, .otherMouseUp, .otherMouseDragged: button = .center
        default: button = .left
        }
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type.cgType, mouseCursorPosition: point, mouseButton: button) else {
            return false
        }
        event.flags = InputEvent.flags(from: modifiers)
        event.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
        lastEvent = event
        return send(InputEvent(type: type, cgEvent: event))
    }

    /// The last event sent, after handlers ran.
    public private(set) var lastEvent: CGEvent?
}

/// Windows kept in a list; `setFrame` moves them.
@MainActor
public final class FakeWindowService: WindowService {
    public var windows: [WindowInfo] = []
    public var focusedKey: UInt64?
    public var isTrusted = true
    public var isSystemEdgeTilingEnabled = false
    public private(set) var raised: [WindowRef] = []
    public private(set) var frameChanges: [(WindowRef, CGRect)] = []

    public init() {}

    @discardableResult
    public func addWindow(
        key: UInt64,
        frame: CGRect,
        title: String = "Window",
        appName: String = "App",
        bundleID: String? = "com.example.app",
        pid: Int32 = 100
    ) -> WindowInfo {
        let info = WindowInfo(ref: WindowRef(pid: pid, key: key), title: title, appName: appName, bundleID: bundleID, frame: frame)
        windows.append(info)
        return info
    }

    public func focusedWindow() async -> WindowInfo? {
        guard isTrusted else { return nil }
        if let focusedKey {
            return windows.first { $0.ref.key == focusedKey }
        }
        return windows.first
    }

    public func window(at point: CGPoint) async -> WindowInfo? {
        windows.first { $0.frame.contains(point) }
    }

    public func visibleWindows() async -> [WindowInfo] {
        windows
    }

    public func info(for window: WindowRef) async -> WindowInfo? {
        windows.first { $0.ref == window }
    }

    public func setFrame(_ frame: CGRect, of window: WindowRef) async {
        guard let index = windows.firstIndex(where: { $0.ref == window }) else { return }
        windows[index].frame = frame
        frameChanges.append((window, frame))
    }

    public func setOrigin(_ origin: CGPoint, of window: WindowRef) async {
        guard let index = windows.firstIndex(where: { $0.ref == window }) else { return }
        let frame = CGRect(origin: origin, size: windows[index].frame.size)
        windows[index].frame = frame
        frameChanges.append((window, frame))
    }

    public func raise(_ window: WindowRef) async {
        raised.append(window)
    }

    public func frame(of key: UInt64) -> CGRect? {
        windows.first { $0.ref.key == key }?.frame
    }
}

/// A frontmost app and menu items you set by hand.
@MainActor
public final class FakeAccessibilityService: AccessibilityService {
    public var isTrusted = true
    public var app: FrontmostApp? = FrontmostApp(pid: 42, bundleID: "com.example.editor", name: "Editor")
    public var items: [MenuItemInfo] = []
    public var selection: String?
    public private(set) var pressed: [MenuItemInfo] = []

    public init() {}

    public func frontmostApp() -> FrontmostApp? { app }

    public func menuItems(of pid: Int32) async -> [MenuItemInfo] {
        items.filter { $0.pid == pid }
    }

    public func press(_ item: MenuItemInfo) async throws {
        guard isTrusted else { throw AccessibilityError.needsAccessibility }
        pressed.append(item)
    }

    public func selectedText() async -> String? { selection }
}

/// Records commands run by id.
@MainActor
public final class FakeCommandRunner: CommandRunnerService {
    public var commandList: [CommandSummary] = []
    public private(set) var runs: [(CommandID, String?)] = []

    public init() {}

    public func run(_ id: CommandID, value: String?) async throws {
        runs.append((id, value))
    }
}
