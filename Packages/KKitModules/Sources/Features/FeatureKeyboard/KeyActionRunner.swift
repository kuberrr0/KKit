import AppKit
import KKitCore
import KKitServicesAPI
import os

/// Runs a key binding's or leader sequence's action.
@MainActor
struct KeyActionRunner: Sendable {
    let commandRunner: any CommandRunnerService
    let input: FeatureInput
    let log: Logger
    /// Shows a failure in the Island.
    let report: @MainActor @Sendable (String) -> Void

    func run(_ action: KeyAction, secondPress: SecondPress = .hide) {
        switch action {
        case .openApp(let path):
            openApp(at: path, secondPress: secondPress)
        case .openURL(let text):
            guard let url = Self.url(from: text) else {
                report(String(localized: "“\(text)” isn't a link."))
                return
            }
            NSWorkspace.shared.open(url)
        case .openFile(let path):
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                report(String(localized: "“\(url.lastPathComponent)” isn't there any more."))
                return
            }
            NSWorkspace.shared.open(url)
        case .runCommand(let id, let value):
            let runner = commandRunner
            let report = report
            Task {
                do {
                    try await runner.run(id, value: value)
                } catch {
                    report(error.localizedDescription)
                }
            }
        case .runShortcut(let name):
            runTool("/usr/bin/shortcuts", ["run", name], label: name)
        case .shellScript(let script):
            runTool("/bin/zsh", ["-lc", script], label: String(localized: "Shell script"))
        }
    }

    /// "github.com" works as well as "https://github.com".
    static func url(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        guard trimmed.contains("."), !trimmed.contains(" ") else { return nil }
        return URL(string: "https://" + trimmed)
    }

    // MARK: Private

    private func openApp(at path: String, secondPress: SecondPress) {
        let url = URL(fileURLWithPath: path)
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleURL?.standardizedFileURL == url.standardizedFileURL {
            switch secondPress {
            case .hide:
                front.hide()
            case .cycleWindows:
                // ⌘` is macOS's "move focus to next window".
                input.tapKey(50, modifiers: [.command])
            case .nothing:
                break
            }
            return
        }
        guard FileManager.default.fileExists(atPath: path) else {
            report(String(localized: "“\(url.deletingPathExtension().lastPathComponent)” isn't installed there any more."))
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
    }

    private func runTool(_ executable: String, _ arguments: [String], label: String) {
        let log = log
        let report = report
        Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                let status = process.terminationStatus
                if status != 0 {
                    log.error("\(label, privacy: .public) exited with \(status)")
                    await report(String(localized: "“\(label)” failed (\(status))."))
                }
            } catch {
                log.error("\(label, privacy: .public) didn't start: \(error.localizedDescription, privacy: .public)")
                await report(error.localizedDescription)
            }
        }
    }
}
