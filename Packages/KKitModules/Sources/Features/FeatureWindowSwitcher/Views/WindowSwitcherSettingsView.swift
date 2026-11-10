import KKitCore
import KKitUI
import SwiftUI

/// Settings › Window Switcher.
struct WindowSwitcherSettingsView: View {
    let screenRecordingGranted: Bool
    let requestScreenRecording: @MainActor () -> Void

    @Setting(WindowSwitcherSettings.takeOverShortcut) private var takeOverShortcut
    @Setting(WindowSwitcherSettings.modifier) private var modifier
    @Setting(WindowSwitcherSettings.includeMinimized) private var includeMinimized
    @Setting(WindowSwitcherSettings.includeHiddenApps) private var includeHiddenApps
    @Setting(WindowSwitcherSettings.includeAppsWithoutWindows) private var includeAppsWithoutWindows
    @Setting(WindowSwitcherSettings.showPreviews) private var showPreviews
    @Setting(WindowSwitcherSettings.previewSize) private var previewSize

    var body: some View {
        Group {
            KKSection(
                String(localized: "Shortcut"),
                footer: String(localized: "Hold the modifier and press Tab to go forward, ⇧Tab to go back; let go to switch. While it's open: arrows move, ↩ switches, ⎋ cancels, W closes the window, Q quits the app, H hides it. The Switch Windows command opens it without holding a key.")
            ) {
                Toggle(String(localized: "Open with a modifier + Tab"), isOn: $takeOverShortcut)
                Picker(String(localized: "Shortcut"), selection: $modifier) {
                    ForEach(SwitcherModifier.allCases, id: \.self) { modifier in
                        Text(modifier.title).tag(modifier)
                    }
                }
                .disabled(!takeOverShortcut)
            }
            KKSection(
                String(localized: "Windows"),
                footer: String(localized: "Windows on the current Space come first, most recent first. Windows on other Spaces aren't listed; their apps show as app icons.")
            ) {
                Toggle(String(localized: "Include minimised windows"), isOn: $includeMinimized)
                Toggle(String(localized: "Include windows of hidden apps"), isOn: $includeHiddenApps)
                Toggle(String(localized: "Include apps with no open windows"), isOn: $includeAppsWithoutWindows)
            }
            KKSection(
                String(localized: "Previews"),
                footer: screenRecordingGranted
                    ? nil
                    : String(localized: "Previews need Screen Recording permission. Without it the switcher shows app icons.")
            ) {
                Toggle(String(localized: "Show live window previews"), isOn: $showPreviews)
                Picker(String(localized: "Preview size"), selection: $previewSize) {
                    ForEach(PreviewSize.allCases, id: \.self) { size in
                        Text(size.title).tag(size)
                    }
                }
                .disabled(!showPreviews)
                if showPreviews, !screenRecordingGranted {
                    Button(String(localized: "Allow Screen Recording…")) { requestScreenRecording() }
                }
            }
        }
    }
}
