import KKitCore
import KKitUI
import SwiftUI

/// Settings › Quick Toggles: which tiles appear in the menu, in order.
struct TogglesSettingsView: View {
    @Setting(ToggleSettings.tiles) private var tiles

    var body: some View {
        Group {
            KKSection(
                String(localized: "In the menu"),
                footer: String(localized: "Every toggle is also a command: find it in the Floating Bar or give it a shortcut below.")
            ) {
                if tiles.isEmpty {
                    Text("No toggles in the menu.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(tiles.enumerated()), id: \.element) { index, toggle in
                    HStack {
                        Image(systemName: toggle.symbol)
                            .frame(width: 20)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(toggle.title)
                            if let note = toggle.note {
                                Text(note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
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
                        .disabled(index == tiles.count - 1)
                        .accessibilityLabel(Text("Move down"))
                        Button {
                            tiles.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .accessibilityLabel(Text("Remove \(toggle.title)"))
                    }
                    .buttonStyle(.borderless)
                }
                let addable = SystemToggle.allCases.filter { !tiles.contains($0) }
                Menu(String(localized: "Add Toggle")) {
                    ForEach(addable) { toggle in
                        Button {
                            tiles.append(toggle)
                        } label: {
                            Label(toggle.title, systemImage: toggle.symbol)
                        }
                    }
                }
                .disabled(addable.isEmpty)
                .fixedSize()
            }
        }
    }

    private func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard tiles.indices.contains(target) else { return }
        tiles.swapAt(index, target)
    }
}
