import Foundation
import KKitCore
import SwiftUI

/// `tr hola` in the Floating Bar: one result that opens the translation card.
@MainActor
final class TranslateProvider: SearchProvider {
    let id = "translate"
    let displayName = String(localized: "Translate")
    let symbol = "translate"
    let prefix: String? = "tr "
    let includeInRootSearch = false

    private let controller: ScreenToolsController

    init(controller: ScreenToolsController) {
        self.controller = controller
    }

    func results(for query: SearchQuery) -> AsyncStream<[SearchResult]> {
        .single(Self.results(for: query, target: controller.settings[ScreenToolsSettings.translateTarget], controller: controller))
    }

    static func results(for query: SearchQuery, target: String, controller: ScreenToolsController) -> [SearchResult] {
        let text = query.trimmed
        guard !text.isEmpty else { return [] }
        let language = TranslationLanguage(id: target).name
        return [
            SearchResult(
                id: "translate:text",
                title: String(localized: "Translate “\(text)”"),
                subtitle: String(localized: "Into \(language), on this Mac"),
                icon: .symbol("translate"),
                score: 1,
                kind: .custom,
                actionTitle: String(localized: "Translate"),
                perform: { [weak controller] in
                    controller?.showTranslation(of: text, near: nil)
                }
            ),
        ]
    }
}
