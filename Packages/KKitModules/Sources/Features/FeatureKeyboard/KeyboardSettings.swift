import Foundation
import KKitCore

/// What a key binding or leader sequence does.
enum KeyAction: Codable, Hashable, Sendable {
    /// Opens the app, or brings it to the front. A second press does `SecondPress`.
    case openApp(path: String)
    case openURL(String)
    case openFile(path: String)
    /// Any KKit command, with an optional typed value ("30", "25m").
    case runCommand(CommandID, value: String?)
    /// A Shortcuts.app shortcut, by name.
    case runShortcut(name: String)
    /// Run with `zsh -lc`.
    case shellScript(String)

    enum Kind: String, CaseIterable, Identifiable {
        case openApp, openURL, openFile, runCommand, runShortcut, shellScript

        var id: String { rawValue }

        var title: String {
            switch self {
            case .openApp: String(localized: "Open App")
            case .openURL: String(localized: "Open Link")
            case .openFile: String(localized: "Open File or Folder")
            case .runCommand: String(localized: "Run KKit Command")
            case .runShortcut: String(localized: "Run Shortcut")
            case .shellScript: String(localized: "Run Shell Script")
            }
        }

        var symbol: String {
            switch self {
            case .openApp: "app"
            case .openURL: "link"
            case .openFile: "doc"
            case .runCommand: "command"
            case .runShortcut: "square.stack.3d.up"
            case .shellScript: "terminal"
            }
        }

        /// An empty action of this kind, for the editor.
        var blank: KeyAction {
            switch self {
            case .openApp: .openApp(path: "")
            case .openURL: .openURL("")
            case .openFile: .openFile(path: "")
            case .runCommand: .runCommand(CommandID(""), value: nil)
            case .runShortcut: .runShortcut(name: "")
            case .shellScript: .shellScript("")
            }
        }
    }

    var kind: Kind {
        switch self {
        case .openApp: .openApp
        case .openURL: .openURL
        case .openFile: .openFile
        case .runCommand: .runCommand
        case .runShortcut: .runShortcut
        case .shellScript: .shellScript
        }
    }

    /// One line for lists and the cheat sheet: "Safari", "github.com", "Toggle Night Shift".
    func summary(commandTitle: (CommandID) -> String? = { _ in nil }) -> String {
        switch self {
        case .openApp(let path):
            path.isEmpty ? String(localized: "No app chosen")
                : ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        case .openURL(let text):
            text.isEmpty ? String(localized: "No link") : text
        case .openFile(let path):
            path.isEmpty ? String(localized: "No file chosen") : (path as NSString).lastPathComponent
        case .runCommand(let id, let value):
            id.rawValue.isEmpty ? String(localized: "No command chosen")
                : [commandTitle(id) ?? id.rawValue, value].compactMap { $0 }.joined(separator: " ")
        case .runShortcut(let name):
            name.isEmpty ? String(localized: "No shortcut") : name
        case .shellScript(let script):
            script.isEmpty ? String(localized: "Empty script") : script
        }
    }

    var isEmpty: Bool {
        switch self {
        case .openApp(let path), .openFile(let path): path.isEmpty
        case .openURL(let text), .runShortcut(let text), .shellScript(let text): text.isEmpty
        case .runCommand(let id, _): id.rawValue.isEmpty
        }
    }
}

/// What pressing an app's key does when the app is already in front.
enum SecondPress: String, Codable, CaseIterable, Sendable {
    case hide
    case cycleWindows
    case nothing

    var title: String {
        switch self {
        case .hide: String(localized: "Hide it")
        case .cycleWindows: String(localized: "Cycle its windows")
        case .nothing: String(localized: "Nothing")
        }
    }
}

/// A key (usually Hyper + a letter) that runs an action.
struct KeyBinding: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var trigger: Shortcut?
    var action: KeyAction
    var secondPress: SecondPress = .hide
}

/// Keys typed after the leader key: "nd" → new daily note.
struct LeaderSequence: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    /// Lowercase characters, typed one after another.
    var keys: String
    var title: String
    var action: KeyAction

    /// `keys` without spaces, lowercased.
    var normalizedKeys: String {
        keys.lowercased().filter { !$0.isWhitespace }
    }
}

/// What tapping Caps Lock (without another key) sends while it's the Hyper key.
enum CapsLockTap: String, Codable, CaseIterable, Sendable {
    case escape
    case nothing

    var title: String {
        switch self {
        case .escape: String(localized: "Escape")
        case .nothing: String(localized: "Nothing")
        }
    }
}

enum KeyboardSettings {
    /// Caps Lock is ⌃⌥⇧⌘ while held.
    static let hyperEnabled = SettingKey("hyperEnabled", default: true)
    static let capsLockTap = SettingKey("capsLockTap", default: CapsLockTap.escape)
    static let bindings = SettingKey("bindings", default: [KeyBinding]())
    static let leaderEnabled = SettingKey("leaderEnabled", default: true)
    /// Hyper + Space by default.
    static let leaderKey = SettingKey<Shortcut?>("leaderKey", default: Shortcut(keyCode: Shortcut.Key.space, modifiers: .hyper))
    static let sequences = SettingKey("sequences", default: [LeaderSequence]())
    /// Seconds to wait for the next key of a sequence.
    static let leaderTimeout = SettingKey("leaderTimeout", default: 2.0)
    static let cheatSheetEnabled = SettingKey("cheatSheetEnabled", default: true)
    /// Seconds Hyper is held alone before the cheat sheet appears.
    static let cheatSheetDelay = SettingKey("cheatSheetDelay", default: 1.0)
}
