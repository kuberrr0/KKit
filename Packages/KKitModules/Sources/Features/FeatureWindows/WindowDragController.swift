import AppKit
import KKitCore
import KKitServicesAPI
import SwiftUI

/// Modifier + mouse move and resize, and drag-to-snap, on the shared input tap.
///
/// Modifier + mouse costs nothing until the modifiers go down: only then are mouse
/// buttons and drags armed, and the click is swallowed so the app underneath never sees
/// it. Window moves are coalesced: while one Accessibility move is in flight, newer
/// positions replace the pending one, so the window follows at the speed the app allows.
@MainActor
final class WindowDragController {
    private enum DragKind {
        case move
        case resize
    }

    private struct DragSession {
        let id = UUID()
        let kind: DragKind
        /// AppKit coordinates.
        let start: CGPoint
        var cursor: CGPoint
        var window: WindowInfo?
        var edges = ResizeEdges.bottomRight
        var failed = false
    }

    private struct SnapDrag {
        let start: CGPoint
        var window: WindowInfo?
        var zone: SnapAction?
        var showingPreview = false
    }

    private let input: FeatureInput
    private let windows: any WindowService
    private let overlays: any OverlayService
    private let settings: FeatureSettings
    private let controller: WindowsController

    private var modifierToken: InputHandlerToken?
    private var snapToken: InputHandlerToken?
    private var isArmed = false
    private var session: DragSession?
    private var pendingFrame: CGRect?
    private var isApplying = false
    private var snapDrag: SnapDrag?
    private var previewPanel: (any OverlayHandle)?
    private var tasks: [Task<Void, Never>] = []

    private static let mouseTypes: Set<InputEventType> = [
        .leftMouseDown, .leftMouseUp, .leftMouseDragged,
        .rightMouseDown, .rightMouseUp, .rightMouseDragged,
    ]

    init(input: FeatureInput, windows: any WindowService, overlays: any OverlayService, settings: FeatureSettings, controller: WindowsController) {
        self.input = input
        self.windows = windows
        self.overlays = overlays
        self.settings = settings
        self.controller = controller
    }

    func start() {
        let mouse = settings.changes(of: WindowsSettings.mouseEnabled)
        tasks.append(Task { [weak self] in
            for await enabled in mouse {
                self?.setModifierHandler(enabled)
            }
        })
        let snapping = settings.changes(of: WindowsSettings.dragToSnap)
        tasks.append(Task { [weak self] in
            for await enabled in snapping {
                self?.setSnapHandler(enabled)
            }
        })
        setModifierHandler(settings[WindowsSettings.mouseEnabled])
        setSnapHandler(settings[WindowsSettings.dragToSnap])
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks = []
        setModifierHandler(false)
        setSnapHandler(false)
        previewPanel?.close()
        previewPanel = nil
    }

    private func setModifierHandler(_ enabled: Bool) {
        if enabled, modifierToken == nil {
            modifierToken = input.add(priority: .normal, interests: [.flagsChanged]) { [weak self] event in
                self?.handleModifierInput(event) ?? .pass
            }
        } else if !enabled, let token = modifierToken {
            input.remove(token)
            modifierToken = nil
            isArmed = false
            session = nil
        }
    }

    private func setSnapHandler(_ enabled: Bool) {
        if enabled, snapToken == nil {
            snapToken = input.add(priority: .low, interests: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
                self?.handleSnapInput(event) ?? .pass
            }
        } else if !enabled, let token = snapToken {
            input.remove(token)
            snapToken = nil
            snapDrag = nil
            hidePreview()
        }
    }

    // MARK: Modifier + mouse

    private var moveModifiers: Shortcut.Modifiers {
        settings[WindowsSettings.moveModifiers]
    }

