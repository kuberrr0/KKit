import Foundation
import KKitServicesAPI

/// Volume arithmetic, kept pure for tests.
enum VolumeMath {
    /// The next volume one step up or down, snapped to the step grid and kept within
    /// `0...limit`. `fine` steps are a quarter of a normal step.
    static func stepped(_ current: Double, step: Double, up: Bool, fine: Bool = false, limit: Double = 1) -> Double {
        let size = fine ? step / 4 : step
        guard size > 0 else { return current }
        let index = current / size
        let target = up
            ? (index + 1e-6).rounded(.down) + 1
            : (index - 1e-6).rounded(.up) - 1
        return clamp(target * size, limit: limit)
    }

    static func clamp(_ volume: Double, limit: Double = 1) -> Double {
        min(max(volume, 0), min(max(limit, 0), 1))
    }

    /// The speaker symbol for a level.
    static func speakerSymbol(volume: Double?, muted: Bool) -> String {
        guard let volume, !muted, volume > 0.001 else { return "speaker.slash.fill" }
        switch volume {
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }
}

/// Turns Island scroll events into volume steps. Trackpads send many small pixel
/// deltas, so they're accumulated; a mouse wheel notch is one step.
struct ScrollAccumulator {
    /// Points of trackpad scrolling per step.
    var threshold: Double
    private(set) var pending: Double = 0

    init(threshold: Double = 14) {
        self.threshold = threshold
    }

    mutating func steps(for event: IslandScrollEvent) -> Int {
        guard event.isPrecise else {
            if event.deltaY > 0 { return 1 }
            if event.deltaY < 0 { return -1 }
            return 0
        }
        if pending != 0, (pending > 0) != (event.deltaY > 0) {
            pending = 0
        }
        pending += event.deltaY
        let steps = Int(pending / threshold)
        pending -= Double(steps) * threshold
        return steps
    }
}

/// Picking devices.
enum AudioDevicePicker {
    /// The first connected device in the priority list.
    static func preferred(in devices: [AudioDevice], priority: [PriorityDevice]) -> AudioDevice? {
        for entry in priority {
            if let device = devices.first(where: { $0.uid == entry.uid }) {
                return device
            }
        }
        return nil
    }

    /// A device by (part of) its name, as typed in the Floating Bar: "airpods".
    /// Exact match, then prefix, then substring; case- and accent-insensitive.
    static func match(_ query: String, in devices: [AudioDevice]) -> AudioDevice? {
        let needle = normalize(query)
        guard !needle.isEmpty else { return nil }
        let names = devices.map { (device: $0, name: normalize($0.name)) }
        return names.first { $0.name == needle }?.device
            ?? names.first { $0.name.hasPrefix(needle) }?.device
            ?? names.first { $0.name.contains(needle) }?.device
    }

    /// The device after `current` in `devices`, wrapping around.
    static func next(after current: AudioDevice?, in devices: [AudioDevice]) -> AudioDevice? {
        guard !devices.isEmpty else { return nil }
        guard let current, let index = devices.firstIndex(where: { $0.uid == current.uid }) else {
            return devices.first
        }
        return devices[(index + 1) % devices.count]
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
