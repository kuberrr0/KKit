import KKitCore

/// Published by the Shelf while it runs, so other features can put things on it
/// without importing it ("Add to Shelf" after a screenshot, from Clipboard History):
///
/// ```swift
/// if let shelf = context.services.resolve((any ShelfServicing).self) {
///     try await shelf.add([.file(url)])
/// }
/// ```
@MainActor
public protocol ShelfServicing: AnyObject {
    var itemCount: Int { get }
    /// Adds items and shows the Shelf briefly in the Island.
    func add(_ items: [DroppedItem]) async throws
}
