import AppKit
import KKitCore
import KKitUI
import SwiftUI

/// Which timer a compact view shows.
enum TimerKind: Equatable {
    case countdown(UUID)
    case stopwatch
}

extension TimerModel {
    /// Remaining (countdown) or elapsed (stopwatch) time.
    func displayTime(_ kind: TimerKind, at date: Date) -> TimeInterval {
        switch kind {
        case .countdown(let id): countdowns.first { $0.id == id }?.remaining(at: date) ?? 0
        case .stopwatch: stopwatch.elapsed(at: date)
        }
    }

    func progress(_ kind: TimerKind, at date: Date) -> Double {
        switch kind {
        case .countdown(let id): countdowns.first { $0.id == id }?.progress(at: date) ?? 1
        case .stopwatch: 0
        }
    }

    func isRunning(_ kind: TimerKind) -> Bool {
        switch kind {
        case .countdown(let id): countdowns.first { $0.id == id }?.isRunning ?? false
        case .stopwatch: stopwatch.isRunning
        }
    }
}

/// Ticks once a second while it's on screen, and not at all while paused.
struct TimerTicker<Content: View>: View {
    let isRunning: Bool
    @ViewBuilder let content: (Date) -> Content

    var body: some View {
        if isRunning {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                content(timeline.date)
            }
        } else {
            content(Date())
        }
    }
}

/// Left ear: progress ring.
struct TimerRing: View {
    let model: TimerModel
    let kind: TimerKind

    var body: some View {
        TimerTicker(isRunning: model.isRunning(kind)) { date in
            KKProgressRing(progress: model.progress(kind, at: date), tint: .orange, lineWidth: 2.5)
                .frame(width: 14, height: 14)
        }
        .accessibilityHidden(true)
    }
}

/// Right ear: "4:05".
struct TimerClock: View {
    let model: TimerModel
    let kind: TimerKind

    var body: some View {
        TimerTicker(isRunning: model.isRunning(kind)) { date in
            Text(KKFormat.clock(model.displayTime(kind, at: date)))
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(model.isRunning(kind) ? Color.white : Color.white.opacity(0.55))
        }
    }
}

/// Big time readout for the expanded Island.
struct TimerBigClock: View {
    let model: TimerModel
    let kind: TimerKind

    var body: some View {
        TimerTicker(isRunning: model.isRunning(kind)) { date in
            Text(KKFormat.clock(model.displayTime(kind, at: date)))
                .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())
        }
    }
}

struct CountdownIslandView: View {
    let controller: TimerController
    let id: UUID

    var body: some View {
        let model = controller.model
        if let countdown = model.countdowns.first(where: { $0.id == id }) {
            HStack(spacing: KKSpacing.l) {
                VStack(alignment: .leading, spacing: KKSpacing.xxs) {
                    Text(countdown.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TimerBigClock(model: model, kind: .countdown(id))
                }
                Spacer()
                TimerControlButton(symbol: "plus", label: String(localized: "Add a minute")) {
                    controller.addMinute(to: id)
                }
                TimerControlButton(
                    symbol: countdown.isRunning ? "pause.fill" : "play.fill",
                    label: countdown.isRunning ? String(localized: "Pause") : String(localized: "Resume")
                ) {
                    controller.togglePause(id)
                }
                TimerControlButton(symbol: "xmark", label: String(localized: "Cancel")) {
                    controller.cancel(id)
                }
            }
        }
    }
}

struct StopwatchIslandView: View {
    let controller: TimerController

    var body: some View {
        let stopwatch = controller.model.stopwatch
        HStack(alignment: .top, spacing: KKSpacing.l) {
            VStack(alignment: .leading, spacing: KKSpacing.xxs) {
                Text("Stopwatch")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                TimerBigClock(model: controller.model, kind: .stopwatch)
                let laps = Array(stopwatch.lapDurations.enumerated().suffix(3).reversed())
                ForEach(laps, id: \.offset) { item in
                    Text("Lap \(item.offset + 1)  \(KKFormat.clock(item.element))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            TimerControlButton(symbol: "flag.fill", label: String(localized: "Lap")) {
                controller.lap()
            }
            .disabled(!stopwatch.isRunning)
            TimerControlButton(
                symbol: stopwatch.isRunning ? "pause.fill" : "play.fill",
                label: stopwatch.isRunning ? String(localized: "Pause") : String(localized: "Start")
            ) {
                controller.toggleStopwatch()
            }
            TimerControlButton(symbol: "arrow.counterclockwise", label: String(localized: "Reset")) {
                controller.resetStopwatch()
            }
        }
    }
}

/// The Timer page in the expanded Island: quick starts and what's running.
struct TimerIslandPage: View {
    let controller: TimerController

    private struct Preset: Identifiable {
        let minutes: Double
        var id: Double { minutes }
    }

    private var presets: [Preset] { [1, 3, 5, 10, 15, 25, 60].map(Preset.init) }

    var body: some View {
        let model = controller.model
        VStack(alignment: .leading, spacing: KKSpacing.s) {
            HStack(spacing: KKSpacing.xs) {
                ForEach(presets) { preset in
                    Button(KKFormat.shortDuration(preset.minutes * 60)) {
                        controller.start(preset.minutes * 60)
                    }
                    .controlSize(.small)
                }
            }
            Button {
                controller.toggleStopwatch()
            } label: {
                Label(model.stopwatch.isRunning ? String(localized: "Pause Stopwatch") : String(localized: "Stopwatch"), systemImage: "stopwatch")
            }
            .controlSize(.small)
            if model.countdowns.isEmpty {
                Text("Type “timer 10m tea” in the Floating Bar for a labeled timer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.countdowns) { countdown in
                    HStack {
                        Text(countdown.title)
                            .font(.callout)
                        Spacer()
                        TimerClock(model: model, kind: .countdown(countdown.id))
                        Button {
                            controller.cancel(countdown.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text("Cancel \(countdown.title)"))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TimerControlButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
        .help(Text(label))
        .accessibilityLabel(Text(label))
    }
}

/// Settings › Timer.
struct TimerSettingsView: View {
    @Setting(TimerSettings.defaultMinutes) private var defaultMinutes
    @Setting(TimerSettings.sound) private var sound
    @Setting(TimerSettings.notify) private var notify
    @Setting(TimerSettings.showInIsland) private var showInIsland

    private let sounds = ["Glass", "Hero", "Ping", "Purr", "Submarine", "Funk", "Blow", "Tink"]

    var body: some View {
        Group {
            KKSection(String(localized: "Timers")) {
                Stepper(value: $defaultMinutes, in: 1...240, step: 1) {
                    Text("Default length: \(KKFormat.shortDuration(defaultMinutes * 60))")
                }
                Toggle(String(localized: "Show in the Island"), isOn: $showInIsland)
            }
            KKSection(
                String(localized: "When a timer ends"),
                footer: String(localized: "Notifications need the Notifications permission; the Island alert always shows.")
            ) {
                Picker(String(localized: "Sound"), selection: $sound) {
                    Text("None").tag("")
                    ForEach(sounds, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .onChange(of: sound) { _, name in
                    if !name.isEmpty {
                        NSSound(named: NSSound.Name(name))?.play()
                    }
                }
                Toggle(String(localized: "Also post a notification"), isOn: $notify)
            }
        }
    }
}
