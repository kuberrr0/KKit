import AppKit
import KKitCore
import KKitServicesAPI
import KKitUI
import SwiftUI

/// Creates KKit panels and reports display changes.
@MainActor
public final class AppKitOverlayService: OverlayService {
    private let events: EventBus
    private var observer: NSObjectProtocol?
    private let regionPicker = RegionPicker()

    public init(events: EventBus) {
        self.events = events
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.events.publish(.displaysChanged)
            }
        }
    }

    public func makePanel(_ configuration: OverlayConfiguration, content: AnyView) -> any OverlayHandle {
        PanelHandle(configuration: configuration, content: content)
    }

    public func pickRegion(_ options: RegionPickerOptions) async -> RegionSelection? {
        await regionPicker.pick(options)
    }

    public var screens: [ScreenInfo] {
        NSScreen.screens.map { screen in
            ScreenInfo(
                id: screen.displayID,
                name: screen.localizedName,
                frame: screen.frame,
                visibleFrame: screen.visibleFrame,
                notchHeight: screen.safeAreaInsets.top,
                isMain: screen == NSScreen.main
            )
        }
    }
}

extension NSScreen {
    var displayID: UInt32 {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

@MainActor
final class PanelHandle: OverlayHandle {
    private var panel: KKPanel?
    private let hostingView: NSHostingView<AnyView>
    private var configuration: OverlayConfiguration
    private var resignObserver: NSObjectProtocol?

    init(configuration: OverlayConfiguration, content: AnyView) {
        self.configuration = configuration
        self.hostingView = NSHostingView(rootView: content)
        let panel = KKPanel(contentRect: .zero, acceptsKeyFocus: configuration.acceptsKeyFocus)
        panel.contentView = hostingView
        self.panel = panel
        apply(configuration)
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.configuration.hidesOnResignKey else { return }
                self.hide()
            }
        }
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func show() {
        guard let panel else { return }
        panel.setFrame(Self.frame(for: configuration), display: false)
        if configuration.acceptsKeyFocus {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func setContent(_ content: AnyView) {
        hostingView.rootView = content
    }

    func setConfiguration(_ configuration: OverlayConfiguration) {
        self.configuration = configuration
        apply(configuration)
    }

    func close() {
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
        resignObserver = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }

    private func apply(_ configuration: OverlayConfiguration) {
        guard let panel else { return }
        switch configuration.level {
        case .aboveDesktopIcons:
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        case .floating: panel.level = .floating
        case .statusBar: panel.level = .statusBar
        case .screenSaver: panel.level = .screenSaver
        }
        panel.acceptsKeyFocus = configuration.acceptsKeyFocus
        panel.ignoresMouseEvents = configuration.ignoresMouseEvents
        panel.hasShadow = configuration.hasShadow
        panel.isMovable = configuration.isMovable
        panel.isMovableByWindowBackground = configuration.isMovable
        panel.setFrame(Self.frame(for: configuration), display: panel.isVisible)
    }

    static func screen(for target: OverlayScreen) -> NSScreen? {
        switch target {
        case .main:
            return NSScreen.main ?? NSScreen.screens.first
        case .withCursor:
            let location = NSEvent.mouseLocation
            return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) } ?? NSScreen.main
        case .display(let id):
            return NSScreen.screens.first { $0.displayID == id } ?? NSScreen.main
        }
    }

    static func frame(for configuration: OverlayConfiguration) -> CGRect {
        if case .frame(let rect) = configuration.placement { return rect }
        guard let screen = screen(for: configuration.screen) else { return .zero }
        let visible = screen.visibleFrame
        switch configuration.placement {
        case .centered(let size):
            return CGRect(
                x: (visible.midX - size.width / 2).rounded(),
                y: (visible.midY - size.height / 2).rounded(),
                width: size.width,
                height: size.height
            )
        case .topCenter(let size, let offset):
            return CGRect(
                x: (visible.midX - size.width / 2).rounded(),
                y: (visible.maxY - offset - size.height).rounded(),
                width: size.width,
                height: size.height
            )
        case .fullScreen:
            return screen.frame
        case .frame(let rect):
            return rect
        }
    }
}
