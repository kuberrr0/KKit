import KKitCore
import KKitUI
import SwiftUI

/// The brightness row in the KKit menu.
struct BrightnessMenuSection: View {
    let controller: BrightnessController

    var body: some View {
        HStack(spacing: KKSpacing.s) {
            Image(systemName: "sun.max.fill")
                .symbolRenderingMode(.hierarchical)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            if let level = controller.level {
                Slider(
                    value: Binding(
                        get: { level },
                        set: { try? controller.set($0, showHUD: false) }
                    ),
                    in: 0...1
                )
                .labelsHidden()
                .accessibilityLabel(Text("Brightness"))
                .accessibilityValue(Text(KKFormat.percent(level)))
                Text(KKFormat.percent(level))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 40, alignment: .trailing)
            } else {
                Text("Brightness can't be changed here")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .onAppear { controller.refresh() }
    }
}

/// Settings › Brightness.
struct BrightnessSettingsView: View {
    let controller: BrightnessController
    let inputTapRunning: @MainActor () -> Bool
    let requestAccess: @MainActor () -> Void

    @Setting(BrightnessSettings.takeOverKeys) private var takeOverKeys
    @Setting(BrightnessSettings.step) private var step
    @Setting(BrightnessSettings.showHUD) private var showHUD

    var body: some View {
        Group {
            KKSection(
                String(localized: "Brightness keys"),
                footer: String(localized: "KKit changes the brightness in its own steps and shows the Island HUD instead of macOS's. ⇧⌥ with a brightness key gives quarter steps. Displays KKit can't control keep macOS's behaviour.")
            ) {
                Toggle(String(localized: "Use KKit for the brightness keys"), isOn: $takeOverKeys)
                if takeOverKeys, !inputTapRunning() {
                    HStack {
                        Text("KKit needs Accessibility to see the brightness keys.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Spacer()
                        Button(String(localized: "Allow…")) { requestAccess() }
                    }
                }
                Picker(String(localized: "Step size"), selection: $step) {
                    Text("1/32").tag(0.03125)
                    Text(String(localized: "1/16 (like macOS)")).tag(0.0625)
                    Text("10%").tag(0.1)
                }
                Toggle(String(localized: "Show a HUD for changes made with KKit commands"), isOn: $showHUD)
            }
            KKSection(String(localized: "Display")) {
                BrightnessMenuSection(controller: controller)
                if let name = controller.displayName {
                    Text(name).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
