import KKitUI
import SwiftUI

/// The leader sequence panel: what's typed so far and the keys that can follow.
struct LeaderView: View {
    let controller: KeyboardController

    var body: some View {
        VStack(alignment: .leading, spacing: KKSpacing.s) {
            HStack(spacing: KKSpacing.s) {
                Image(systemName: "text.cursor")
                    .foregroundStyle(.secondary)
                Text("Leader")
                    .font(.headline)
                Text(controller.leaderTyped ?? "")
                    .font(.headline.monospaced())
                    .foregroundStyle(Color.accentColor)
                Spacer()
                KKKeyCap("⎋")
            }
            Divider()
            ForEach(Array(controller.leaderOptions.prefix(8).enumerated()), id: \.offset) { _, option in
                HStack(spacing: KKSpacing.s) {
                    KKKeyCap(option.key.uppercased())
                    Text(option.title)
                        .lineLimit(1)
                    Spacer()
                }
            }
        }
        .padding(KKSpacing.l)
        .frame(width: 420, alignment: .topLeading)
        .background(KKVisualEffect(material: .hudWindow))
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Leader sequence"))
    }
}

/// Every Hyper binding, shown while Hyper is held for a moment.
struct CheatSheetView: View {
    let entries: [CheatSheetEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: KKSpacing.s) {
            HStack {
                Image(systemName: "keyboard")
                Text("Hyper Key")
                    .font(.headline)
            }
            Divider()
            if entries.isEmpty {
                Text("No Hyper bindings yet. Add some in Settings › Keyboard.")
                    .foregroundStyle(.secondary)
            }
            ForEach(entries) { entry in
                HStack(spacing: KKSpacing.s) {
                    Text(entry.keys)
                        .font(.body.monospaced())
                        .frame(width: 150, alignment: .leading)
                    Image(systemName: entry.symbol)
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    Text(entry.title)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
            }
        }
        .padding(KKSpacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(KKVisualEffect(material: .hudWindow))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Hyper key cheat sheet"))
    }
}
