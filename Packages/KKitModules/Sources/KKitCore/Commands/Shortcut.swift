import Foundation

/// A keyboard shortcut, independent of AppKit so features and tests can declare one.
///
/// `keyCode` is the macOS virtual key code (Carbon `kVK_*`), e.g. 49 for Space.
public struct Shortcut: Hashable, Sendable, Codable {
    public struct Modifiers: OptionSet, Hashable, Sendable, Codable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let command = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let control = Modifiers(rawValue: 1 << 2)
        public static let shift = Modifiers(rawValue: 1 << 3)
        /// ⌃⌥⇧⌘, what the Hyper key sends.
        public static let hyper: Modifiers = [.command, .option, .control, .shift]
    }

    public var keyCode: Int
    public var modifiers: Modifiers

    public init(keyCode: Int, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// A few virtual key codes for declaring default shortcuts.
    public enum Key {
        public static let space = 49
        public static let returnKey = 36
        public static let escape = 53
        public static let comma = 43
        public static let a = 0, s = 1, d = 2, f = 3, h = 4, g = 5, z = 6, x = 7, c = 8, v = 9
        public static let b = 11, q = 12, w = 13, e = 14, r = 15, y = 16, t = 17
        public static let o = 31, u = 32, i = 34, p = 35, l = 37, j = 38, k = 40, n = 45, m = 46
        public static let leftArrow = 123, rightArrow = 124, downArrow = 125, upArrow = 126
        public static let tab = 48, delete = 51, forwardDelete = 117
        public static let equal = 24, minus = 27, leftBracket = 33, rightBracket = 30
        public static let zero = 29, one = 18, two = 19, three = 20, four = 21
        public static let five = 23, six = 22, seven = 26, eight = 28, nine = 25
        public static let home = 115, end = 119, pageUp = 116, pageDown = 121
        public static let f13 = 105, f14 = 107, f15 = 113, f16 = 106, f17 = 64, f18 = 79, f19 = 80, f20 = 90
        public static let capsLock = 57
        // Modifier keys on their own (push-to-talk can be one of these).
        public static let leftCommand = 55, rightCommand = 54
        public static let leftShift = 56, rightShift = 60
        public static let leftOption = 58, rightOption = 61
        public static let leftControl = 59, rightControl = 62
        public static let function = 63

        /// The modifier a modifier key's code stands for, `nil` for ordinary keys.
        public static func modifier(forKeyCode keyCode: Int) -> Modifiers? {
            switch keyCode {
            case leftCommand, rightCommand: .command
            case leftShift, rightShift: .shift
            case leftOption, rightOption: .option
            case leftControl, rightControl: .control
            default: nil
            }
        }

        /// Modifier keys (including fn), which arrive as flag changes rather than key presses.
        public static func isModifierKey(_ keyCode: Int) -> Bool {
            modifier(forKeyCode: keyCode) != nil || keyCode == function
        }

        /// F1–F20, which work as shortcuts without a modifier.
        public static let functionKeys: [Int] = [
            122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, f13, f14, f15, f16, f17, f18, f19, f20,
        ]

        public static func isFunctionKey(_ keyCode: Int) -> Bool {
            functionKeys.contains(keyCode)
        }
    }
}
