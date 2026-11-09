import KKitCore

/// The one list of every feature type, in the order they appear in Settings.
/// Add new features here (ARCHITECTURE.md §11).
enum FeatureCatalog {
    @MainActor
    static let all: [any Feature.Type] = [
        // PowerFeature.self, VolumeFeature.self, …
    ]
}
