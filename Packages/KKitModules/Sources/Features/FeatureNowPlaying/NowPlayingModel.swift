import AppKit
import Foundation
import KKitServicesAPI
import Observation

/// What the Now Playing views show: the current track, its artwork as an image, and
/// the app playing it.
@MainActor
@Observable
final class NowPlayingModel {
    private(set) var info: NowPlayingInfo?
    private(set) var availability: NowPlayingAvailability = .unknown
    /// Decoded once per artwork change, not on every redraw.
    private(set) var artwork: NSImage?
    private(set) var appName: String?
    private(set) var appIcon: NSImage?

    init() {}

    func update(_ info: NowPlayingInfo?) {
        let old = self.info
        self.info = info
        if info?.artwork != old?.artwork {
            artwork = info?.artwork.flatMap { NSImage(data: $0) }
        }
        if info?.appBundleID != old?.appBundleID || info?.appPID != old?.appPID {
            resolveApp(bundleID: info?.appBundleID, pid: info?.appPID)
        }
    }

    func update(availability: NowPlayingAvailability) {
        self.availability = availability
    }

    /// Whether the compact Island shows the track: only while it plays.
    func showsCompact(setting: Bool) -> Bool {
        setting && info?.isPlaying == true
    }

    private func resolveApp(bundleID: String?, pid: Int32?) {
        let running = pid.flatMap { NSRunningApplication(processIdentifier: $0) }
        if let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            appName = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            appIcon = NSWorkspace.shared.icon(forFile: url.path)
        } else if let running {
            appName = running.localizedName
            appIcon = running.icon
        } else {
            appName = nil
            appIcon = nil
        }
    }
}

/// Times on the scrubber.
enum NowPlayingFormat {
    /// "0:07", "3:25", "1:02:03". Whole seconds, rounded down.
    static func time(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "–:––" }
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// 0…1 through the track, or `nil` without a duration.
    static func progress(position: Double?, duration: Double?) -> Double? {
        guard let position, let duration, duration > 0 else { return nil }
        return min(max(position / duration, 0), 1)
    }
}
