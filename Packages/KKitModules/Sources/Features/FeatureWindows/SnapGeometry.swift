import CoreGraphics
import Foundation
import KKitCore

/// Where a window can be snapped. The raw value is the command verb (`windows.leftHalf`).
enum SnapAction: String, CaseIterable, Codable, Sendable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case firstThird, centerThird, lastThird, firstTwoThirds, lastTwoThirds
    case maximize, almostMaximize, center

    var title: String {
        switch self {
        case .leftHalf: String(localized: "Left Half")
        case .rightHalf: String(localized: "Right Half")
        case .topHalf: String(localized: "Top Half")
        case .bottomHalf: String(localized: "Bottom Half")
        case .topLeft: String(localized: "Top Left Quarter")
        case .topRight: String(localized: "Top Right Quarter")
        case .bottomLeft: String(localized: "Bottom Left Quarter")
        case .bottomRight: String(localized: "Bottom Right Quarter")
        case .firstThird: String(localized: "First Third")
        case .centerThird: String(localized: "Center Third")
        case .lastThird: String(localized: "Last Third")
        case .firstTwoThirds: String(localized: "First Two Thirds")
        case .lastTwoThirds: String(localized: "Last Two Thirds")
        case .maximize: String(localized: "Maximize")
        case .almostMaximize: String(localized: "Almost Maximize")
        case .center: String(localized: "Center")
        }
    }

    var symbol: String {
        switch self {
        case .leftHalf: "rectangle.lefthalf.filled"
        case .rightHalf: "rectangle.righthalf.filled"
        case .topHalf: "rectangle.tophalf.filled"
        case .bottomHalf: "rectangle.bottomhalf.filled"
        case .topLeft: "rectangle.inset.topleft.filled"
        case .topRight: "rectangle.inset.topright.filled"
        case .bottomLeft: "rectangle.inset.bottomleft.filled"
        case .bottomRight: "rectangle.inset.bottomright.filled"
        case .firstThird: "rectangle.leadingthird.inset.filled"
        case .centerThird: "rectangle.center.inset.filled"
        case .lastThird: "rectangle.trailingthird.inset.filled"
        case .firstTwoThirds: "rectangle.split.2x1.fill"
        case .lastTwoThirds: "rectangle.split.2x1.fill"
        case .maximize: "macwindow"
        case .almostMaximize: "macwindow.badge.plus"
        case .center: "rectangle.center.inset.filled"
        }
    }

    /// The word for `win <choice>` in the Floating Bar.
    var choiceName: String {
        switch self {
        case .leftHalf: "left"
        case .rightHalf: "right"
        case .topHalf: "top"
        case .bottomHalf: "bottom"
        case .topLeft: "top left"
        case .topRight: "top right"
        case .bottomLeft: "bottom left"
        case .bottomRight: "bottom right"
        case .firstThird: "first third"
        case .centerThird: "center third"
        case .lastThird: "last third"
        case .firstTwoThirds: "first two thirds"
        case .lastTwoThirds: "last two thirds"
        case .maximize: "max"
        case .almostMaximize: "almost max"
        case .center: "center"
        }
    }

    static func named(_ text: String) -> SnapAction? {
        let needle = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return allCases.first { $0.choiceName == needle }
            ?? allCases.first { $0.rawValue.lowercased() == needle.replacingOccurrences(of: " ", with: "") }
            ?? allCases.first { $0.choiceName.hasPrefix(needle) }
    }

    /// ⌃⌥ plus a key, like other window managers.
    var defaultShortcut: Shortcut? {
        let key: Int
        switch self {
        case .leftHalf: key = Shortcut.Key.leftArrow
        case .rightHalf: key = Shortcut.Key.rightArrow
        case .topHalf: key = Shortcut.Key.upArrow
        case .bottomHalf: key = Shortcut.Key.downArrow
        case .topLeft: key = Shortcut.Key.u
        case .topRight: key = Shortcut.Key.i
        case .bottomLeft: key = Shortcut.Key.j
        case .bottomRight: key = Shortcut.Key.k
        case .firstThird: key = Shortcut.Key.d
        case .centerThird: key = Shortcut.Key.f
        case .lastThird: key = Shortcut.Key.g
        case .firstTwoThirds: key = Shortcut.Key.e
        case .lastTwoThirds: key = Shortcut.Key.t
        case .maximize: key = Shortcut.Key.returnKey
        case .center: key = Shortcut.Key.c
        case .almostMaximize: return nil
        }
        return Shortcut(keyCode: key, modifiers: [.control, .option])
    }

    /// Halves cycle ½ → ⅓ → ⅔ when the shortcut is pressed again.
    var cycles: Bool {
        [.leftHalf, .rightHalf, .topHalf, .bottomHalf].contains(self)
    }
}

