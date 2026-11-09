import CoreGraphics
import KKitCore

/// The kinds of low-level input a handler can ask for. ARCHITECTURE.md §7.
public enum InputEventType: Int, Sendable, Hashable, CaseIterable {
    case keyDown
    case keyUp
    case flagsChanged
    /// Media and brightness keys (`NX_SYSDEFINED`).
    case systemDefined
    case leftMouseDown
    case leftMouseUp
    case leftMouseDragged
    case rightMouseDown
    case rightMouseUp
    case rightMouseDragged
    case otherMouseDown
    case otherMouseUp
    case otherMouseDragged
    case mouseMoved
    case scrollWheel

    /// These arrive many times a second, so they're only tapped while a handler arms
    /// them (`FeatureInput.arm`).
    public var isHighFrequency: Bool {
        switch self {
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .mouseMoved, .scrollWheel: true
        default: false
        }
    }

    /// The Core Graphics event type.
    public var cgType: CGEventType {
        switch self {
        case .keyDown: .keyDown
        case .keyUp: .keyUp
        case .flagsChanged: .flagsChanged
        case .systemDefined: CGEventType(rawValue: 14) ?? .null
        case .leftMouseDown: .leftMouseDown
        case .leftMouseUp: .leftMouseUp
        case .leftMouseDragged: .leftMouseDragged
        case .rightMouseDown: .rightMouseDown
        case .rightMouseUp: .rightMouseUp
        case .rightMouseDragged: .rightMouseDragged
        case .otherMouseDown: .otherMouseDown
        case .otherMouseUp: .otherMouseUp
        case .otherMouseDragged: .otherMouseDragged
        case .mouseMoved: .mouseMoved
        case .scrollWheel: .scrollWheel
        }
    }

    public init?(cgType: CGEventType) {
        guard let match = Self.allCases.first(where: { $0.cgType.rawValue == cgType.rawValue }) else { return nil }
        self = match
    }

    public static let keyboard: Set<InputEventType> = [.keyDown, .keyUp, .flagsChanged, .systemDefined]
    public static let mouseButtons: Set<InputEventType> = [
        .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
    ]
    public static let mouseMotion: Set<InputEventType> = [
        .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .mouseMoved, .scrollWheel,
    ]
}

/// Who sees an event first. The first handler that consumes it wins.
public enum InputPriority: Int, Sendable, Comparable {
    case low = 0
    case normal = 1
    case high = 2
    /// Clean Mode: ahead of everything.
    case safety = 3

