import AppKit
import CoreGraphics
import KKitCore
import KKitServicesAPI

/// Displays and per-display gamma tables (`CGSetDisplayTransferByTable`, public API).
///
/// Adjustments multiply each display's original transfer table, so the display's own
/// colour profile is kept. macOS resets gamma tables when displays change and after
/// wake, so the service re-applies them then.
@MainActor
public final class CoreGraphicsDisplayService: DisplayService {
    private struct GammaTable {
        var red: [CGGammaValue]
        var green: [CGGammaValue]
        var blue: [CGGammaValue]
    }

    private var adjustments: [UInt32: ColorAdjustment] = [:]
    private var originals: [UInt32: GammaTable] = [:]
    private var eventTask: Task<Void, Never>?
    /// Private DisplayServices, loaded at run time (ARCHITECTURE.md §11 conventions).
    private let brightnessBridge = BrightnessBridge()
    private let log = KKitLog.logger("display")

    public init(events: EventBus) {
        let stream = events.stream { event in
            [AppEvent.displaysChanged, .systemDidWake, .screensDidWake].contains(event)
        }
        eventTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                if event == .displaysChanged {
                    // A reconnected display may come back with a new id; capture again.
                    self.forgetMissingDisplays()
                }
                self.reapplySoon()
            }
        }
    }

    public var displays: [DisplayInfo] {
        Self.activeDisplayIDs().map { id in
            DisplayInfo(
                id: id,
                stableID: "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))",
                name: NSScreen.screens.first { $0.displayID == id }?.localizedName ?? String(localized: "Display \(id)"),
                isBuiltIn: CGDisplayIsBuiltin(id) != 0
            )
        }
    }

    public func setColorAdjustment(_ adjustment: ColorAdjustment, for displayID: UInt32) {
        if adjustment.isIdentity {
            guard adjustments.removeValue(forKey: displayID) != nil else { return }
        } else {
            adjustments[displayID] = adjustment
        }
        apply(adjustment, to: displayID)
    }

    public func resetColorAdjustments() {
        guard !adjustments.isEmpty else { return }
        adjustments.removeAll()
        CGDisplayRestoreColorSyncSettings()
    }

    public func brightness(of displayID: UInt32) -> Double? {
        brightnessBridge.brightness(of: displayID)
    }

    public func setBrightness(_ brightness: Double, for displayID: UInt32) {
        brightnessBridge.setBrightness(brightness, for: displayID)
    }

    // MARK: Private

    private static func activeDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    private func apply(_ adjustment: ColorAdjustment, to displayID: UInt32) {
        if originals[displayID] == nil {
            originals[displayID] = Self.readTable(displayID)
        }
        guard let original = originals[displayID] else {
            log.error("No gamma table for display \(displayID)")
            return
        }
        let red = original.red.map { CGGammaValue(Double($0) * adjustment.red) }
        let green = original.green.map { CGGammaValue(Double($0) * adjustment.green) }
        let blue = original.blue.map { CGGammaValue(Double($0) * adjustment.blue) }
        let result = CGSetDisplayTransferByTable(displayID, UInt32(red.count), red, green, blue)
        if result != .success {
            log.error("CGSetDisplayTransferByTable failed for display \(displayID): \(result.rawValue)")
        }
    }

    private static func readTable(_ displayID: UInt32) -> GammaTable? {
        let capacity = CGDisplayGammaTableCapacity(displayID)
        guard capacity > 0 else { return nil }
        var red = [CGGammaValue](repeating: 0, count: Int(capacity))
        var green = [CGGammaValue](repeating: 0, count: Int(capacity))
        var blue = [CGGammaValue](repeating: 0, count: Int(capacity))
        var count: UInt32 = 0
        guard CGGetDisplayTransferByTable(displayID, capacity, &red, &green, &blue, &count) == .success, count > 0 else {
            return nil
        }
        let n = Int(count)
        return GammaTable(red: Array(red.prefix(n)), green: Array(green.prefix(n)), blue: Array(blue.prefix(n)))
    }

    private func forgetMissingDisplays() {
        let active = Set(Self.activeDisplayIDs())
        originals = originals.filter { active.contains($0.key) }
        adjustments = adjustments.filter { active.contains($0.key) }
    }

    /// Re-applies now and again shortly after, because macOS sometimes resets the
    /// tables a moment after the notification.
    private func reapplySoon() {
        reapply()
        Task { [weak self] in
            for delay in [1, 3] {
                try? await Task.sleep(for: .seconds(delay))
                self?.reapply()
            }
        }
    }

    private func reapply() {
        for (displayID, adjustment) in adjustments {
            apply(adjustment, to: displayID)
        }
    }
}