/// Which edges a modifier + mouse resize moves.
struct ResizeEdges: Equatable, Sendable {
    var left = false
    var right = false
    var top = false
    var bottom = false

    static let bottomRight = ResizeEdges(right: true, bottom: true)
}

/// Window geometry, all in AppKit coordinates (bottom-left origin), kept pure for tests.
enum SnapGeometry {
    /// The widths (or heights) a half cycles through.
    static let cycleFractions: [CGFloat] = [1.0 / 2, 1.0 / 3, 2.0 / 3]

    /// Where `action` puts a window on a screen whose visible frame is `visible`.
    static func frame(for action: SnapAction, in visible: CGRect, current: CGRect, gap: CGFloat = 0, cycle: Int = 0) -> CGRect {
        let fraction = action.cycles ? cycleFractions[((cycle % cycleFractions.count) + cycleFractions.count) % cycleFractions.count] : 0.5
        let v = visible
        let landscape = v.width >= v.height
        let rect: CGRect
        switch action {
        case .leftHalf:
            rect = CGRect(x: v.minX, y: v.minY, width: v.width * fraction, height: v.height)
        case .rightHalf:
            rect = CGRect(x: v.maxX - v.width * fraction, y: v.minY, width: v.width * fraction, height: v.height)
        case .topHalf:
            rect = CGRect(x: v.minX, y: v.maxY - v.height * fraction, width: v.width, height: v.height * fraction)
        case .bottomHalf:
            rect = CGRect(x: v.minX, y: v.minY, width: v.width, height: v.height * fraction)
        case .topLeft:
            rect = CGRect(x: v.minX, y: v.midY, width: v.width / 2, height: v.height / 2)
        case .topRight:
            rect = CGRect(x: v.midX, y: v.midY, width: v.width / 2, height: v.height / 2)
        case .bottomLeft:
            rect = CGRect(x: v.minX, y: v.minY, width: v.width / 2, height: v.height / 2)
        case .bottomRight:
            rect = CGRect(x: v.midX, y: v.minY, width: v.width / 2, height: v.height / 2)
        case .firstThird, .centerThird, .lastThird, .firstTwoThirds, .lastTwoThirds:
            let (start, length): (CGFloat, CGFloat) = switch action {
            case .firstThird: (0, 1.0 / 3)
            case .centerThird: (1.0 / 3, 1.0 / 3)
            case .lastThird: (2.0 / 3, 1.0 / 3)
            case .firstTwoThirds: (0, 2.0 / 3)
            default: (1.0 / 3, 2.0 / 3)
            }
            if landscape {
                rect = CGRect(x: v.minX + v.width * start, y: v.minY, width: v.width * length, height: v.height)
            } else {
                // Portrait screens split top to bottom: the first third is the top one.
                let height = v.height * length
                rect = CGRect(x: v.minX, y: v.maxY - v.height * start - height, width: v.width, height: height)
            }
        case .maximize:
            rect = v
        case .almostMaximize:
            rect = v.insetBy(dx: v.width * 0.05, dy: v.height * 0.05)
            return rect.integral
        case .center:
            let width = min(current.width, v.width)
            let height = min(current.height, v.height)
            return CGRect(x: v.midX - width / 2, y: v.midY - height / 2, width: width, height: height).integral
        }
        return gapped(rect, in: v, gap: gap).integral
    }

