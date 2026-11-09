import Foundation
import KKitCore
import KKitServicesAPI
import SwiftUI

/// Colours in the Floating Bar. A colour typed anywhere (`#FF8800`, `rgb(255 136 0)`,
/// `hsl(32 100% 50%)`, `Color(red: …)`) shows in every format, ↵ copies one. `#` on its
/// own lists Pick Colour and the recent colours.
@MainActor
final class ColorProvider: SearchProvider {
    nonisolated static let prefixText = "#"

    let id = "colors"
    let displayName = String(localized: "Colours")
    let symbol = "eyedropper"
    let prefix: String? = ColorProvider.prefixText
    private let controller: ColorPickerController

    init(controller: ColorPickerController) {
        self.controller = controller
    }

    func results(for query: SearchQuery) -> AsyncStream<[SearchResult]> {
        .single(search(query))
    }

    func search(_ query: SearchQuery) -> [SearchResult] {
        let text = query.trimmed
        if query.isScoped {
            if text.isEmpty {
                return [pickResult()] + recentResults()
            }
            // The router took the "#" off: "#ff8800" arrives as "ff8800".
            let color = ColorParser.hex(text) ?? ColorParser.parse(text)
            return color.map(conversions) ?? []
        }
        return ColorParser.parse(text).map(conversions) ?? []
    }

    // MARK: Rows

    /// The colour in each format, the chosen one first.
    func conversions(_ color: RGBAColor) -> [SearchResult] {
        let chosen = controller.settings[ColorPickerSettings.format]
        let formats = [chosen] + ColorFormat.allCases.filter { $0 != chosen }
        let controller = controller
        return formats.enumerated().map { (index, format) -> SearchResult in
            let text = controller.string(color, format: format)
            return SearchResult(
                id: "color:\(color.hex):\(format.rawValue)",
                title: text,
                subtitle: format.title,
                icon: Self.icon(color),
                // Above everything else when it's clearly a colour, in format order.
                score: 0.97 - Double(index) * 0.001,
                kind: .text(text),
                accessory: index == 0 ? String(localized: "Colour") : nil,
                actionTitle: String(localized: "Copy"),
                perform: { _ = controller.copy(color, format: format) },
                preview: { AnyView(ColorPreview(color: color, controller: controller)) }
            )
        }
    }

    private func pickResult() -> SearchResult {
        SearchResult(
            id: "color:pick",
            title: String(localized: "Pick Colour from Screen"),
            subtitle: String(localized: "Click anywhere to copy the colour under the loupe"),
            icon: .symbol("eyedropper"),
            score: 1,
            kind: .command(ColorPickerFeature.pickCommand, argument: nil),
            actionTitle: String(localized: "Pick")
        )
    }

    private func recentResults() -> [SearchResult] {
        let controller = controller
        return controller.history.enumerated().map { (index, color) -> SearchResult in
            let text = controller.string(color)
            return SearchResult(
                id: "color:recent:\(color.hex)",
                title: text,
                subtitle: index == 0 ? String(localized: "Last picked") : String(localized: "Recent colour"),
                icon: Self.icon(color),
                score: max(0.3, 0.9 - Double(index) * 0.01),
                kind: .custom,
                actionTitle: String(localized: "Copy"),
                perform: { _ = controller.copy(color) },
                preview: { AnyView(ColorPreview(color: color, controller: controller)) }
            )
        }
    }

    nonisolated static func icon(_ color: RGBAColor) -> ResultIcon {
        .swatch(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }
}
