import AppKit
import SwiftUI

/// A behind-window blur with rounded corners, for borderless panels (the Floating Bar).
/// SwiftUI materials only blur within a window, so panels use this instead.
public struct KKVisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let cornerRadius: CGFloat

    public init(material: NSVisualEffectView.Material = .popover, cornerRadius: CGFloat = KKRadius.panel) {
        self.material = material
        self.cornerRadius = cornerRadius
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = material
        view.maskImage = Self.maskImage(cornerRadius: cornerRadius)
        return view
    }

    public func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }

    /// A stretchable rounded rectangle, so the blur (and the window shadow) follow the
    /// panel's corners.
    static func maskImage(cornerRadius: CGFloat) -> NSImage {
        let edge = 2 * cornerRadius + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius)
        image.resizingMode = .stretch
        return image
    }
}

/// A key cap for footers and hints: "⌘K", "↵".
public struct KKKeyCap: View {
    let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, KKSpacing.xs + 1)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            )
            .accessibilityHidden(true)
    }
}
