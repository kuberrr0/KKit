import KKitCore
import KKitServicesAPI
import KKitUI
import SwiftUI
import UniformTypeIdentifiers

/// Settings › Keyboard: the Hyper key, key bindings and leader sequences.
struct KeyboardSettingsView: View {
    let controller: KeyboardController

    @Setting(KeyboardSettings.hyperEnabled) private var hyperEnabled
    @Setting(KeyboardSettings.capsLockTap) private var capsLockTap
    @Setting(KeyboardSettings.cheatSheetEnabled) private var cheatSheetEnabled
    @Setting(KeyboardSettings.cheatSheetDelay) private var cheatSheetDelay
    @Setting(KeyboardSettings.bindings) private var bindings
    @Setting(KeyboardSettings.leaderEnabled) private var leaderEnabled
    @Setting(KeyboardSettings.leaderKey) private var leaderKey
    @Setting(KeyboardSettings.leaderTimeout) private var leaderTimeout
    @Setting(KeyboardSettings.sequences) private var sequences

    var body: some View {
        Group {
            InputStatusSection(status: controller.inputStatus, requestAccess: { controller.requestAccessibility() })
            KKSection(
                String(localized: "Hyper key"),
                footer: String(localized: "Caps Lock becomes ⌃⌥⇧⌘ while you hold it. KKit maps it with hidutil for this login session and gives Caps Lock back when the feature is turned off.")
            ) {
                Toggle(String(localized: "Use Caps Lock as the Hyper key"), isOn: $hyperEnabled)
                Picker(String(localized: "Tapping Caps Lock alone sends"), selection: $capsLockTap) {
                    ForEach(CapsLockTap.allCases, id: \.self) { tap in
                        Text(tap.title).tag(tap)
                    }
                }
                .disabled(!hyperEnabled)
                Toggle(String(localized: "Hold Hyper to show a cheat sheet"), isOn: $cheatSheetEnabled)
                    .disabled(!hyperEnabled)
                LabeledContent(String(localized: "Show it after")) {
                    Stepper(value: $cheatSheetDelay, in: 0.5...3, step: 0.25) {
                        Text("\(cheatSheetDelay, format: .number.precision(.fractionLength(2))) s")
                            .monospacedDigit()
                    }
                }
                .disabled(!hyperEnabled || !cheatSheetEnabled)
            }
            KKSection(
                String(localized: "Key bindings"),
                footer: String(localized: "Pressing an app's key again while it's in front hides it or cycles its windows. Commands can also get Hyper shortcuts in Settings › Shortcuts.")
            ) {
                ForEach($bindings) { $binding in
                    KeyBindingRow(binding: $binding, commands: controller.commandList) {
                        bindings.removeAll { $0.id == binding.id }
                    }
                }
                Button(String(localized: "Add Binding")) {
                    bindings.append(KeyBinding(trigger: nil, action: .openApp(path: "")))
                }
                if let conflict = duplicateTrigger {
                    Text("\(KKKeyNames.string(for: conflict)) is used more than once; only the first binding runs.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            KKSection(
                String(localized: "Leader sequences"),
                footer: String(localized: "Press the leader key, then type a sequence: Hyper Space, N, D. ⎋ cancels.")
            ) {
                Toggle(String(localized: "Use leader sequences"), isOn: $leaderEnabled)
                LabeledContent(String(localized: "Leader key")) {
                    KKKeyRecorder(shortcut: $leaderKey, requiresModifier: true)
                }
                .disabled(!leaderEnabled)
                LabeledContent(String(localized: "Wait for the next key")) {
                    Stepper(value: $leaderTimeout, in: 1...5, step: 0.5) {
                        Text("\(leaderTimeout, format: .number.precision(.fractionLength(1))) s")
                            .monospacedDigit()
                    }
                }
                .disabled(!leaderEnabled)
                ForEach($sequences) { $sequence in
                    LeaderSequenceRow(sequence: $sequence, commands: controller.commandList) {
                        sequences.removeAll { $0.id == sequence.id }
                    }
                }
                .disabled(!leaderEnabled)
                Button(String(localized: "Add Sequence")) {
                    sequences.append(LeaderSequence(keys: "", title: "", action: .runCommand(CommandID(""), value: nil)))
                }
                .disabled(!leaderEnabled)
            }
        }
    }

    private var duplicateTrigger: Shortcut? {
        var seen: Set<Shortcut> = []
        for trigger in bindings.compactMap(\.trigger) {
            if !seen.insert(trigger).inserted {
                return trigger
            }
        }
        return nil
    }
}

/// Shown when the tap isn't running.
struct InputStatusSection: View {
    let status: InputTapStatus
    let requestAccess: @MainActor () -> Void

    var body: some View {
        switch status {
        case .needsPermission:
            KKSection {
                HStack {
                    Label(String(localized: "KKit needs Accessibility to see key presses."), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button(String(localized: "Allow…")) { requestAccess() }
                }
            }
        case .failed(let message):
            KKSection {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        case .idle, .running:
            EmptyView()
        }
    }
}

struct KeyBindingRow: View {
    @Binding var binding: KeyBinding
    let commands: [CommandSummary]
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: KKSpacing.s) {
            HStack {
                KKKeyRecorder(shortcut: $binding.trigger, requiresModifier: true)
                Spacer()
                Button(role: .destructive, action: remove) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Remove binding"))
            }
            KeyActionEditor(action: $binding.action, commands: commands)
            if binding.action.kind == .openApp {
                Picker(String(localized: "When the app is already in front"), selection: $binding.secondPress) {
                    ForEach(SecondPress.allCases, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                }
            }
        }
        .padding(.vertical, KKSpacing.xs)
    }
}

struct LeaderSequenceRow: View {
    @Binding var sequence: LeaderSequence
    let commands: [CommandSummary]
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: KKSpacing.s) {
            HStack {
                TextField(String(localized: "Keys"), text: $sequence.keys, prompt: Text("nd"))
                    .font(.body.monospaced())
                    .frame(width: 80)
                TextField(String(localized: "Name"), text: $sequence.title, prompt: Text("New daily note"))
                Button(role: .destructive, action: remove) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Remove sequence"))
            }
            KeyActionEditor(action: $sequence.action, commands: commands)
        }
        .padding(.vertical, KKSpacing.xs)
    }
}

/// Picks what a binding or sequence does.
struct KeyActionEditor: View {
    @Binding var action: KeyAction
    let commands: [CommandSummary]
    @State private var choosingApp = false
    @State private var choosingFile = false