    /// Insets `rect` by `gap` where it touches the screen edge and by half that between
    /// windows, so neighbouring windows end up `gap` apart.
    static func gapped(_ rect: CGRect, in visible: CGRect, gap: CGFloat) -> CGRect {
        guard gap > 0 else { return rect }
        func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 1 }
        let left = near(rect.minX, visible.minX) ? gap : gap / 2
        let right = near(rect.maxX, visible.maxX) ? gap : gap / 2
        let bottom = near(rect.minY, visible.minY) ? gap : gap / 2
        let top = near(rect.maxY, visible.maxY) ? gap : gap / 2
        return CGRect(
            x: rect.minX + left,
            y: rect.minY + bottom,
            width: max(rect.width - left - right, 50),
            height: max(rect.height - top - bottom, 50)
        )
    }

    /// The same place on another screen, scaled to its size.
    static func move(_ frame: CGRect, from source: CGRect, to target: CGRect) -> CGRect {
        guard source.width > 0, source.height > 0 else { return frame }
        let scaleX = target.width / source.width
        let scaleY = target.height / source.height
        var result = CGRect(
            x: target.minX + (frame.minX - source.minX) * scaleX,
            y: target.minY + (frame.minY - source.minY) * scaleY,
            width: frame.width * scaleX,
            height: frame.height * scaleY
        )
        result = clamp(result, to: target)
        return result.integral
    }

    /// Grows (or shrinks) by `step` of the screen on every side, staying on the screen.
    static func resize(_ frame: CGRect, in visible: CGRect, grow: Bool, step: CGFloat = 0.05) -> CGRect {
        let dx = visible.width * step * (grow ? -1 : 1)
        let dy = visible.height * step * (grow ? -1 : 1)
        var result = frame.insetBy(dx: dx, dy: dy)
        if !grow, result.width < 200 || result.height < 150 {
            return frame
        }
        result = clamp(result, to: visible)
        return result.integral
    }

    /// Moved and shrunk to fit inside `bounds`.
    static func clamp(_ frame: CGRect, to bounds: CGRect) -> CGRect {
        let width = min(frame.width, bounds.width)
        let height = min(frame.height, bounds.height)
        let x = min(max(frame.minX, bounds.minX), bounds.maxX - width)
        let y = min(max(frame.minY, bounds.minY), bounds.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    // MARK: Dragging

    /// The snap a window dragged to `point` would get: screen edges are halves (top is
    /// maximise), corners quarters. The bottom edge (the Dock) only has corners.
    static func dragZone(for point: CGPoint, screen: CGRect, edge: CGFloat = 6, corner: CGFloat = 60) -> SnapAction? {
        guard screen.insetBy(dx: -1, dy: -1).contains(point) else { return nil }
        let nearLeft = point.x <= screen.minX + edge
        let nearRight = point.x >= screen.maxX - edge
        let nearTop = point.y >= screen.maxY - edge
        let nearBottom = point.y <= screen.minY + edge
        let topBand = point.y >= screen.maxY - corner
        let bottomBand = point.y <= screen.minY + corner
        let leftBand = point.x <= screen.minX + corner
        let rightBand = point.x >= screen.maxX - corner
        if nearLeft {
            return topBand ? .topLeft : (bottomBand ? .bottomLeft : .leftHalf)
        }
        if nearRight {
            return topBand ? .topRight : (bottomBand ? .bottomRight : .rightHalf)
        }
        if nearTop {
            return leftBand ? .topLeft : (rightBand ? .topRight : .maximize)
        }
        if nearBottom {
            return leftBand ? .bottomLeft : (rightBand ? .bottomRight : nil)
        }
        return nil
    }

    /// Which edges follow the mouse when resizing from `point`: the nearest corner, or
    /// just one edge from the middle of a side.
    static func resizeEdges(for point: CGPoint, in frame: CGRect, nearestCorner: Bool) -> ResizeEdges {
        guard nearestCorner, frame.width > 0, frame.height > 0 else { return .bottomRight }
        let rx = (point.x - frame.minX) / frame.width
        let ry = (point.y - frame.minY) / frame.height
        var edges = ResizeEdges()
        if rx < 1.0 / 3 { edges.left = true } else if rx > 2.0 / 3 { edges.right = true }
        if ry < 1.0 / 3 { edges.bottom = true } else if ry > 2.0 / 3 { edges.top = true }
        if edges == ResizeEdges() {
            // The middle: the nearest corner.
            edges.left = rx < 0.5
            edges.right = rx >= 0.5
            edges.bottom = ry < 0.5
            edges.top = ry >= 0.5
        }
        return edges
    }

    static func resized(_ frame: CGRect, edges: ResizeEdges, dx: CGFloat, dy: CGFloat, minimum: CGSize = CGSize(width: 160, height: 100)) -> CGRect {
        var minX = frame.minX, maxX = frame.maxX, minY = frame.minY, maxY = frame.maxY
        if edges.left { minX = min(minX + dx, maxX - minimum.width) }
        if edges.right { maxX = max(maxX + dx, minX + minimum.width) }
        if edges.bottom { minY = min(minY + dy, maxY - minimum.height) }
        if edges.top { maxY = max(maxY + dy, minY + minimum.height) }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// The screen a frame is mostly on.
    static func screenIndex(for frame: CGRect, screens: [CGRect]) -> Int? {
        var best: (index: Int, area: CGFloat)?
        for (index, screen) in screens.enumerated() {
            let overlap = screen.intersection(frame)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if area > (best?.area ?? 0) {
                best = (index, area)
            }
        }
        if let best { return best.index }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return screens.firstIndex { $0.contains(center) }
    }

    /// Core Graphics / Accessibility point (top-left origin) → AppKit.
    static func appKitPoint(_ point: CGPoint, mainDisplayHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: mainDisplayHeight - point.y)
    }
}
