import AppKit
import KKitCore
import KKitServicesAPI
import KKitUI
import SwiftUI
import UniformTypeIdentifiers

/// Settings › Window Management.
struct WindowsSettingsView: View {
    let controller: WindowsController
    let systemTilingOn: Bool
    let openDesktopSettings: @MainActor () -> Void

    @Setting(WindowsSettings.mouseEnabled) private var mouseEnabled
    @Setting(WindowsSettings.moveModifiers) private var moveModifiers
    @Setting(WindowsSettings.resizeTrigger) private var resizeTrigger
    @Setting(WindowsSettings.resizeFromNearestCorner) private var resizeFromNearestCorner
    @Setting(WindowsSettings.raiseOnDrag) private var raiseOnDrag
    @Setting(WindowsSettings.snapWhileModifierDragging) private var snapWhileModifierDragging
    @Setting(WindowsSettings.doubleClickToMaximize) private var doubleClickToMaximize
    @Setting(WindowsSettings.dragToSnap) private var dragToSnap
    @Setting(WindowsSettings.deferToSystemTiling) private var deferToSystemTiling
    @Setting(WindowsSettings.gap) private var gap
    @Setting(WindowsSettings.cycleSizes) private var cycleSizes
    @Setting(WindowsSettings.excludedApps) private var excludedApps

    @State private var choosingApp = false
    @State private var newLayoutName = ""
    @State private var layoutError: String?

    var body: some View {
        Group {
            KKSection(
                String(localized: "Snapping"),
                footer: String(localized: "These are the default keys. Change them in Settings › Shortcuts.")
            ) {
                SnapGrid()
                Toggle(String(localized: "Pressing a half again cycles ½, ⅓ and ⅔"), isOn: $cycleSizes)
                LabeledContent(String(localized: "Gap between windows")) {
                    Stepper(value: $gap, in: 0...40, step: 2) {
                        Text("\(Int(gap)) pt").monospacedDigit()
                    }
                }
            }
            KKSection(
                String(localized: "Drag to snap"),
                footer: systemTilingFooter
            ) {
                Toggle(String(localized: "Snap windows dragged to a screen edge or corner"), isOn: $dragToSnap)
                Toggle(String(localized: "Leave it to macOS while its own tiling is on"), isOn: $deferToSystemTiling)
                    .disabled(!dragToSnap)
                if systemTilingOn, dragToSnap {
                    Button(String(localized: "Open Desktop & Dock Settings…")) { openDesktopSettings() }
                }
            }
            KKSection(
                String(localized: "Modifier + mouse"),
                footer: String(localized: "Hold the modifiers and drag anywhere in a window to move it. Right-drag, or add ⇧, to resize.")
            ) {
                Toggle(String(localized: "Move and resize windows with a modifier"), isOn: $mouseEnabled)
                LabeledContent(String(localized: "Modifiers")) {
                    ModifierPicker(modifiers: $moveModifiers)
                }
                .disabled(!mouseEnabled)
                Picker(String(localized: "Resize with"), selection: $resizeTrigger) {
                    ForEach(ResizeTrigger.allCases, id: \.self) { trigger in
                        Text(trigger.title).tag(trigger)
                    }
                }
                .disabled(!mouseEnabled)
                Toggle(String(localized: "Resize from the nearest corner"), isOn: $resizeFromNearestCorner)
                    .disabled(!mouseEnabled)
                Toggle(String(localized: "Bring the window to the front"), isOn: $raiseOnDrag)
                    .disabled(!mouseEnabled)
                Toggle(String(localized: "Snap at edges while dragging this way too"), isOn: $snapWhileModifierDragging)
                    .disabled(!mouseEnabled)
                Toggle(String(localized: "Double-click to maximise or restore"), isOn: $doubleClickToMaximize)
                    .disabled(!mouseEnabled)
            }
            KKSection(
                String(localized: "Layouts"),
                footer: String(localized: "Restore one from the Floating Bar: type “Layout” and its name.")
            ) {
                ForEach(controller.layouts) { layout in
                    LayoutRow(layout: layout, controller: controller)
                }
                HStack {
                    TextField(String(localized: "Name"), text: $newLayoutName, prompt: Text("Coding"))
                    Button(String(localized: "Save Current Windows")) {
                        let name = newLayoutName
                        Task {
                            do {
                                try await controller.saveLayout(named: name)
                                newLayoutName = ""
                                layoutError = nil
                            } catch {
                                layoutError = error.localizedDescription
                            }
                        }
                    }
                }
                if let layoutError {
                    Text(layoutError).font(.caption).foregroundStyle(.orange)
                }
            }
            KKSection(
                String(localized: "Excluded apps"),
                footer: String(localized: "KKit never moves these apps' windows, by key or by mouse.")
            ) {
                ForEach(excludedApps, id: \.self) { bundleID in
                    HStack {
                        Text(Self.appName(for: bundleID))
                        Spacer()
                        Text(bundleID).font(.caption).foregroundStyle(.secondary)
                        Button {
                            excludedApps.removeAll { $0 == bundleID }
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text("Remove"))
                    }
                }
                Button(String(localized: "Add App…")) { choosingApp = true }
                    .fileImporter(isPresented: $choosingApp, allowedContentTypes: [.application]) { result in
                        if case .success(let url) = result, let id = Bundle(url: url)?.bundleIdentifier,
                           !excludedApps.contains(id) {
                            excludedApps.append(id)
                        }
                    }
            }
        }
    }

