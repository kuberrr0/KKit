import Foundation
import KKitCore
import KKitServicesAPI

/// Records what features ask of the Floating Bar.
@MainActor
public final class FakeFloatingBarService: FloatingBarService {
    public private(set) var isVisible = false
    public private(set) var shownQueries: [String?] = []
    public private(set) var shownModes: [(owner: FeatureID, mode: String, text: String?)] = []

    public init() {}

    public func show(query: String?) {
        isVisible = true
        shownQueries.append(query)
    }

    public func showMode(_ modeID: String, owner: FeatureID, text: String?) {
        isVisible = true
        shownModes.append((owner, modeID, text))
    }

    public func hide() {
        isVisible = false
    }
}

/// Spotlight with a fixed list of files: returns those whose name contains the text.
@MainActor
public final class FakeFileSearchService: FileSearchService {
    public var files: [FileSearchHit] = []
    public private(set) var searches: [String] = []

    public init() {}

    public func search(_ text: String, limit: Int) -> AsyncStream<[FileSearchHit]> {
        searches.append(text)
        let matches = files.filter { $0.name.localizedCaseInsensitiveContains(text) }
        return .single(Array(matches.prefix(limit)))
    }
}
