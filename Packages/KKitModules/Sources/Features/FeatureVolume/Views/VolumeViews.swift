import AppKit
import KKitCore
import KKitServicesAPI
import KKitUI
import SwiftUI

/// The volume row in the KKit menu: mute button, slider, and output/input pickers.
struct VolumeMenuSection: View {
    let controller: VolumeController
    @State private var showsApps = false

    var body: some View {
        let state = controller.state
        VStack(alignment: .leading, spacing: KKSpacing.s) {
            HStack(spacing: KKSpacing.s) {
                Button {
                    controller.toggleMute()
                } label: {
                    Image(systemName: VolumeMath.speakerSymbol(volume: state.outputVolume, muted: state.outputMuted))
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 20)
                }
                .buttonStyle(.borderless)
                .help(state.outputMuted ? Text("Unmute") : Text("Mute"))
                .accessibilityLabel(state.outputMuted ? Text("Unmute") : Text("Mute"))

                if let volume = controller.effectiveOutputVolume {
                    Slider(
                        value: Binding(
                            get: { volume },
                            set: { controller.setVolume($0, source: .slider) }
                        ),
                        in: 0...controller.limit
                    )
                    .labelsHidden()
                    .accessibilityLabel(Text("Volume"))
                    .accessibilityValue(Text(KKFormat.percent(volume)))
                    Text(KKFormat.percent(volume))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 40, alignment: .trailing)
                } else {
                    Text("This device has no volume control")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            HStack(spacing: KKSpacing.s) {
                AudioDeviceMenu(
                    devices: state.outputDevices,
                    current: state.defaultOutput,
                    symbol: "hifispeaker",
                    label: String(localized: "Output")
                ) { controller.setDefault($0, for: .output) }
                Spacer(minLength: KKSpacing.s)
                AudioDeviceMenu(
                    devices: state.inputDevices,
                    current: state.defaultInput,
                    symbol: "mic",
                    label: String(localized: "Input")
                ) { controller.setDefault($0, for: .input) }
                Button {
                    controller.toggleMicMute()
                } label: {
                    Image(systemName: state.inputMuted ? "mic.slash.fill" : "mic.fill")
                        .foregroundStyle(state.inputMuted ? Color.red : Color.secondary)
                        .frame(width: 20)
                }
                .buttonStyle(.borderless)
                .disabled(state.defaultInput == nil)
                .help(state.inputMuted ? Text("Unmute microphone") : Text("Mute microphone"))
                .accessibilityLabel(state.inputMuted ? Text("Unmute microphone") : Text("Mute microphone"))
            }
            DisclosureGroup(isExpanded: $showsApps) {
                AppVolumeList(controller: controller, playingOnly: true)
                    .padding(.top, KKSpacing.xs)
            } label: {
                Text("App volume")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A compact pop-up menu of devices with the current one checked.
struct AudioDeviceMenu: View {
    let devices: [AudioDevice]
    let current: AudioDevice?
    let symbol: String
    let label: String
    let select: (AudioDevice) -> Void

    var body: some View {
        Menu {
            if devices.isEmpty {
                Text("No devices")
            }
            ForEach(devices) { device in
                Button {
                    select(device)
                } label: {
                    if device.uid == current?.uid {
                        Label(device.name, systemImage: "checkmark")
                    } else {
                        Text(device.name)
                    }
                }
            }
        } label: {
            Label(current?.name ?? String(localized: "None"), systemImage: symbol)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 150, alignment: .leading)
        .help(Text(label))
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(current?.name ?? String(localized: "None")))
    }
}

/// Settings › Volume & Audio.
struct VolumeSettingsView: View {
    let controller: VolumeController
    let inputTapRunning: @MainActor () -> Bool
    let requestAccess: @MainActor () -> Void

    @Setting(VolumeSettings.step) private var step
    @Setting(VolumeSettings.volumeLimit) private var volumeLimit
    @Setting(VolumeSettings.showHUD) private var showHUD
    @Setting(VolumeSettings.hudForSystemChanges) private var hudForSystemChanges
    @Setting(VolumeSettings.scrollOnIsland) private var scrollOnIsland
    @Setting(VolumeSettings.soundOnMicMute) private var soundOnMicMute
    @Setting(VolumeSettings.autoSwitchOutput) private var autoSwitchOutput
    @Setting(VolumeSettings.outputPriority) private var outputPriority
    @Setting(VolumeSettings.autoSwitchInput) private var autoSwitchInput
    @Setting(VolumeSettings.inputPriority) private var inputPriority
    @Setting(VolumeSettings.takeOverVolumeKeys) private var takeOverVolumeKeys
    @Setting(VolumeSettings.pushToTalkKey) private var pushToTalkKey
    @Setting(VolumeSettings.pushToMuteKey) private var pushToMuteKey

    private struct StepOption: Identifiable {
        let label: String
        let value: Double
        var id: Double { value }
    }

    private var steps: [StepOption] {
        [
            StepOption(label: "1%", value: 0.01),
            StepOption(label: "2%", value: 0.02),
            StepOption(label: "5%", value: 0.05),
            StepOption(label: String(localized: "6.25% (like macOS)"), value: 0.0625),
            StepOption(label: "10%", value: 0.1),
        ]
    }

    var body: some View {
        Group {
            KKSection(String(localized: "Volume")) {
                Picker(String(localized: "Step size"), selection: $step) {
                    ForEach(steps) { item in
                        Text(item.label).tag(item.value)
                    }
                }
                LabeledContent(String(localized: "Volume limit")) {
                    HStack {
                        Slider(value: $volumeLimit, in: 0.1...1, step: 0.05)
                            .frame(maxWidth: 220)
                            .accessibilityLabel(Text("Volume limit"))
                        Text(KKFormat.percent(volumeLimit))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 40, alignment: .trailing)
                    }
                }
                Toggle(String(localized: "Scroll on the Island to change the volume"), isOn: $scrollOnIsland)
                Text("Hold ⌥ while scrolling for fine steps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            KKSection(
                String(localized: "Volume keys and HUD"),
                footer: String(localized: "With the volume keys taken over, KKit uses its step size and limit and shows the Island HUD instead of macOS's. ⇧⌥ with a volume key gives quarter steps. Needs Accessibility.")
            ) {
                Toggle(String(localized: "Use KKit for the volume keys"), isOn: $takeOverVolumeKeys)
                if takeOverVolumeKeys, !inputTapRunning() {
                    HStack {
                        Text("KKit needs Accessibility to see the volume keys.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Spacer()
                        Button(String(localized: "Allow…")) { requestAccess() }
                    }
                }
                Toggle(String(localized: "Show a HUD for changes made with KKit"), isOn: $showHUD)
                Toggle(String(localized: "Also for changes made in Control Center and other apps"), isOn: $hudForSystemChanges)
            }
            KKSection(
                String(localized: "Microphone"),
                footer: String(localized: "With a push-to-talk key the microphone stays muted until you hold the key. A key on its own, like Right ⌥ or fn, works too. Needs Accessibility.")
            ) {
                Toggle(String(localized: "Play a sound on mute and unmute"), isOn: $soundOnMicMute)
                LabeledContent(String(localized: "Push to talk")) {
                    KKKeyRecorder(shortcut: $pushToTalkKey, allowsModifierOnly: true)
                }
                LabeledContent(String(localized: "Push to mute")) {
                    KKKeyRecorder(shortcut: $pushToMuteKey, allowsModifierOnly: true)
                }
                if pushToTalkKey != nil, pushToTalkKey == pushToMuteKey {
                    Text("Use different keys for push to talk and push to mute.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            KKSection(
                String(localized: "App volume"),
                footer: String(localized: "Turning an app down plays its sound through KKit, quieter. The first time, macOS asks to let KKit capture audio. Volumes are remembered per app.")
            ) {
                AppVolumeList(controller: controller)
            }
            KKSection(
                String(localized: "Output auto-switch"),
                footer: String(localized: "When a device connects or disconnects, KKit switches to the first connected device in this list.")
            ) {
                Toggle(String(localized: "Switch output automatically"), isOn: $autoSwitchOutput)
                PriorityListEditor(list: $outputPriority, available: controller.state.outputDevices)
                    .disabled(!autoSwitchOutput)
            }
            KKSection(String(localized: "Input auto-switch")) {
                Toggle(String(localized: "Switch input automatically"), isOn: $autoSwitchInput)
                PriorityListEditor(list: $inputPriority, available: controller.state.inputDevices)
                    .disabled(!autoSwitchInput)
            }
        }
    }
}

/// An ordered list of devices with move up/down, remove and add.
struct PriorityListEditor: View {
    @Binding var list: [PriorityDevice]
    let available: [AudioDevice]

    var body: some View {
        ForEach(Array(list.enumerated()), id: \.element.id) { index, entry in
            HStack {
                Text("\(index + 1).")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text(entry.name)
                if !available.contains(where: { $0.uid == entry.uid }) {
                    KKStatusBadge(String(localized: "Not connected"), tone: .neutral)
                }
                Spacer()
                Button {
                    move(index, by: -1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(index == 0)
                .accessibilityLabel(Text("Move up"))
                Button {
                    move(index, by: 1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(index == list.count - 1)
                .accessibilityLabel(Text("Move down"))
                Button {
                    list.remove(at: index)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .accessibilityLabel(Text("Remove"))
            }
            .buttonStyle(.borderless)
        }
        let addable = available.filter { device in !list.contains { $0.uid == device.uid } }
        Menu(String(localized: "Add Device")) {
            ForEach(addable) { device in
                Button(device.name) {
                    list.append(PriorityDevice(uid: device.uid, name: device.name))
                }
            }
        }
        .disabled(addable.isEmpty)
        .fixedSize()
    }

    private func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard list.indices.contains(target) else { return }
        list.swapAt(index, target)
    }
}

/// Apps with audio and a slider each.
struct AppVolumeList: View {
    let controller: VolumeController
    var playingOnly = false

    @State private var apps: [AudioApp] = []
    @State private var volumes: [String: Double] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: KKSpacing.s) {
            if shownApps.isEmpty {
                Text(playingOnly ? "No apps are playing sound." : "No apps are using audio.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(shownApps) { app in
                HStack(spacing: KKSpacing.s) {
                    AppIcon(bundleID: app.bundleID)
                    Text(app.name)
                        .lineLimit(1)
                        .frame(width: 110, alignment: .leading)
                    Slider(
                        value: Binding(
                            get: { volumes[app.bundleID] ?? controller.appVolume(for: app.bundleID) },
                            set: { value in
                                volumes[app.bundleID] = value
                                controller.setAppVolume(value, for: app.bundleID)
                            }
                        ),
                        in: 0...1
                    )
                    .labelsHidden()
                    .accessibilityLabel(Text("\(app.name) volume"))
                    Text(KKFormat.percent(volumes[app.bundleID] ?? controller.appVolume(for: app.bundleID)))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 40, alignment: .trailing)
                }
            }
            if !playingOnly {
                Button(String(localized: "Refresh")) { reload() }
            }
        }
        .onAppear { reload() }
    }

    private var shownApps: [AudioApp] {
        playingOnly ? apps.filter { $0.isPlaying || controller.appVolume(for: $0.bundleID) < 1 } : apps
    }

    private func reload() {
        apps = controller.audioApps()
        volumes = [:]
    }
}

private struct AppIcon: View {
    let bundleID: String

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 18, height: 18)
        } else {
            Image(systemName: "app")
                .frame(width: 18, height: 18)
        }
    }
}
