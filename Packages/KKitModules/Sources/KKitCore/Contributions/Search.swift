import Foundation
import SwiftUI

/// What the user typed in the Floating Bar, as a provider sees it.
public struct SearchQuery: Sendable, Hashable {
    /// The text after the provider's prefix (if one was typed), without leading spaces.
    public var text: String
    /// `true` when the user typed this provider's prefix (`f `, `=`), so the provider
    /// should show everything it has, not just strong matches.
    public var isScoped: Bool

    public init(text: String, isScoped: Bool = false) {
        self.text = text
        self.isScoped = isScoped
    }

    /// `text` without surrounding whitespace.
    public var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isEmpty: Bool { trimmed.isEmpty }
}

/// A result's icon.
public enum ResultIcon: Sendable, Hashable, Codable {
    /// An SF Symbol.
    case symbol(String)
    /// The Finder icon of a file, folder or app.
    case file(URL)
    /// A short piece of text drawn as the icon ("=", "€").
    case glyph(String)
}

/// What a result is. The Floating Bar runs results by kind (opens files and URLs, runs
/// commands, copies text) unless the result has its own `perform`, and offers ⌘K
/// actions by kind (Reveal in Finder for files, Copy Link for URLs…). Results of every
/// kind but `.custom` can be added to Favourites and show up in Recent.
public enum ResultKind: Sendable, Hashable, Codable {
    case command(CommandID, argument: CommandArgument?)
    case application(URL)
    case file(URL)
    case url(URL)
    /// Copied to the clipboard (calculator answers).
    case text(String)
    /// Only the result's own `perform` knows what to do.
    case custom

    /// Can be saved to Favourites and Recent.
    public var isStorable: Bool { self != .custom }

    /// The file or app, for file actions.
    public var fileURL: URL? {
        switch self {
        case .application(let url), .file(let url): url
        default: nil
        }
    }
}

/// One row in the Floating Bar.
public struct SearchResult: Identifiable, Sendable {
    public typealias Perform = @MainActor @Sendable () async throws -> Void
    public typealias Preview = @MainActor @Sendable () -> AnyView

    /// Stable across queries ("app:com.apple.Safari"), so frecency, Favourites and
    /// Recent can find the same thing again.
    public var id: String
    public var title: String
    public var subtitle: String?
    public var icon: ResultIcon
    /// 0…1: how well this matches, by the provider's own measure (use `FuzzyMatch`).
    /// The host weights it per provider and adds frecency.
    public var score: Double
    public var kind: ResultKind
    /// Short trailing text: a shortcut ("⌃⌥N"), a state ("On"), "Application".
    public var accessory: String?
    /// What ↵ does, for the footer: "Open", "Run", "Copy". `nil` uses the kind's default.
    public var actionTitle: String?
    /// Listed after every other result whatever its score ("Search the web for …").
    public var isFallback: Bool
    /// Replaces the host's default action for `kind`.
    public var perform: Perform?
    /// Shown in the preview pane (Tab). `nil` uses the host's default preview.
    public var preview: Preview?

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        icon: ResultIcon,
        score: Double,
        kind: ResultKind,
        accessory: String? = nil,
        actionTitle: String? = nil,
        isFallback: Bool = false,
        perform: Perform? = nil,
        preview: Preview? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.score = score
        self.kind = kind
        self.accessory = accessory
        self.actionTitle = actionTitle
        self.isFallback = isFallback
        self.perform = perform
        self.preview = preview
    }
}

/// A source of Floating Bar results, contributed by a feature (`Feature.searchProviders`).
///
/// Return the same provider instances every time `searchProviders` is read. `results`
/// is called for each keystroke; earlier streams are cancelled when the query changes,
/// so check `Task.isCancelled` in slow work. Yield more than once to fill in slow
/// sources (yield what you have, then the rest).
@MainActor
public protocol SearchProvider: AnyObject {
    /// Unique within the feature: "files", "apps".
    var id: String { get }
    /// "Files", shown when scoped and in Settings › Floating Bar.
    var displayName: String { get }
    var symbol: String { get }
    /// Typing this first searches only this provider: "f ", "=", "/".
    var prefix: String? { get }
    /// Whether it's asked when no prefix is typed.
    var includeInRootSearch: Bool { get }
    func results(for query: SearchQuery) -> AsyncStream<[SearchResult]>
}