    public static func < (lhs: InputPriority, rhs: InputPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// What a handler does with an event.
public enum InputDecision: Sendable, Hashable {
    /// Let it through (possibly changed in place, like the Hyper key's flags).
    case pass
    /// Swallow it: no app sees it.
    case consume
}

/// The media and brightness keys, as `NX_SYSDEFINED` events carry them.
public enum MediaKey: Int, Sendable, Hashable {
    case volumeUp = 0
    case volumeDown = 1
    case brightnessUp = 2
    case brightnessDown = 3
    case mute = 7
    case play = 16
    case next = 17
    case previous = 18
    case fast = 19
    case rewind = 20
    case keyboardBacklightUp = 21
    case keyboardBacklightDown = 22
}

/// A media key press or release.
public struct MediaKeyEvent: Sendable, Hashable {
    public var key: MediaKey
    public var isDown: Bool
    public var isRepeat: Bool

    public init(key: MediaKey, isDown: Bool, isRepeat: Bool) {
        self.key = key
        self.isDown = isDown
        self.isRepeat = isRepeat
    }

    /// Decodes `NSEvent.data1` of a system-defined event with subtype 8 (aux control
    /// buttons): key code in bits 16–23, state in bits 8–15 (0xA down, 0xB up), repeat in bit 0.
    public init?(subtype: Int, data1: Int) {
        guard subtype == 8 else { return nil }
        let code = (data1 & 0xFFFF_0000) >> 16
        let flags = data1 & 0x0000_FFFF
        let state = (flags & 0xFF00) >> 8
        guard let key = MediaKey(rawValue: code), state == 0xA || state == 0xB else { return nil }
        self.init(key: key, isDown: state == 0xA, isRepeat: flags & 0x1 == 1)
    }
}

/// One event, as handlers see it. Read what you need; to rewrite a key event (the
/// Hyper key), change `cgEvent` in place and return `.pass`.
@MainActor
public struct InputEvent {
    public let type: InputEventType
    public let cgEvent: CGEvent
    /// Media keys only.
    public let mediaKey: MediaKeyEvent?

    public init(type: InputEventType, cgEvent: CGEvent, mediaKey: MediaKeyEvent? = nil) {
        self.type = type
        self.cgEvent = cgEvent
        self.mediaKey = mediaKey
    }

    /// Virtual key code (`kVK_*`) for key and flags-changed events.
    public var keyCode: Int {
        Int(cgEvent.getIntegerValueField(.keyboardEventKeycode))
    }

    public var isAutoRepeat: Bool {
        cgEvent.getIntegerValueField(.keyboardEventAutorepeat) != 0
    }

    public var flags: CGEventFlags { cgEvent.flags }

    /// ⌘⌥⌃⇧ held during the event.
    public var modifiers: Shortcut.Modifiers {
        Self.modifiers(from: cgEvent.flags)
    }

    /// Whether fn was held.
    public var isFunctionDown: Bool { cgEvent.flags.contains(.maskSecondaryFn) }

    /// The cursor in Core Graphics global coordinates (top-left origin of the main display).
    public var location: CGPoint { cgEvent.location }

    /// Mouse clicks: 1, 2 (double-click)…
    public var clickCount: Int {
        Int(cgEvent.getIntegerValueField(.mouseEventClickState))
    }

    public static func modifiers(from flags: CGEventFlags) -> Shortcut.Modifiers {
        var result: Shortcut.Modifiers = []
        if flags.contains(.maskCommand) { result.insert(.command) }
        if flags.contains(.maskAlternate) { result.insert(.option) }
        if flags.contains(.maskControl) { result.insert(.control) }
        if flags.contains(.maskShift) { result.insert(.shift) }
        return result
    }

    public static func flags(from modifiers: Shortcut.Modifiers) -> CGEventFlags {
        var result: CGEventFlags = []
        if modifiers.contains(.command) { result.insert(.maskCommand) }
        if modifiers.contains(.option) { result.insert(.maskAlternate) }
        if modifiers.contains(.control) { result.insert(.maskControl) }
        if modifiers.contains(.shift) { result.insert(.maskShift) }
        return result
    }
}

/// Where the shared tap is.
public enum InputTapStatus: Sendable, Hashable {
    /// No handler wants anything, so there's no tap.
    case idle
    case running
    /// macOS refused the tap: Accessibility isn't granted.
    case needsPermission
    case failed(String)
}

/// Identifies an added handler.
public struct InputHandlerToken: Hashable, Sendable {
    public let id: UInt64

    public init(id: UInt64) {
        self.id = id
    }
}

/// What a remapped Caps Lock sends (the Hyper key). `hidutil` maps Caps Lock to this key
/// for the whole login session; the tap then turns it into ⌃⌥⇧⌘.
public enum CapsLockRemap: Sendable, Hashable {
    /// F18 (`kVK_F18`).
    case f18

    public var keyCode: Int {
        switch self {
        case .f18: Shortcut.Key.f18
        }
    }

    /// The HID usage `hidutil` maps to (keyboard page 0x07).
    public var hidUsage: UInt64 {
        switch self {
        case .f18: 0x7_0000_006D
        }
    }

    /// Caps Lock's HID usage.
    public static let capsLockUsage: UInt64 = 0x7_0000_0039
}

/// The one `CGEventTap` in KKit, for keyboard and mouse. ARCHITECTURE.md §7.
///
/// Handlers run on the main thread inside the tap callback, so they must decide in
/// well under a millisecond and hand real work to a `Task`. The tap's event mask is
/// the union of what handlers ask for; high-frequency events (drags, mouse moves,
/// scrolls) are added only while a handler arms them. Events KKit posts itself
/// (`postKey`) skip the handlers. Features use `context.input`, which fills in the
/// owner and removes the feature's handlers when it stops.
@MainActor
public protocol InputTapService: AnyObject, Sendable {
    var status: InputTapStatus { get }

    @discardableResult
    func addHandler(
        owner: FeatureID,
        priority: InputPriority,
        interests: Set<InputEventType>,
        handler: @escaping @MainActor (InputEvent) -> InputDecision
    ) -> InputHandlerToken
    func removeHandler(_ token: InputHandlerToken)
    func removeHandlers(owner: FeatureID)

    /// Adds high-frequency event types for one handler until `disarm`.
    func arm(_ types: Set<InputEventType>, for token: InputHandlerToken)
    func disarm(_ token: InputHandlerToken)

    /// Posts a key press or release that KKit's own handlers don't see again.
    func postKey(_ keyCode: Int, down: Bool, modifiers: Shortcut.Modifiers)

    /// Maps Caps Lock to another key with `hidutil` (`nil` restores Caps Lock). Other
    /// apps' mappings are kept.
    func setCapsLockRemap(_ remap: CapsLockRemap?) async

    /// Try again to create the tap (a permission was granted).
    func retry()
}

/// A feature's handle on the input tap (`context.input`).
@MainActor
public struct FeatureInput: Sendable {
    public let owner: FeatureID
    public let service: any InputTapService

    public init(owner: FeatureID, service: any InputTapService) {
        self.owner = owner
        self.service = service
    }

    public var status: InputTapStatus { service.status }

    @discardableResult
    public func add(
        priority: InputPriority = .normal,
        interests: Set<InputEventType>,
        handler: @escaping @MainActor (InputEvent) -> InputDecision
    ) -> InputHandlerToken {
        service.addHandler(owner: owner, priority: priority, interests: interests, handler: handler)
    }

    public func remove(_ token: InputHandlerToken) {
        service.removeHandler(token)
    }

    public func removeAll() {
        service.removeHandlers(owner: owner)
    }

    public func arm(_ types: Set<InputEventType>, for token: InputHandlerToken) {
        service.arm(types, for: token)
    }

    public func disarm(_ token: InputHandlerToken) {
        service.disarm(token)
    }

    public func postKey(_ keyCode: Int, down: Bool, modifiers: Shortcut.Modifiers = []) {
        service.postKey(keyCode, down: down, modifiers: modifiers)
    }

    /// A key press and release.
    public func tapKey(_ keyCode: Int, modifiers: Shortcut.Modifiers = []) {
        service.postKey(keyCode, down: true, modifiers: modifiers)
        service.postKey(keyCode, down: false, modifiers: modifiers)
    }
}
