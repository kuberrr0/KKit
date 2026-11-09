import AppKit
import KKitServicesAPI
import SwiftUI

/// "Hide desktop icons" without restarting Finder: a click-through panel just above the
/// desktop icons on each screen, showing that screen's wallpaper.
@MainActor
final class DesktopCover {
    private let overlays: any OverlayService
    private let actions: any SystemActionsService
    private var panels: [any OverlayHandle] = []

    private(set) var isHidingIcons = false

    init(overlays: any OverlayService, actions: any SystemActionsService) {
        self.overlays = overlays
        self.actions = actions
    }

    func setHidingIcons(_ hide: Bool) {
        isHidingIcons = hide
        rebuild()
    }

    /// Screens or wallpapers changed.
    func rebuild() {
        panels.forEach { $0.close() }
        panels = []
        guard isHidingIcons else { return }
        for screen in overlays.screens {
            let configuration = OverlayConfiguration(
                level: .aboveDesktopIcons,
                screen: .display(screen.id),
                placement: .fullScreen,
                ignoresMouseEvents: true,
                hasShadow: false
            )
            let image = actions.desktopImageURL(forDisplay: screen.id).flatMap { NSImage(contentsOf: $0) }
            let panel = overlays.makePanel(configuration, content: AnyView(DesktopCoverView(image: image)))
            panel.show()
            panels.append(panel)
        }
    }

    func tearDown() {
        isHidingIcons = false
        rebuild()
    }
}

struct DesktopCoverView: View {
    let image: NSImage?

    var body: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
                .accessibilityHidden(true)
        } else {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()
                .accessibilityHidden(true)
        }
    }
}
