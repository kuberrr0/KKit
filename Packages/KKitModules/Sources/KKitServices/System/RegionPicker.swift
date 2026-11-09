import AppKit
import KKitServicesAPI
import KKitUI

/// Dims every screen and lets the user drag out an area, click a window or pick a
/// screen, like macOS's own screenshot tool. Space switches between area and window,
/// ⎋ cancels. Used by `AppKitOverlayService.pickRegion`.
@MainActor
final class RegionPicker {
    private var panels: [KKPanel] = []
    private var views: [RegionPickerView] = []
    private var continuation: CheckedContinuation<RegionSelection?, Never>?
    private var previousApp: NSRunningApplication?

    var isPicking: Bool { continuation != nil }

    func pick(_ options: RegionPickerOptions) async -> RegionSelection? {
        guard continuation == nil else { return nil }
        previousApp = NSWorkspace.shared.frontmostApplication
        let windows = PickableWindow.onScreen()
        let mouse = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            let panel = KKPanel(contentRect: screen.frame, acceptsKeyFocus: true)
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.animationBehavior = .none
            panel.acceptsMouseMovedEvents = true
            let view = RegionPickerView(
                screenFrame: screen.frame,
                displayID: screen.displayID,
                style: options.style,
                prompt: options.prompt,
                windows: windows
            )
            view.onFinish = { [weak self] selection in self?.finish(selection) }
            view.onStyleChange = { [weak self] style in self?.views.forEach { $0.style = style } }
            panel.contentView = view
            panel.setFrame(screen.frame, display: false)
            panels.append(panel)
            views.append(view)
        }
        // The picker needs the keyboard (⎋, Space) and the cursor, so KKit comes to the
        // front for a moment; the previous app gets focus back afterwards.
        NSApp.activate()
        for (index, panel) in panels.enumerated() {
            if NSMouseInRect(mouse, panel.frame, false) {
                panel.makeKeyAndOrderFront(nil)
                panel.makeFirstResponder(views[index])
            } else {
                panel.orderFrontRegardless()
            }
        }
        if !panels.contains(where: \.isKeyWindow), let first = panels.first {
            first.makeKeyAndOrderFront(nil)
            first.makeFirstResponder(views.first)
        }
        NSCursor.crosshair.set()
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    private func finish(_ selection: RegionSelection?) {
        for panel in panels {
            panel.orderOut(nil)
            panel.close()
        }
        panels = []
        views = []
        NSCursor.arrow.set()
        if let previousApp, previousApp.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp.activate(options: [])
        }
        previousApp = nil
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(returning: selection)
    }
}

/// A window the picker can highlight, in AppKit global coordinates.
struct PickableWindow: Sendable {
    var id: UInt32
    var frame: CGRect

    /// On-screen app windows, front to back, without KKit's own.
    @MainActor
    static func onScreen() -> [PickableWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let ownPID = Int(ProcessInfo.processInfo.processIdentifier)
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        return info.compactMap { entry in
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  (entry[kCGWindowOwnerPID as String] as? Int) != ownPID,
                  let number = entry[kCGWindowNumber as String] as? Int,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.width >= 40, bounds.height >= 40
            else { return nil }
            if let alpha = entry[kCGWindowAlpha as String] as? Double, alpha <= 0 { return nil }
            // Quartz window bounds have their origin at the top left of the main screen.
            let frame = CGRect(x: bounds.minX, y: mainHeight - bounds.maxY, width: bounds.width, height: bounds.height)
            return PickableWindow(id: UInt32(number), frame: frame)
        }
    }
}

/// One screen's part of the picker.
final class RegionPickerView: NSView {
    var onFinish: (@MainActor (RegionSelection?) -> Void)?
    var onStyleChange: (@MainActor (RegionPickerStyle) -> Void)?
    var style: RegionPickerStyle {
        didSet { needsDisplay = true }
    }

    private let screenFrame: CGRect
    private let displayID: UInt32
    private let prompt: String?
    private let windows: [PickableWindow]
    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var hoverPoint: CGPoint?

    init(screenFrame: CGRect, displayID: UInt32, style: RegionPickerStyle, prompt: String?, windows: [PickableWindow]) {
        self.screenFrame = screenFrame
        self.displayID = displayID
        self.style = style
        self.prompt = prompt
        self.windows = windows
        super.init(frame: CGRect(origin: .zero, size: screenFrame.size))
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate],
            owner: self,
            userInfo: nil
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var isFlipped: Bool { false }

    // MARK: Geometry

    private func global(_ local: CGPoint) -> CGPoint {
        CGPoint(x: local.x + screenFrame.minX, y: local.y + screenFrame.minY)
    }

    private func local(_ rect: CGRect) -> CGRect {
        rect.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
    }