    private var systemTilingFooter: String {
        if systemTilingOn {
            String(localized: "macOS's own tiling (Desktop & Dock › Drag windows to screen edges to tile) is on. Turn it off there to use KKit's, or keep both by turning off “Leave it to macOS”.")
        } else {
            String(localized: "The top edge maximises, the sides take half, the corners a quarter.")
        }
    }

    static func appName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

/// The snap actions with their default keys.
private struct SnapGrid: View {
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: KKSpacing.s)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: KKSpacing.s) {
            ForEach(SnapAction.allCases, id: \.self) { action in
                HStack(spacing: KKSpacing.xs) {
                    Image(systemName: action.symbol)
                        .frame(width: 18)
                        .foregroundStyle(.secondary)
                    Text(action.title).lineLimit(1)
                    Spacer(minLength: 4)
                    if let shortcut = action.defaultShortcut {
                        Text(KKKeyNames.string(for: shortcut))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// ⌃ ⌥ ⇧ ⌘ toggles; at least one stays on.
private struct ModifierPicker: View {
    @Binding var modifiers: Shortcut.Modifiers

    private let options: [(Shortcut.Modifiers, String, String)] = [
        (.control, "⌃", String(localized: "Control")),
        (.option, "⌥", String(localized: "Option")),
        (.shift, "⇧", String(localized: "Shift")),
        (.command, "⌘", String(localized: "Command")),
    ]

    var body: some View {
        HStack(spacing: KKSpacing.xs) {
            ForEach(options, id: \.1) { option in
                Toggle(isOn: Binding(
                    get: { modifiers.contains(option.0) },
                    set: { on in
                        var next = modifiers
                        if on { next.insert(option.0) } else { next.remove(option.0) }
                        if !next.isEmpty { modifiers = next }
                    }
                )) {
                    Text(option.1).frame(minWidth: 18)
                }
                .toggleStyle(.button)
                .accessibilityLabel(Text(option.2))
            }
        }
    }
}

private struct LayoutRow: View {
    let layout: WindowLayout
    let controller: WindowsController
    @State private var name = ""

    var body: some View {
        HStack {
            TextField(String(localized: "Name"), text: $name)
                .textFieldStyle(.plain)
                .onSubmit {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        name = layout.name
                    } else {
                        controller.renameLayout(layout.id, to: trimmed)
                    }
                }
            Text("\(layout.entries.count) windows")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(String(localized: "Restore")) {
                let id = layout.id
                Task { try? await controller.restoreLayout(id: id) }
            }
            Button {
                controller.deleteLayout(layout.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Delete layout"))
        }
        .onAppear { name = layout.name }
    }
}
