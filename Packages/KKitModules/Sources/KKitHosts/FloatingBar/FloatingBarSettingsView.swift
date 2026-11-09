import KKitCore
import KKitServicesAPI
import KKitUI
import SwiftUI

/// Settings › Floating Bar.
struct FloatingBarSettingsView: View {
    let dependencies: HostDependencies
    let host: FloatingBarHost

    @Setting(FloatingBarSettings.placement) private var placement
    @Setting(FloatingBarSettings.rememberQuery) private var rememberQuery
    @Setting(FloatingBarSettings.showRecents) private var showRecents

    var body: some View {
        KKForm {
            KKSection {
                HStack(spacing: KKSpacing.m) {
                    KKFeatureIcon("magnifyingglass", size: 36)
                    VStack(alignment: .leading, spacing: KKSpacing.xxs) {
                        Text("Floating Bar")
                            .font(.title3.weight(.semibold))
                        Text("Search apps, files, commands, System Settings and the web from one hotkey.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                KKRow(String(localized: "Open the Floating Bar"), symbol: "keyboard") {
                    dependencies.hotkeys.recorder(for: FloatingBarCommandID.toggle)
                }
            }

            KKSection(
                String(localized: "Behaviour"),
                footer: String(localized: "↵ runs the selected result, ⌘↵ runs it and keeps the bar open, ⌘K shows more actions, Tab shows a preview. Commands take a value after their name: “night 150”, “awake 2h”, “vol 30”.")
            ) {
                Picker(String(localized: "Open at"), selection: $placement) {
                    Text("Middle of the screen").tag(FloatingBarPlacement.center)
                    Text("Top of the screen").tag(FloatingBarPlacement.top)
                }
                Toggle(String(localized: "Keep the last search for 30 seconds"), isOn: $rememberQuery)
                Toggle(String(localized: "Show recent results when nothing is typed"), isOn: $showRecents)
                Button(String(localized: "Clear Recent and Learned Results")) {
                    host.clearRecents()
                }
            }

            KKSection(
                String(localized: "Sources"),
                footer: String(localized: "Type a prefix to search only that source. Sources come from features; turn a feature off to remove its sources.")
            ) {
                ForEach(host.sourceInfos()) { source in
                    KKRow(source.name, subtitle: subtitle(for: source), symbol: source.symbol) {
                        if let prefix = source.prefix {
                            KKKeyCap(prefix.trimmingCharacters(in: .whitespaces))
                        }
                        if !source.isMode {
                            Toggle(String(localized: "On"), isOn: enabled(source.id))
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.small)
                        }
                    }
                }
            }

            KKSection(String(localized: "Favourites"), footer: String(localized: "Add favourites with ⌘K on any result.")) {
                if host.model.history.favourites.isEmpty {
                    Text("No favourites yet")
                        .foregroundStyle(.secondary)
                }
                ForEach(host.model.history.favourites) { favourite in
                    KKRow(favourite.title, subtitle: favourite.subtitle) {
                        Button(String(localized: "Remove")) {
                            host.removeFavourite(favourite.id)
                        }
                    }
                }
            }
        }
    }

    private func subtitle(for source: FloatingBarHost.SourceInfo) -> String {
        var parts = [source.owner]
        if source.isMode {
            parts.append(String(localized: "switches the bar to an editor"))
        } else if !source.inRootSearch {
            parts.append(String(localized: "only with its prefix"))
        }
        return parts.joined(separator: " · ")
    }

    private func enabled(_ key: String) -> Binding<Bool> {
        let host = self.host
        return Binding(
            get: { host.isProviderEnabled(key) },
            set: { host.setProvider(key, enabled: $0) }
        )
    }
}