    var body: some View {
        Picker(String(localized: "Action"), selection: kind) {
            ForEach(KeyAction.Kind.allCases) { kind in
                Label(kind.title, systemImage: kind.symbol).tag(kind)
            }
        }
        switch action {
        case .openApp(let path):
            HStack {
                Text(path.isEmpty ? String(localized: "No app chosen") : action.summary())
                    .foregroundStyle(path.isEmpty ? .secondary : .primary)
                Spacer()
                Button(String(localized: "Choose App…")) { choosingApp = true }
            }
            .fileImporter(isPresented: $choosingApp, allowedContentTypes: [.application]) { result in
                if case .success(let url) = result {
                    action = .openApp(path: url.path)
                }
            }
        case .openURL(let text):
            TextField(String(localized: "Link"), text: Binding(get: { text }, set: { action = .openURL($0) }), prompt: Text("github.com"))
        case .openFile(let path):
            HStack {
                Text(path.isEmpty ? String(localized: "Nothing chosen") : path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(path.isEmpty ? .secondary : .primary)
                Spacer()
                Button(String(localized: "Choose…")) { choosingFile = true }
            }
            .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.item, .folder]) { result in
                if case .success(let url) = result {
                    action = .openFile(path: url.path)
                }
            }
        case .runCommand(let id, let value):
            Picker(String(localized: "Command"), selection: Binding(get: { id }, set: { action = .runCommand($0, value: value) })) {
                Text("Choose…").tag(CommandID(""))
                ForEach(commands) { command in
                    Text(command.title).tag(command.id)
                }
            }
            if commands.first(where: { $0.id == id })?.takesValue == true {
                TextField(
                    String(localized: "Value"),
                    text: Binding(get: { value ?? "" }, set: { action = .runCommand(id, value: $0.isEmpty ? nil : $0) }),
                    prompt: Text("25m, 30, AirPods…")
                )
            }
        case .runShortcut(let name):
            TextField(String(localized: "Shortcut name"), text: Binding(get: { name }, set: { action = .runShortcut(name: $0) }))
        case .shellScript(let script):
            TextField(String(localized: "Script"), text: Binding(get: { script }, set: { action = .shellScript($0) }), prompt: Text("open -a Terminal ~"))
                .font(.body.monospaced())
        }
    }

    private var kind: Binding<KeyAction.Kind> {
        Binding(
            get: { action.kind },
            set: { newKind in
                guard newKind != action.kind else { return }
                action = newKind.blank
            }
        )
    }
}