    private var dragRect: CGRect? {
        guard let dragStart, let dragCurrent else { return nil }
        return CGRect(
            x: min(dragStart.x, dragCurrent.x),
            y: min(dragStart.y, dragCurrent.y),
            width: abs(dragStart.x - dragCurrent.x),
            height: abs(dragStart.y - dragCurrent.y)
        )
    }

    private func window(at local: CGPoint) -> PickableWindow? {
        let point = global(local)
        return windows.first { $0.frame.contains(point) }
    }

    // MARK: Events

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func mouseMoved(with event: NSEvent) {
        hoverPoint = convert(event.locationInWindow, from: nil)
        NSCursor.crosshair.set()
        if style != .area {
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoverPoint = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if style == .area {
            dragStart = point
            dragCurrent = point
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard style == .area, dragStart != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        dragCurrent = CGPoint(x: min(max(point.x, 0), bounds.width), y: min(max(point.y, 0), bounds.height))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch style {
        case .area:
            if let rect = dragRect, rect.width >= 4, rect.height >= 4 {
                finish(RegionSelection(displayID: displayID, rect: rect.offsetBy(dx: screenFrame.minX, dy: screenFrame.minY)))
            } else if let window = window(at: point) {
                // A click without a drag takes the window under the cursor.
                finish(RegionSelection(displayID: displayID, rect: window.frame, windowID: window.id))
            } else {
                dragStart = nil
                dragCurrent = nil
                needsDisplay = true
            }
        case .window:
            if let window = window(at: point) {
                finish(RegionSelection(displayID: displayID, rect: window.frame, windowID: window.id))
            }
        case .screen:
            finish(RegionSelection(displayID: displayID, rect: screenFrame))
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        finish(nil)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:
            finish(nil)
        case 49 where style != .screen:
            let next: RegionPickerStyle = style == .area ? .window : .area
            dragStart = nil
            dragCurrent = nil
            onStyleChange?(next)
        case 36 where style == .screen, 76 where style == .screen:
            finish(RegionSelection(displayID: displayID, rect: screenFrame))
        default:
            super.keyDown(with: event)
        }
    }

    private func finish(_ selection: RegionSelection?) {
        let onFinish = self.onFinish
        self.onFinish = nil
        onFinish?(selection)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let dim = NSColor.black.withAlphaComponent(0.28)
        var highlight: CGRect?
        switch style {
        case .area:
            highlight = dragRect
        case .window:
            if let hoverPoint, let window = window(at: hoverPoint) {
                highlight = local(window.frame).intersection(bounds)
            }
        case .screen:
            if hoverPoint != nil {
                highlight = bounds
            }
        }

        if let highlight, style == .area {
            let path = NSBezierPath(rect: bounds)
            path.appendRect(highlight)
            path.windingRule = .evenOdd
            dim.setFill()
            path.fill()
            NSColor.white.withAlphaComponent(0.9).setStroke()
            let border = NSBezierPath(rect: highlight.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1
            border.stroke()
            drawSizeLabel(for: highlight)
        } else {
            dim.setFill()
            bounds.fill()
            if let highlight {
                NSColor.controlAccentColor.withAlphaComponent(0.25).setFill()
                highlight.fill(using: .sourceOver)
                NSColor.controlAccentColor.withAlphaComponent(0.8).setStroke()
                let border = NSBezierPath(rect: highlight.insetBy(dx: 1, dy: 1))
                border.lineWidth = 2
                border.stroke()
            }
        }
        drawPrompt()
    }

    private func drawSizeLabel(for rect: CGRect) {
        let text = "\(Int(rect.width)) × \(Int(rect.height))" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attributes)
        var origin = CGPoint(x: rect.maxX - size.width - 8, y: rect.minY - size.height - 10)
        if origin.y < 4 { origin.y = rect.minY + 6 }
        origin.x = max(origin.x, 4)
        let background = CGRect(x: origin.x - 5, y: origin.y - 3, width: size.width + 10, height: size.height + 6)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: background, xRadius: 5, yRadius: 5).fill()
        text.draw(at: origin, withAttributes: attributes)
    }

    private func drawPrompt() {
        let hint: String
        switch style {
        case .area:
            hint = String(localized: "Drag to select · Space for a window · ⎋ to cancel")
        case .window:
            hint = String(localized: "Click a window · Space to drag an area · ⎋ to cancel")
        case .screen:
            hint = String(localized: "Click a screen · ⎋ to cancel")
        }
        let text = ([prompt, hint].compactMap { $0 }.joined(separator: "  —  ")) as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attributes)
        let origin = CGPoint(x: (bounds.width - size.width) / 2, y: bounds.height - size.height - 60)
        let background = CGRect(x: origin.x - 12, y: origin.y - 6, width: size.width + 24, height: size.height + 12)
        NSColor.black.withAlphaComponent(0.65).setFill()
        NSBezierPath(roundedRect: background, xRadius: background.height / 2, yRadius: background.height / 2).fill()
        text.draw(at: origin, withAttributes: attributes)
    }
}
