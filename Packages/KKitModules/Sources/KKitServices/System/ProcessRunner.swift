import Foundation
import KKitServicesAPI

/// Runs a command-line tool off the main thread and returns its standard output.
enum ProcessRunner {
    @discardableResult
    static func run(_ executable: String, _ arguments: [String]) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let output = Pipe()
            let errors = Pipe()
            process.standardOutput = output
            process.standardError = errors
            try process.run()
            let outputData = output.fileHandleForReading.readDataToEndOfFile()
            let errorData = errors.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let message = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                throw SystemActionError(message.isEmpty
                    ? "\((executable as NSString).lastPathComponent) failed (\(process.terminationStatus))."
                    : message)
            }
            return String(data: outputData, encoding: .utf8) ?? ""
        }.value
    }

    /// Runs AppleScript with `osascript`, so a slow script or an Automation prompt never
    /// blocks the main thread. macOS attributes the Automation request to KKit.
    @discardableResult
    static func appleScript(_ source: String) async throws -> String {
        do {
            return try await run("/usr/bin/osascript", ["-e", source])
        } catch let error as SystemActionError where error.message.contains("-1743") {
            throw SystemActionError(String(localized: "KKit isn't allowed to control that app. Allow it in System Settings › Privacy & Security › Automation."))
        }
    }
}
