import AppKit
import KKitServicesAPI
import KKitUI
import SwiftUI

/// The bar under the menu bar with the icons that aren't in it: behind the notch,
/// hidden and always hidden. Clicking one opens its menu.
struct DropDownBarView: View {
    let controller: MenuBarManagerController

    static let cell = CGSize(width: 30, height: 26)
    static let padding: CGFloat = 6
    static let separatorWidth: CGFloat = 9
    static let messageSize = CGSize(width: 320, height: 54)
    static let maximumWidth: CGFloat = 900

    /// The panel's size for groups of `counts` icons.
    static func size(for counts: [Int], hasMessage: Bool) -> CGSize {
        if hasMessage { return messageSize }
        let icons = CGFloat(counts.reduce(0, +))
        let separators = CGFloat(max(counts.count - 1, 0))
        let width = padding * 2 + icons * cell.width + separators * separatorWidth
        return CGSize(width: min(max(width, 60), maximumWidth), height: cell.height + padding * 2)
    }

    var body: some View {
        content
            .padding(Self.padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(KKVisualEffect(material: .menu, cornerRadius: 10))
            .onHover { controller.isPointerOnDropDown = $0 }
    }

    @ViewBuilder
    private var content: some View {
        let groups = controller.dropDownGroups
        if !controller.hasAccessibility {
            HStack(spacing: KKSpacing.s) {
                Image(systemName: "accessibility")
                    .foregroundStyle(.secondary)
                Text("Allow Accessibility to list hidden icons.")
                    .font(.callout)
                Spacer(minLength: 0)
                Button(String(localized: "Allow…")) { controller.requestAccessibility() }
                    .controlSize(.small)
            }
            .padding(.horizontal, KKSpacing.xs)
        } else if groups.isEmpty {
            Text("No hidden icons. ⌘-drag icons left of ‹ to hide them.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                        if index > 0 {
                            Divider()
                                .frame(height: 16)
                                .padding(.horizontal, (Self.separatorWidth - 1) / 2)
                        }
                        ForEach(group) { icon in
                            Button {
                                Task { try? await controller.open(icon) }
                            } label: {
                                MenuBarIconImage(icon: icon, image: controller.images[icon.id])
                                    .frame(width: Self.cell.width, height: Self.cell.height)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(DropDownButtonStyle())
                            .help(Text(icon.detail.map { "\(icon.displayName) — \($0)" } ?? icon.displayName))
                            .accessibilityLabel(Text(icon.displayName))
                        }
                    }
                }
            }
        }
    }
}

/// A rounded highlight under the pointer, like the menu bar's own.
struct DropDownButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverHighlight(isPressed: configuration.isPressed) {
            configuration.label
        }
    }
}

struct HoverHighlight<Content: View>: View {
    let isPressed: Bool
    @ViewBuilder let content: Content
    @State private var isHovered = false

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.primary.opacity(isPressed ? 0.2 : (isHovered ? 0.1 : 0)))
            )
            .onHover { isHovered = $0 }
    }
}

/// A picture of the icon if KKit has one, the app's icon otherwise.
struct MenuBarIconImage: View {
    let icon: MenuBarIcon
    let image: CapturedImage?

    var body: some View {
        if let image {
            Image(decorative: image.image, scale: image.scale)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 28, maxHeight: 22)
        } else if let url = icon.appURL {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 16, height: 16)
        } else {
            Image(systemName: "menubar.rectangle")
                .foregroundStyle(.secondary)
        }
    }
}
