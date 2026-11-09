import KKitCore
import KKitUI
import SwiftUI

struct ShelfSettingsView: View {
    let controller: ShelfController

    @Setting(ShelfSettings.keepCopies) private var keepCopies
    @Setting(ShelfSettings.autoClear) private var autoClear
    @Setting(ShelfSettings.maxItems) private var maxItems
    @Setting(ShelfSettings.showAfterDrop) private var showAfterDrop

    var body: some View {
        KKSection(
            String(localized: "Shelf"),
            footer: keepCopies
                ? String(localized: "Dropped files are copied, so you can move or delete the originals. Copies are deleted when you remove them from the Shelf.")
                : String(localized: "The Shelf points to your files and never moves or deletes them. Images dragged from apps are kept as files of their own.")
        ) {
            Toggle(String(localized: "Keep a copy of dropped files"), isOn: $keepCopies)
            Picker(String(localized: "Clear items"), selection: $autoClear) {
                ForEach(ShelfAutoClear.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            Stepper(value: $maxItems, in: 5...200, step: 5) {
                LabeledContent(String(localized: "At most"), value: String(localized: "\(maxItems) items"))
            }
            Toggle(String(localized: "Open the Shelf after dropping on it"), isOn: $showAfterDrop)
            KKRow(String(localized: "\(controller.itemCount) items on the Shelf"), symbol: "tray") {
                Button(String(localized: "Clear Shelf"), role: .destructive) {
                    controller.clear()
                }
                .disabled(controller.items.isEmpty)
            }
        }
        .onChange(of: autoClear) {
            controller.removeExpired()
        }
    }
}
