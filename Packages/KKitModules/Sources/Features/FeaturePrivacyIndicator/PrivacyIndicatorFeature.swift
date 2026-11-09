import KKitCore
import KKitServicesAPI
import KKitUI
import SwiftUI
import os

/// Shows in the Island while an app uses the microphone or a camera; red when the mic
/// is muted, click to toggle mute. Optional 7-day log. DESIGN.md §3.15.
@MainActor
public final class PrivacyIndicatorFeature: Feature {
    public static let manifest = FeatureManifest(
        id: "privacyIndicator",
        name: String(localized: "Privacy Indicator"),
        symbol: "mic.badge.xmark",
        summary: String(localized: "See in the Island when an app uses your microphone or camera."),
        category: .system,
        enabledByDefault: true
    )

    static let logFile = "log.json"

    private let context: FeatureContext
    let model = PrivacyModel()
    private var tasks: [Task<Void, Never>] = []
    private var activity: (any IslandHandle)?

    public init(context: FeatureContext) {
        self.context = context
    }

    public func start() async throws {
        if let saved = try? context.storage.read(UsageLog.self, named: Self.logFile) {
            var log = saved
            log.closeAll(at: Date())
            log.prune(now: Date())
            model.loadLog(log)
        }
        model.update(audio: context.audio.state)

        let usage = context.deviceUsage.updates()
        tasks.append(Task { [weak self] in
            for await value in usage {
                self?.receive(value)
            }
        })
        let audio = context.audio.updates()
        tasks.append(Task { [weak self] in
            for await state in audio {
                self?.model.update(audio: state)
                self?.updateIsland()
            }
        })
        for key in [PrivacySettings.showMic, PrivacySettings.showCamera, PrivacySettings.showAppNames, PrivacySettings.clickTogglesMute] {
            let changes = context.settings.changes(of: key)
            tasks.append(Task { [weak self] in
                for await _ in changes {
                    self?.updateIsland()
                }
            })
        }
        let keepLog = context.settings.changes(of: PrivacySettings.keepLog)
        tasks.append(Task { [weak self] in
            for await on in keepLog where !on {
                self?.clearLog()
            }
        })
    }

    public func stop() async {
        tasks.forEach { $0.cancel() }
        tasks = []
        activity?.dismiss()
        activity = nil
        if context.settings[PrivacySettings.keepLog] {
            model.closeLog(at: Date())
            saveLog()
        }
    }

    // MARK: Contributions

    public var commands: [Command] {
        [
            Command(
                id: "privacyIndicator.clearLog",
                title: String(localized: "Clear Mic & Camera Log"),
                symbol: "trash",
                keywords: ["privacy", "history"]
            ) { [weak self] _ in
                self?.clearLog()
            },
        ]
    }

    public var settingsPane: SettingsPane? {
        SettingsPane { [model, weak self] in
            PrivacySettingsView(model: model) { self?.clearLog() }
        }
    }

    // MARK: Private

    private func receive(_ usage: DeviceUsage) {
        model.update(usage: usage, keepLog: context.settings[PrivacySettings.keepLog], at: Date())
        if model.logIsDirty {
            saveLog()
        }
        updateIsland()
    }

    private func clearLog() {
        model.clearLog()
        saveLog()
    }

    private func saveLog() {
        do {
            if model.log.entries.isEmpty {
                try context.storage.remove(named: Self.logFile)
            } else {
                try context.storage.write(model.log, named: Self.logFile)
            }
            model.markSaved()
        } catch {
            context.log.error("Couldn't save the usage log: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func toggleMute() {
        let audio = context.audio
        let muted = !audio.state.inputMuted
        audio.setMuted(muted, for: .input)
        context.island.showHUD(IslandHUD(
            id: "mic",
            symbol: muted ? "mic.slash.fill" : "mic.fill",
            title: muted ? String(localized: "Microphone muted") : String(localized: "Microphone on"),
            tint: muted ? .critical : .normal
        ))
    }

    private func updateIsland() {
        let settings = context.settings
        guard let indicator = model.indicator(
            showMic: settings[PrivacySettings.showMic],
            showCamera: settings[PrivacySettings.showCamera],
            showAppNames: settings[PrivacySettings.showAppNames]
        ) else {
            activity?.dismiss()
            activity = nil
            return
        }
        let tapToggles = settings[PrivacySettings.clickTogglesMute] && indicator.micInUse
        let island = IslandActivity(
            id: "inUse",
            title: String(localized: "Mic & Camera"),
            symbol: indicator.micInUse ? "mic.fill" : "video.fill",
            priority: .high,
            compactLeading: AnyView(PrivacyCompactLeading(indicator: indicator)),
            compactTrailing: AnyView(PrivacyCompactTrailing(indicator: indicator)),
            expanded: AnyView(PrivacyIslandView(model: model) { [weak self] in self?.toggleMute() }),
            onTap: tapToggles ? { [weak self] in self?.toggleMute() } : nil
        )
        if let activity, activity.isActive {
            activity.update(island)
        } else {
            activity = context.island.present(island)
        }
    }
}
