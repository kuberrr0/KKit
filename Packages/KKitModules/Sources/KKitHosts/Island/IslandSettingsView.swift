import KKitCore
import KKitUI
import SwiftUI

/// Settings › Island.
struct IslandSettingsView: View {
    @Setting(IslandSettings.enabled) private var enabled
    @Setting(IslandSettings.expandOnHover) private var expandOnHover
    @Setting(IslandSettings.hoverDelay) private var hoverDelay
    @Setting(IslandSettings.displays) private var displays
    @Setting(IslandSettings.showInFullScreen) private var showInFullScreen

    var body: some View {
        KKForm {
            KKSection {
                HStack(spacing: KKSpacing.m) {
                    KKFeatureIcon("capsule.fill", size: 36, tint: .black)
                    VStack(alignment: .leading, spacing: KKSpacing.xxs) {
                        Text("Island")
                            .font(.title3.weight(.semibold))
                        Text("Live activities, HUDs and pages around the notch.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle(String(localized: "Show the Island"), isOn: $enabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }

            KKSection(
                String(localized: "Behaviour"),
                footer: String(localized: "Click an activity to open its page. Swipe sideways on the expanded Island to switch pages. With Volume on, scroll over the Island to change the volume (hold ⌥ for fine steps).")
            ) {
                Toggle(String(localized: "Expand when the pointer rests on it"), isOn: $expandOnHover)
                Picker(String(localized: "Hover delay"), selection: $hoverDelay) {
                    Text("Short (0.1 s)").tag(0.1)
                    Text("Normal (0.3 s)").tag(0.3)
                    Text("Long (0.6 s)").tag(0.6)
                    Text("Very long (1 s)").tag(1.0)
                }
                .disabled(!expandOnHover)
                Toggle(String(localized: "Show in full-screen apps"), isOn: $showInFullScreen)
            }

            KKSection(
                String(localized: "Displays"),
                footer: String(localized: "On displays without a notch the Island is a pill that appears only when there's something to show.")
            ) {
                Picker(String(localized: "Show on"), selection: $displays) {
                    Text("Built-in display").tag(IslandDisplays.builtIn)
                    Text("Main display").tag(IslandDisplays.main)
                    Text("All displays").tag(IslandDisplays.all)
                }
            }
        }
    }
}
