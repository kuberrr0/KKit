import CoreGraphics
import Foundation
import KKitCore
import KKitServicesAPI

/// A saved arrangement of windows: "Coding".
struct WindowLayout: Codable, Hashable, Identifiable, Sendable {
    struct Entry: Codable, Hashable, Sendable {
        var bundleID: String
        var appName: String
        var title: String
        /// AppKit coordinates.
        var frame: CGRect
    }

    var id = UUID()
    var name: String
    var entries: [Entry]
    var savedAt = Date()
}

/// Matching a layout's entries to the windows open now, kept pure for tests.
enum LayoutMatcher {
    /// For each app, windows with the same title first, then the rest in order.
    static func assignments(for layout: WindowLayout, windows: [WindowInfo]) -> [(WindowHandle, CGRect)] {
        var result: [(WindowHandle, CGRect)] = []
        var used: Set<WindowHandle> = []
        let byApp = Dictionary(grouping: layout.entries, by: \.bundleID)
        for (bundleID, entries) in byApp {
            let candidates = windows.filter { $0.bundleID == bundleID && !$0.isMinimized && !$0.isFullScreen }
            var remaining: [WindowLayout.Entry] = []
            for entry in entries {
                if !entry.title.isEmpty,
                   let match = candidates.first(where: { $0.title == entry.title && !used.contains($0.ref) }) {
                    used.insert(match.ref)
                    result.append((match.ref, entry.frame))
                } else {
                    remaining.append(entry)
                }
            }
            for entry in remaining {
                guard let match = candidates.first(where: { !used.contains($0.ref) }) else { break }
                used.insert(match.ref)
                result.append((match.ref, entry.frame))
            }
        }
        return result
    }

    static func layout(named name: String, windows: [WindowInfo]) -> WindowLayout {
        WindowLayout(
            name: name,
            entries: windows.compactMap { window in
                guard let bundleID = window.bundleID, !window.isMinimized, !window.isFullScreen else { return nil }
                return WindowLayout.Entry(bundleID: bundleID, appName: window.appName, title: window.title, frame: window.frame)
            }
        )
    }

    /// A layout by (part of) its name.
    static func find(_ name: String, in layouts: [WindowLayout]) -> WindowLayout? {
        let needle = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return nil }
        return layouts.first { $0.name.lowercased() == needle }
            ?? layouts.first { $0.name.lowercased().hasPrefix(needle) }
            ?? layouts.first { $0.name.lowercased().contains(needle) }
    }
}

/// "Layout: Coding" results in the Floating Bar.
@MainActor
final class LayoutsProvider: SearchProvider {
    let id = "layouts"
    let displayName = String(localized: "Window Layouts")
    let symbol = "rectangle.3.group"

    private let controller: WindowsController

    init(controller: WindowsController) {
        self.controller = controller
    }

    func results(for query: SearchQuery) -> AsyncStream<[SearchResult]> {
        let text = query.trimmed
        let controller = controller
        let results = controller.layouts.compactMap { layout -> SearchResult? in
            let title = String(localized: "Layout: \(layout.name)")
            let score: Double
            if text.isEmpty {
                guard query.isScoped else { return nil }
                score = 0.5
            } else {
                guard let match = FuzzyMatch.score(text, title: title, keywords: [layout.name, "layout", "windows"]) else { return nil }
                score = match
            }
            let layoutID = layout.id
            return SearchResult(
                id: "layout:\(layout.id.uuidString)",
                title: title,
                subtitle: String(localized: "\(layout.entries.count) windows"),
                icon: .symbol("rectangle.3.group"),
                score: score,
                kind: .custom,
                actionTitle: String(localized: "Restore"),
                perform: {
                    try await controller.restoreLayout(id: layoutID)
                }
            )
        }
        return .single(results)
    }
}
