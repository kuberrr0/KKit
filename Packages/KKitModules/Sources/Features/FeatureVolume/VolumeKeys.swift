import KKitCore
import KKitServicesAPI

/// Tracks a hold-to-talk (or hold-to-mute) key: a normal key with its modifiers, or a
/// modifier on its own (Right ⌥, fn). Kept free of the tap for tests.
struct PushKeyTracker {
    enum Change: Equatable {
        case pressed
        case released
    }

    let key: Shortcut
    private(set) var isHeld = false

    init(key: Shortcut) {
        self.key = key
    }

    var isModifierOnly: Bool {
        key.modifiers.isEmpty && Shortcut.Key.isModifierKey(key.keyCode)
    }

    /// What an event does to the key, and whether to swallow it. Modifiers are never
    /// swallowed, so they keep working in the app in front.
    mutating func handle(
        _ type: InputEventType,
        keyCode: Int,
        modifiers: Shortcut.Modifiers,
        isFunctionDown: Bool,
        isRepeat: Bool
    ) -> (change: Change?, consume: Bool) {
        if isModifierOnly {
            guard type == .flagsChanged, keyCode == key.keyCode else { return (nil, false) }
            let flagDown: Bool
            if let modifier = Shortcut.Key.modifier(forKeyCode: keyCode) {
                flagDown = modifiers.contains(modifier)
            } else {
                flagDown = isFunctionDown
            }
            // The same modifier on the other side can keep the flag set, so a second
            // event for this key while it's held is its release.
            let down = flagDown && !isHeld
            if down {
                isHeld = true
                return (.pressed, false)
            }
            if isHeld {
                isHeld = false
                return (.released, false)
            }
            return (nil, false)
        }
        guard keyCode == key.keyCode else { return (nil, false) }
        switch type {
        case .keyDown:
            if isHeld || isRepeat {
                return (nil, isHeld)
            }
            guard modifiers == key.modifiers else { return (nil, false) }
            isHeld = true
            return (.pressed, true)
        case .keyUp:
            guard isHeld else { return (nil, false) }
            isHeld = false
            return (.released, true)
        default:
            return (nil, false)
        }
    }
}

/// What a media key does with the volume.
enum VolumeKeyAction: Equatable {
    case step(up: Bool, fine: Bool)
    case toggleMute
    /// The release (or a repeat of mute): swallow it so macOS doesn't act on it.
    case swallow
    case pass

    static func action(for media: MediaKeyEvent, modifiers: Shortcut.Modifiers) -> VolumeKeyAction {
        switch media.key {
        case .volumeUp, .volumeDown:
            guard media.isDown else { return .swallow }
            // ⇧⌥ gives quarter steps, like macOS.
            let fine = modifiers.contains(.shift) && modifiers.contains(.option)
            return .step(up: media.key == .volumeUp, fine: fine)
        case .mute:
            return media.isDown && !media.isRepeat ? .toggleMute : .swallow
        default:
            return .pass
        }
    }
}
