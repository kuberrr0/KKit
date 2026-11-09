import Foundation

/// The Hyper key's state, kept pure for tests. Caps Lock is remapped (by `hidutil`) to a
/// spare key; while that key is held every other key gets ⌃⌥⇧⌘, and tapping it alone
/// sends Escape.
struct HyperKeyMachine {
    enum Result: Equatable {
        /// Not the Hyper key, and Hyper isn't held: leave the event alone.
        case passThrough
        /// The Hyper key went down. Swallow it.
        case pressed
        /// The Hyper key came up. Swallow it; `tapped` means send the tap key.
        case released(tapped: Bool)
        /// The Hyper key's auto-repeat or a stray release. Swallow it.
        case swallow
        /// Another key while Hyper is held: add ⌃⌥⇧⌘ and let it through.
        case addHyper
    }

    let keyCode: Int
    /// A press longer than this isn't a tap.
    var tapTimeout: TimeInterval = 0.5
    private(set) var isHeld = false
    private(set) var wasUsed = false
    private var pressedAt: Date?

    init(keyCode: Int) {
        self.keyCode = keyCode
    }

    mutating func handle(keyCode code: Int, isDown: Bool, isRepeat: Bool, at time: Date) -> Result {
        if code == keyCode {
            if isDown {
                guard !isHeld, !isRepeat else { return .swallow }
                isHeld = true
                wasUsed = false
                pressedAt = time
                return .pressed
            }
            guard isHeld else { return .swallow }
            isHeld = false
            let quick = pressedAt.map { time.timeIntervalSince($0) <= tapTimeout } ?? false
            pressedAt = nil
            return .released(tapped: quick && !wasUsed)
        }
        guard isHeld else { return .passThrough }
        if isDown {
            wasUsed = true
        }
        return .addHyper
    }

    /// Something used the held key on its own (the cheat sheet), so releasing it isn't a tap.
    mutating func markUsed() {
        wasUsed = true
    }

    /// Forget a held key (the tap was rebuilt, the feature stopped).
    mutating func reset() {
        isHeld = false
        wasUsed = false
        pressedAt = nil
    }
}
