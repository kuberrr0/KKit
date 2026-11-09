import Foundation

/// A `kkit://` link (ARCHITECTURE.md §5).
///
/// - `kkit://run/nightShift.setIntensity?value=150` runs a command with an argument
///   (parsed like typed text: `150`, `25m`, `tea`).
/// - `kkit://search?q=night` opens the Floating Bar with a query.
public enum KKitLink: Sendable, Hashable {
    case run(CommandID, value: String?)
    case search(String?)

    public static let scheme = "kkit"

    public init?(_ url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        let items = components.queryItems ?? []
        func item(_ names: String...) -> String? {
            items.first { names.contains($0.name) }?.value
        }
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        switch components.host?.lowercased() {
        case "run":
            let raw = path.isEmpty ? (item("command", "id") ?? "") : path
            let id = CommandID(raw)
            guard id.featureID.isValid || id.featureID == .app, !id.verb.isEmpty else { return nil }
            self = .run(id, value: item("value", "arg", "argument"))
        case "search", "bar":
            let query = item("q", "query") ?? (path.isEmpty ? nil : path)
            self = .search(query)
        default:
            return nil
        }
    }

    /// The link's URL, for "Copy Link" and docs.
    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .run(let id, let value):
            components.host = "run"
            components.path = "/" + id.rawValue
            if let value {
                components.queryItems = [URLQueryItem(name: "value", value: value)]
            }
        case .search(let query):
            components.host = "search"
            if let query {
                components.queryItems = [URLQueryItem(name: "q", value: query)]
            }
        }
        return components.url ?? URL(string: "kkit://")!
    }
}