    private func handleModifierInput(_ event: InputEvent) -> InputDecision {
        switch event.type {
        case .flagsChanged:
            let modifiers = event.modifiers
            let held = !moveModifiers.isEmpty && (modifiers == moveModifiers || modifiers == moveModifiers.union(.shift))
            if held, !isArmed, let modifierToken {
                input.arm(Self.mouseTypes, for: modifierToken)
                isArmed = true
            } else if !held, isArmed, session == nil {
                disarm()
            }
            return .pass
        case .leftMouseDown, .rightMouseDown:
            if session != nil {
                return .consume
            }
            guard let kind = dragKind(for: event) else { return .pass }
            if controller.isExcluded(NSWorkspace.shared.frontmostApplication?.bundleIdentifier) {
                return .pass
            }
            let point = Self.appKitPoint(event.location)
            if kind == .move, event.clickCount == 2, settings[WindowsSettings.doubleClickToMaximize] {
                let windows = windows
                let controller = controller
                Task {
                    if let window = await windows.window(at: point), !controller.isExcluded(window.bundleID) {
                        await controller.toggleMaximize(window)
                    }
                }
                return .consume
            }
            beginSession(kind, at: point)
            return .consume
        case .leftMouseDragged, .rightMouseDragged:
            guard session != nil else { return .pass }
            updateSession(cursor: Self.appKitPoint(event.location))
            return .consume
        case .leftMouseUp, .rightMouseUp:
            guard session != nil else { return .pass }
            endSession(cursor: Self.appKitPoint(event.location))
            return .consume
        default:
            return .pass
        }
    }

    private func dragKind(for event: InputEvent) -> DragKind? {
        let modifiers = event.modifiers
        let move = moveModifiers
        guard !move.isEmpty else { return nil }
        let trigger = settings[WindowsSettings.resizeTrigger]
        if event.type == .leftMouseDown {
            if modifiers == move { return .move }
            if modifiers == move.union(.shift), trigger != .rightDrag { return .resize }
            return nil
        }
        if modifiers == move, trigger != .shiftLeftDrag { return .resize }
        return nil
    }

    private func beginSession(_ kind: DragKind, at point: CGPoint) {
        let new = DragSession(kind: kind, start: point, cursor: point)
        session = new
        pendingFrame = nil
        let windows = windows
        let raise = settings[WindowsSettings.raiseOnDrag]
        let nearest = settings[WindowsSettings.resizeFromNearestCorner]
        Task { [weak self] in
            let window = await windows.window(at: point)
            guard let self, self.session?.id == new.id else { return }
            guard let window, !window.isFullScreen, !self.controller.isExcluded(window.bundleID),
                  kind == .move || window.isResizable else {
                self.session?.failed = true
                return
            }
            self.session?.window = window
            self.session?.edges = SnapGeometry.resizeEdges(for: point, in: window.frame, nearestCorner: nearest)
            if raise {
                await windows.raise(window.ref)
            }
            // Catch up with drags that happened while the window was being found.
            if let cursor = self.session?.cursor {
                self.updateSession(cursor: cursor)
            }
        }
    }

    private func updateSession(cursor: CGPoint) {
        guard var current = session else { return }
        current.cursor = cursor
        session = current
        guard let window = current.window, !current.failed else { return }
        let dx = cursor.x - current.start.x
        let dy = cursor.y - current.start.y
        switch current.kind {
        case .move:
            pendingFrame = window.frame.offsetBy(dx: dx, dy: dy)
        case .resize:
            pendingFrame = SnapGeometry.resized(window.frame, edges: current.edges, dx: dx, dy: dy)
        }
        applyPending(window: window.ref, moveOnly: current.kind == .move)
    }

    private func endSession(cursor: CGPoint) {
        updateSession(cursor: cursor)
        let finished = session
        session = nil
        if !Self.modifiersHeld(moveModifiers) {
            disarm()
        }
        guard let finished, let window = finished.window, finished.kind == .move,
              settings[WindowsSettings.snapWhileModifierDragging],
              let zone = zone(at: cursor) else { return }
        let controller = controller
        let windows = windows
        Task {
            // Let the last move land first.
            try? await Task.sleep(for: .milliseconds(60))
            if let latest = await windows.info(for: window.ref) {
                await controller.snap(latest, to: zone)
            }
        }
    }

    /// One Accessibility call at a time; newer frames replace the pending one.
    private func applyPending(window: WindowHandle, moveOnly: Bool) {
        guard !isApplying else { return }
        isApplying = true
        let windows = windows
        Task { [weak self] in
            while let self, let frame = self.pendingFrame {
                self.pendingFrame = nil
                if moveOnly {
                    await windows.setOrigin(frame.origin, of: window)
                } else {
                    await windows.setFrame(frame, of: window)
                }
            }
            self?.isApplying = false
        }
    }

    private func disarm() {
        guard isArmed, let modifierToken else { return }
        input.disarm(modifierToken)
        isArmed = false
    }

    // MARK: Drag to snap

