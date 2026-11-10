import KKitCore

enum NowPlayingSettings {
    /// Artwork and moving bars either side of the notch while something plays.
    static let showCompact = SettingKey("showCompact", default: true)
    /// Clicking the artwork on the Island page brings the playing app to the front.
    static let clickArtworkOpensApp = SettingKey("clickArtworkOpensApp", default: true)
}
