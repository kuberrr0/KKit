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

/// File name search with Spotlight (`NSMetadataQuery`), through the whole home folder.
///
/// Spotlight only returns what KKit itself may read, so nothing inside Desktop,
/// Documents or Downloads shows up until macOS has given KKit access to them. The first
/// search asks (one system prompt per folder); `blockedFolders` lists those still denied.
@MainActor
public protocol FileSearchService: AnyObject {
    /// Files and folders in the home folder whose name contains every word of `text`:
    /// exact names first, then names that start with it, then the rest; shallower paths
    /// and recently used files first within each. The standard home folders (Downloads,
    /// Documents…) always match by name. Yields as Spotlight gathers and finishes when
    /// it's done; cancel the consuming task to stop the query early.
    func search(_ text: String, limit: Int) -> AsyncStream<[FileSearchHit]>

    /// Names of the protected folders (Desktop, Documents, Downloads) KKit can't read,
    /// so their contents are missing from results. Known after the first search.
    var blockedFolders: [String] { get }
}
