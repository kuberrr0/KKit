import AppKit
import KKitCore
import KKitServicesAPI
import KKitUI
import SwiftUI

/// The preview pane for one item: the text, image, files or colour, and where it came
/// from.
struct ClipboardPreview: View {
    let item: ClipboardItem
    let imageURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: KKSpacing.s) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            details
        }
        .padding(KKSpacing.m)
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .image:
            KKThumbnail(url: imageURL, maxPixelSize: 900)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .files:
            ScrollView {
                VStack(alignment: .leading, spacing: KKSpacing.xs) {
                    ForEach(item.fileURLs, id: \.self) { url in
                        HStack(spacing: KKSpacing.s) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                .resizable()
                                .frame(width: 20, height: 20)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(url.lastPathComponent)
                                    .lineLimit(1)
                                Text(url.deletingLastPathComponent().path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                }
            }
        case .color:
            if let color = item.color {
                VStack(alignment: .leading, spacing: KKSpacing.s) {
                    KKSwatch(color.swiftUI, size: 72)
                    Text(color.hex)
                        .font(.system(.title3, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        case .text, .richText, .link:
            ScrollView {
                Text(item.text.count > 6000 ? String(item.text.prefix(6000)) + "…" : item.text)
                    .font(item.kind == .link ? .body : .system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let app = item.sourceAppName {
                detail(String(localized: "From"), app)
            }
            detail(String(localized: "Copied"), item.lastUsedAt.formatted(date: .abbreviated, time: .shortened))
            switch item.kind {
            case .text, .richText:
                detail(String(localized: "Size"), String(localized: "\(item.text.count) characters, \(max(item.lineCount, 1)) lines"))
            case .files:
                detail(String(localized: "Files"), "\(item.fileURLs.count)")
            default:
                EmptyView()
            }
            if item.useCount > 1 {
                detail(String(localized: "Used"), String(localized: "\(item.useCount) times"))
            }
        }
        .font(.caption)
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            Text(value)
                .lineLimit(1)
        }
    }
}

/// An item's icon in lists: a thumbnail, file icon, swatch or symbol.
struct ClipboardItemIcon: View {
    let item: ClipboardItem
    let imageURL: URL?
    var size: CGFloat = 22

    var body: some View {
        Group {
            switch item.kind {
            case .image:
                KKThumbnail(url: imageURL, maxPixelSize: size * 4, contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            case .files:
                if let url = item.fileURLs.first {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                } else {
                    Image(systemName: item.kind.symbol)
                }
            case .color:
                KKSwatch(item.color?.swiftUI ?? .gray, size: size * 0.8)
            default:
                Image(systemName: item.kind.symbol)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

extension RGBAColor {
    var swiftUI: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