public extension SearchProvider {
    var prefix: String? { nil }
    var includeInRootSearch: Bool { true }
}

public extension AsyncStream where Element: Sendable {
    /// A stream with one value, for providers that answer straight away.
    static func single(_ value: Element) -> AsyncStream<Element> {
        AsyncStream { continuation in
            continuation.yield(value)
            continuation.finish()
        }
    }

    /// A stream with the one value `work` returns, for providers with slow work (an
    /// index to load, a file to read). The work is cancelled when the query changes.
    static func task(_ work: @escaping @MainActor @Sendable () async -> Element) -> AsyncStream<Element> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                let value = await work()
                if !Task.isCancelled {
                    continuation.yield(value)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// A ⌘K action on Floating Bar results (Reveal in Finder, Add to Shelf…). Features
/// contribute them through `Feature.resultActions`; the host adds the built-in ones.
public struct ResultAction: Identifiable, Sendable {
    public typealias Perform = @MainActor @Sendable (SearchResult) async throws -> Void

    /// Unique: "<featureID>.<verb>", e.g. "shelf.add".
    public let id: String
    public var title: String
    public var symbol: String
    /// Hide the Floating Bar before running (most actions); `false` keeps it open
    /// (Add to Favourites).
    public var dismissesBar: Bool
    public var appliesTo: @MainActor @Sendable (SearchResult) -> Bool
    public var perform: Perform

    public init(
        id: String,
        title: String,
        symbol: String,
        dismissesBar: Bool = true,
        appliesTo: @escaping @MainActor @Sendable (SearchResult) -> Bool = { _ in true },
        perform: @escaping Perform
    ) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.dismissesBar = dismissesBar
        self.appliesTo = appliesTo
        self.perform = perform
    }
}

/// What a Floating Bar mode's view can ask of the host.
@MainActor
public struct FloatingBarModeContext {
    /// Text typed after the mode's prefix, or passed when the mode was opened.
    public let initialText: String
    /// Hides the Floating Bar.
    public let dismiss: @MainActor () -> Void
    /// Goes back to search.
    public let exit: @MainActor () -> Void
    /// Opens the owning feature's Settings page.
    public let openSettings: @MainActor () -> Void

    public init(
        initialText: String,
        dismiss: @escaping @MainActor () -> Void,
        exit: @escaping @MainActor () -> Void,
        openSettings: @escaping @MainActor () -> Void
    ) {
        self.initialText = initialText
        self.dismiss = dismiss
        self.exit = exit
        self.openSettings = openSettings
    }
}

/// A feature taking over the Floating Bar's content area (Quick Note's editor). It opens
/// when the user types `prefix`, or when the feature calls `context.floatingBar.showMode`.
/// The mode's view handles its own keys; ⎋ should call `exit`.
public struct FloatingBarMode: Identifiable {
    /// Unique within the feature: "editor".
    public let id: String
    public var title: String
    public var symbol: String
    /// "n ". `nil` for modes opened only by the feature.
    public var prefix: String?
    /// The content area's height.
    public var height: CGFloat
    public let makeView: @MainActor (FloatingBarModeContext) -> AnyView

    public init<Content: View>(
        id: String,
        title: String,
        symbol: String,
        prefix: String? = nil,
        height: CGFloat = 280,
        @ViewBuilder content: @escaping @MainActor (FloatingBarModeContext) -> Content
    ) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.prefix = prefix
        self.height = height
        self.makeView = { AnyView(content($0)) }
    }
}
