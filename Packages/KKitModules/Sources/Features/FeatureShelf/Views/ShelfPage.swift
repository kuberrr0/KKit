import AppKit
import KKitServicesAPI
import KKitUI
import SwiftUI

/// What the Shelf page asks the feature to do that needs more than the controller.
struct ShelfPageActions {
    var rename: @MainActor (ShelfItem) -> Void
    var sendToNote: (@MainActor (ShelfItem) -> Void)?
}

/// The Shelf in the expanded Island: tiles you drag out, with a menu of actions each.
struct ShelfPage: View {
    let controller: ShelfController
    let actions: ShelfPageActions

    var body: some View {
        VStack(alignment: .leading, spacing: KKSpacing.s) {
            HStack {
                Text(controller.items.isEmpty ? String(localized: "Shelf") : String(localized: "Shelf · \(controller.items.count)"))
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                if !controller.items.isEmpty {
                    if controller.pdfs.count >= 2 {
                        Button(String(localized: "Merge PDFs")) {
                            Task { await controller.mergePDFs() }
                        }
                    }
                    Button {
                        controller.airDrop(controller.items)
                    } label: {
                        Label(String(localized: "AirDrop All"), systemImage: "airplayaudio")
                    }
                    Button(String(localized: "Clear")) {
                        controller.clear()
                    }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            if controller.items.isEmpty {
                Text("Drag files, images, links or text to the notch to keep them here for later.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: KKSpacing.s) {
                        ForEach(controller.items.reversed()) { item in
                            ShelfTile(item: item, controller: controller, actions: actions)
                        }
                    }
                }
            }
        }
    }
}

struct ShelfTile: View {
    let item: ShelfItem
    let controller: ShelfController
    let actions: ShelfPageActions

    @State private var hovering = false

    var body: some View {
        VStack(spacing: KKSpacing.xs) {
            preview
                .frame(width: 64, height: 52)
            Text(item.title)
                .font(.caption2)
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 72)
        }
        .padding(KKSpacing.xs)
        .background(.white.opacity(hovering ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: KKRadius.control))
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button {
                    controller.remove(item)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.6))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
                .accessibilityLabel(Text("Remove from Shelf"))
            }
        }
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { controller.open(item) }
        .onDrag { ShelfController.provider(for: item) }
        .contextMenu { ShelfItemMenu(item: item, controller: controller, actions: actions) }
        .help(item.subtitle ?? item.title)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(item.title))
    }

    @ViewBuilder private var preview: some View {
        switch item.content {
        case .file(let url):
            KKThumbnail(url: url, maxPixelSize: 160)
        case .text(let text):
            Text(text)
                .font(.system(size: 8))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(KKSpacing.xs)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
        case .link:
            Image(systemName: "link")
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

/// The right-click menu on a Shelf tile.
struct ShelfItemMenu: View {
    let item: ShelfItem
    let controller: ShelfController
    let actions: ShelfPageActions

    var body: some View {
        if !item.isText {
            Button(String(localized: "Open")) { controller.open(item) }
        }
        if item.fileURL != nil {
            let apps = controller.apps(for: item)
            if !apps.isEmpty {
                Menu(String(localized: "Open With")) {
                    ForEach(apps, id: \.self) { app in
                        Button(FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")) {
                            controller.open(item, with: app)
                        }
                    }
                }
            }
            Button(String(localized: "Show in Finder")) { controller.reveal([item]) }
        }
        Divider()
        Button(String(localized: "Copy")) { controller.copy([item]) }
        if item.fileURL != nil {
            Button(String(localized: "Copy Path")) { controller.copyPath(item) }
        }
        Button(String(localized: "AirDrop")) { controller.airDrop([item]) }
        if let url = item.fileURL {
            ShareLink(item: url) { Text("Share…") }
        } else if case .link(let url) = item.content {
            ShareLink(item: url) { Text("Share…") }
        } else if let text = item.plainText {
            ShareLink(item: text) { Text("Share…") }
        }
        if let sendToNote = actions.sendToNote, item.fileURL == nil {
            Button(String(localized: "Send to Note")) { sendToNote(item) }
        }
        if item.fileURL != nil {
            Divider()
            Button(String(localized: "Rename…")) { actions.rename(item) }
            Button(String(localized: "Compress")) {
                Task { await controller.compress(item) }
            }
            if item.isImage {
                Menu(String(localized: "Convert Image")) {
                    ForEach(ShelfImageFormat.allCases) { format in
                        Button(String(localized: "To \(format.title)")) {
                            Task { await controller.convert(item, to: format) }
                        }
                    }
                    Divider()
                    Button(String(localized: "Half Size")) {
                        Task { await controller.convert(item, to: Self.sameFormat(as: item), halfSize: true) }
                    }
                }
            }
            if item.isPDF, controller.pdfs.count >= 2 {
                Button(String(localized: "Merge PDFs on the Shelf")) {
                    Task { await controller.mergePDFs() }
                }
            }
        }
        Divider()
        Button(String(localized: "Remove from Shelf"), role: .destructive) { controller.remove(item) }
    }

    /// Resizing keeps the format when it's one ImageIO can write.
    static func sameFormat(as item: ShelfItem) -> ShelfImageFormat {
        switch item.fileURL?.pathExtension.lowercased() ?? "" {
        case "jpg", "jpeg": .jpeg
        case "heic", "heif": .heic
        default: .png
        }
    }
}

/// A small panel to rename a file on the Shelf.
struct RenameView: View {
    let original: String
    let rename: @MainActor (String) -> String?
    let cancel: @MainActor () -> Void

    @State private var name: String
    @State private var error: String?

    init(original: String, rename: @escaping @MainActor (String) -> String?, cancel: @escaping @MainActor () -> Void) {
        self.original = original
        self.rename = rename
        self.cancel = cancel
        _name = State(initialValue: original)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KKSpacing.s) {
            Text("Rename")
                .font(.headline)
            TextField(String(localized: "Name"), text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button(String(localized: "Cancel"), action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Rename"), action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(KKSpacing.l)
        .frame(width: 340)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: KKRadius.panel))
    }

    private func submit() {
        error = rename(name)
    }
}
