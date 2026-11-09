import Foundation

/// A file or folder Spotlight found.
public struct FileSearchHit: Sendable, Hashable, Identifiable {
    public var url: URL
    /// The file name as Finder shows it.
    public var name: String
    public var isDirectory: Bool
    public var lastUsed: Date?

    public var id: URL { url }

    public init(url: URL, name: String, isDirectory: Bool, lastUsed: Date? = nil) {
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.lastUsed = lastUsed
    }
}

/// File name search with Spotlight (`NSMetadataQuery`). No permission is needed;
/// Spotlight only returns what the user can read.
@MainActor
public protocol FileSearchService: AnyObject {
    /// Files and folders in the home folder whose name contains `text`, most recently
    /// used first. Yields as Spotlight gathers and finishes when it's done; cancel the
    /// consuming task to stop the query early.
    func search(_ text: String, limit: Int) -> AsyncStream<[FileSearchHit]>
}
