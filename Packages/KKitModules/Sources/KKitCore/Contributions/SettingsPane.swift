import SwiftUI

/// A feature's page content in the Settings window. The Settings host adds the
/// header (name, on/off switch, permissions) and the feature's shortcuts around it,
/// and puts the feature's `FeatureSettings` in the environment for `@Setting`.
public struct SettingsPane {
    public let makeView: @MainActor () -> AnyView

    public init<Content: View>(@ViewBuilder _ content: @escaping @MainActor () -> Content) {
        self.makeView = { AnyView(content()) }
    }
}
