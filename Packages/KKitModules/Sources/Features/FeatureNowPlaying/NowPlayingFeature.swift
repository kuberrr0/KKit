import AppKit
import KKitCore
import KKitServicesAPI
import KKitUI
import SwiftUI

/// What's playing in any app, in the Island: artwork and moving bars either side of the
/// notch while it plays, and a page with the track, a scrubber and controls.
/// DESIGN.md §2.2 and §3.5.
@MainActor
public final class NowPlayingFeature: Feature {
    public static let manifest = FeatureManifest(
        id: "nowPlaying",
        name: String(localized: "Now Playing"),
        symbol: "music.note",
        summary: String(localized: "See what's playing in the Island, with artwork and controls."),
        category: .audio,
        enabledByDefault: true
    )

    static let activityID = "nowPlaying"

    private let context: FeatureContext
    let model = NowPlayingModel()
    private var tasks: [Task<Void, Never>] = []
    private var activity: (any IslandHandle)?
    /// Whether the presented activity has compact ears, so it's only rebuilt when that changes.
    private var presentedCompact: Bool?

    public init(context: FeatureContext) {
        self.context = context
    }

    public func start() async throws {
        let updates = context.nowPlaying.updates()
        tasks.append(Task { [weak self] in
            for await info in updates {
                self?.model.update(info)
                self?.updateIsland()
            }
        })
        let availability = context.nowPlaying.availabilityUpdates()
        tasks.append(Task { [weak self] in
            for await value in availability {
                self?.model.update(availability: value)
            }
        })
        let compact = context.settings.changes(of: NowPlayingSettings.showCompact)
        tasks.append(Task { [weak self] in
            for await _ in compact {
                self?.updateIsland()
            }
        })
    }

    public func stop() async {
        tasks.forEach { $0.cancel() }
        tasks = []
        activity?.dismiss()
        activity = nil
        presentedCompact = nil
        model.update(nil)
    }

    // MARK: Contributions

    public var commands: [Command] {
        [
            Command(
                id: "nowPlaying.playPause",
                title: String(localized: "Play or Pause"),
                symbol: "playpause.fill",
                keywords: ["music", "media", "resume", "now playing"]
            ) { [weak self] _ in
                self?.send(.togglePlayPause)
            },
            Command(
                id: "nowPlaying.next",
                title: String(localized: "Next Track"),
                symbol: "forward.fill",
                keywords: ["music", "media", "skip", "now playing"]
            ) { [weak self] _ in
                self?.send(.nextTrack)
            },
            Command(
                id: "nowPlaying.previous",
                title: String(localized: "Previous Track"),
                symbol: "backward.fill",
                keywords: ["music", "media", "back", "now playing"]
            ) { [weak self] _ in
                self?.send(.previousTrack)
            },
            Command(
                id: "nowPlaying.show",
                title: String(localized: "Show Now Playing"),
                subtitle: String(localized: "Opens the Island on what's playing"),
                symbol: "music.note",
                keywords: ["music", "media", "island"],
                isEnabled: { [weak self] in self?.model.info != nil }
            ) { [weak self] _ in
                self?.context.island.showActivity(Self.activityID)
            },
        ]
    }

    public var settingsPane: SettingsPane? {
        SettingsPane { [model] in
            NowPlayingSettingsView(model: model)
        }
    }

    // MARK: Private

    private var actions: NowPlayingActions {
        NowPlayingActions(
            send: { [weak self] command in self?.send(command) },
            seek: { [weak self] seconds in self?.context.nowPlaying.seek(to: seconds) },
            openApp: { [weak self] in self?.openApp() }
        )
    }

    private func send(_ command: NowPlayingCommand) {
        context.nowPlaying.send(command)
    }

    private func openApp() {
        guard context.settings[NowPlayingSettings.clickArtworkOpensApp], let info = model.info else { return }
        if let pid = info.appPID, let app = NSRunningApplication(processIdentifier: pid), app.bundleIdentifier == info.appBundleID || info.appBundleID == nil {
            app.activate()
            return
        }
        if let bundleID = info.appBundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        }
    }

    private func updateIsland() {
        guard model.info != nil else {
            activity?.dismiss()
            activity = nil
            presentedCompact = nil
            return
        }
        let compact = model.showsCompact(setting: context.settings[NowPlayingSettings.showCompact])
        // The views watch the model, so a new track or position doesn't need a new activity.
        if let activity, activity.isActive, presentedCompact == compact {
            return
        }
        let island = IslandActivity(
            id: Self.activityID,
            title: String(localized: "Now Playing"),
            symbol: "music.note",
            priority: .normal,
            compactLeading: compact ? AnyView(NowPlayingCompactLeading(model: model)) : nil,
            compactTrailing: compact ? AnyView(NowPlayingCompactTrailing(model: model)) : nil,
            expanded: AnyView(NowPlayingPageView(model: model, actions: actions))
        )
        presentedCompact = compact
        if let activity, activity.isActive {
            activity.update(island)
        } else {
            activity = context.island.present(island)
        }
    }
}
