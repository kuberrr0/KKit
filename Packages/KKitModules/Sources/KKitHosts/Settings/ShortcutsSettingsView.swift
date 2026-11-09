import KKitCore
import KKitServicesAPI
import KKitUI
import SwiftUI

/// Every command from KKit and the running features, with a shortcut recorder each.
struct ShortcutsSettingsView: View {
    let dependencies: HostDependencies
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            TextField(String(localized: "Search commands"), text: $query)
                .textFieldStyle(.roundedBorder)
                .padding([.horizontal, .top], KKSpacing.l)
            KKForm {
                if groups.isEmpty {
                    KKSection {
                        Text(query.isEmpty
                             ? String(localized: "No commands yet.")
                             : String(localized: "No commands match “\(query)”."))
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(groups, id: \.owner) { group in
                    KKSection(group.title) {
                        ForEach(group.commands) { command in
                            CommandShortcutRow(command: command, dependencies: dependencies)
                        }
                    }
                }
            }
        }
    }

    private struct CommandGroup {
        let owner: FeatureID
        let title: String
        let commands: [Command]
    }

    private var groups: [CommandGroup] {
        let matching = dependencies.commands.allCommands.filter { matches($0) }
        let owners = Set(matching.map(\.id.featureID)).sorted { title(for: $0) < title(for: $1) }
        return owners.map { owner in
            CommandGroup(owner: owner, title: title(for: owner), commands: matching.filter { $0.id.featureID == owner })
        }
    }

    private func title(for owner: FeatureID) -> String {
        owner == .app ? "KKit" : dependencies.features.manifest(for: owner)?.name ?? owner.rawValue
    }

    private func matches(_ command: Command) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return true }
        let haystack = [command.title, command.subtitle ?? "", command.id.rawValue] + command.keywords
        return haystack.contains { $0.localizedCaseInsensitiveContains(needle) }
    }
}

/// One command: title, conflict warning, recorder.
struct CommandShortcutRow: View {
    let command: Command
    let dependencies: HostDependencies

    var body: some View {
        KKRow(command.title, subtitle: conflictText, symbol: command.symbol) {
            dependencies.hotkeys.recorder(for: command.id)
        }
        .contextMenu {
            Button(String(localized: "Reset to Default")) {
                dependencies.hotkeys.resetShortcut(for: command.id)
            }
        }
    }

    private var conflictText: String? {
        let others = dependencies.hotkeys.conflicts(for: command.id)
            .map { dependencies.commands.command($0)?.title ?? $0.rawValue }
        guard !others.isEmpty else { return command.subtitle }
        return String(localized: "Same shortcut as \(others.formatted(.list(type: .and)))")
    }
}
