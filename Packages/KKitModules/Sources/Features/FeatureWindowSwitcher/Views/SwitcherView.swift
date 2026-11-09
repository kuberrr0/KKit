import AppKit
import KKitUI
import SwiftUI

/// The switcher panel: a grid of window previews (or app icons), the selected one
/// highlighted. Hovering selects, clicking switches.
struct SwitcherView: View {
    let model: SwitcherModel
    let onHover: @MainActor (SwitcherItem.ID) -> Void
    let onClick: @MainActor (SwitcherItem.ID) -> Void

    var body: some View {
        let layout = model.layout
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.fixed(layout.tileSize.width), spacing: SwitcherLayout.spacing),
                        count: max(layout.columns, 1)
                    ),
                    spacing: SwitcherLayout.spacing
                ) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                        SwitcherTile(
                            item: item,
                            isSelected: index == model.selectedIndex,
                            thumbnail: item.windowID.flatMap { model.thumbnails[$0] },
                            icon: model.icons[item.pid],
                            showsPreview: model.showsPreviews,
                            layout: layout
                        )
                        .id(item.id)
                        .onHover { inside in
                            if inside {
                                onHover(item.id)
                            }
                        }
                        .onTapGesture {
                            onClick(item.id)
                        }
                    }
                }
                .padding(SwitcherLayout.padding)
            }
            .scrollDisabled(layout.rows <= layout.visibleRows)
            .onChange(of: model.selectedIndex) { _, _ in
                if let id = model.selected?.id {
                    proxy.scrollTo(id)
                }
            }
        }
        .overlay {
            if model.items.isEmpty {
                Text("No windows")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: layout.panelSize.width, height: layout.panelSize.height)
        .background(KKVisualEffect(material: .hudWindow))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Window switcher"))
    }
}

/// One window or app.
struct SwitcherTile: View {
    let item: SwitcherItem
    let isSelected: Bool
    let thumbnail: CGImage?
    let icon: NSImage?
    let showsPreview: Bool
    let layout: SwitcherLayout

    private var isTucked: Bool { item.isMinimized || item.isAppHidden }

    var body: some View {
        VStack(spacing: 4) {
            preview
                .frame(width: layout.thumbnailSize.width, height: layout.thumbnailSize.height)
            HStack(spacing: 4) {
                if showsPreview, let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                }
                if let badge {
                    Image(systemName: badge)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Text(item.displayTitle)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity)
            .frame(height: SwitcherLayout.titleHeight - 4)
        }
        .padding(SwitcherLayout.tileInset)
        .frame(width: layout.tileSize.width, height: layout.tileSize.height)
        .background(
            RoundedRectangle(cornerRadius: KKRadius.row, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.28) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: KKRadius.row, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .help(item.title.isEmpty ? item.appName : "\(item.appName) — \(item.title)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(item.title.isEmpty ? item.appName : "\(item.appName), \(item.title)"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var preview: some View {
        if showsPreview, let thumbnail {
            Image(decorative: thumbnail, scale: 1)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                .opacity(isTucked ? 0.6 : 1)
        } else {
            let side = min(SwitcherLayout.iconSize, layout.thumbnailSize.height * 0.8)
            Group {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                } else {
                    Image(systemName: "macwindow")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: side, height: side)
            .opacity(isTucked ? 0.6 : 1)
        }
    }

    private var badge: String? {
        if item.isMinimized { return "minus.circle" }
        if item.isAppHidden { return "eye.slash" }
        return nil
    }
}