    private func handleSnapInput(_ event: InputEvent) -> InputDecision {
        switch event.type {
        case .leftMouseDown:
            guard session == nil, event.modifiers.isEmpty, shouldSnapOnDrag else { return .pass }
            let point = Self.appKitPoint(event.location)
            snapDrag = SnapDrag(start: point)
            if let snapToken {
                input.arm([.leftMouseDragged], for: snapToken)
            }
            let windows = windows
            Task { [weak self] in
                let window = await windows.window(at: point)
                guard let self, self.snapDrag?.start == point else { return }
                if let window, self.controller.isExcluded(window.bundleID) || window.isFullScreen {
                    self.snapDrag = nil
                    return
                }
                self.snapDrag?.window = window
            }
        case .leftMouseDragged:
            guard var drag = snapDrag else { return .pass }
            let point = Self.appKitPoint(event.location)
            let zone = zone(at: point)
            guard zone != drag.zone else { return .pass }
            drag.zone = zone
            snapDrag = drag
            if let zone, let window = drag.window {
                showPreviewIfMoved(window, zone: zone, cursor: point)
            } else {
                hidePreview()
            }
        case .leftMouseUp:
            if let snapToken {
                input.disarm(snapToken)
            }
            let drag = snapDrag
            snapDrag = nil
            hidePreview()
            guard let drag, drag.showingPreview, let zone = drag.zone, let window = drag.window else { return .pass }
            let controller = controller
            let windows = windows
            Task {
                // The app finishes its own drag first.
                try? await Task.sleep(for: .milliseconds(60))
                if let latest = await windows.info(for: window.ref) {
                    await controller.snap(latest, to: zone)
                }
            }
        default:
            break
        }
        return .pass
    }

    private var shouldSnapOnDrag: Bool {
        !(settings[WindowsSettings.deferToSystemTiling] && windows.isSystemEdgeTilingEnabled)
    }

    /// Shows the preview only once the window has really moved (not a text selection).
    private func showPreviewIfMoved(_ window: WindowInfo, zone: SnapAction, cursor: CGPoint) {
        let windows = windows
        Task { [weak self] in
            guard let now = await windows.info(for: window.ref),
                  !WindowsController.isClose(now.frame, window.frame, tolerance: 1) else { return }
            guard let self, self.snapDrag?.zone == zone else { return }
            self.snapDrag?.showingPreview = true
            self.showPreview(zone: zone, window: now, cursor: cursor)
        }
    }

    private func showPreview(zone: SnapAction, window: WindowInfo, cursor: CGPoint) {
        let screens = controller.screenFrames
        guard let screen = screens.first(where: { $0.frame.insetBy(dx: -1, dy: -1).contains(cursor) }) else { return }
        let frame = SnapGeometry.frame(
            for: zone,
            in: screen.visible,
            current: window.frame,
            gap: CGFloat(max(settings[WindowsSettings.gap], 0))
        )
        let configuration = OverlayConfiguration(
            level: .floating,
            placement: .frame(frame),
            ignoresMouseEvents: true,
            hasShadow: false
        )
        if let previewPanel {
            previewPanel.setConfiguration(configuration)
        } else {
            previewPanel = overlays.makePanel(configuration, content: AnyView(SnapPreviewView()))
        }
        previewPanel?.show()
    }

    private func hidePreview() {
        previewPanel?.hide()
        snapDrag?.showingPreview = false
    }

    private func zone(at point: CGPoint) -> SnapAction? {
        guard let screen = controller.screenFrames.first(where: { $0.frame.insetBy(dx: -1, dy: -1).contains(point) }) else {
            return nil
        }
        return SnapGeometry.dragZone(for: point, screen: screen.frame)
    }

    // MARK: Coordinates

    static func appKitPoint(_ point: CGPoint) -> CGPoint {
        SnapGeometry.appKitPoint(point, mainDisplayHeight: CGDisplayBounds(CGMainDisplayID()).height)
    }

    static func modifiersHeld(_ modifiers: Shortcut.Modifiers) -> Bool {
        let held = InputEvent.modifiers(from: CGEventSource.flagsState(.combinedSessionState))
        return !modifiers.isEmpty && (held == modifiers || held == modifiers.union(.shift))
    }
}

/// The translucent box showing where a dragged window will snap.
struct SnapPreviewView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.accentColor.opacity(0.18))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 2)
            )
            .padding(4)
            .accessibilityHidden(true)
    }
}
