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
    }
}
