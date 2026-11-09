import KKitCore
import KKitServicesAPI
import KKitUI
import SwiftUI

/// The volume row in the KKit menu: mute button, slider, and output/input pickers.
struct VolumeMenuSection: View {
    let controller: VolumeController

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
                String(localized: "Island HUD"),
                footer: String(localized: "The volume keys still show macOS's own HUD; KKit takes them over in a later update.")
            ) {
                Toggle(String(localized: "Show a HUD for changes made with KKit"), isOn: $showHUD)
                Toggle(String(localized: "Also for the volume keys and Control Center"), isOn: $hudForSystemChanges)
            }
            KKSection(String(localized: "Microphone")) {
                Toggle(String(localized: "Play a sound on mute and unmute"), isOn: $soundOnMicMute)
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
