import KKitCore

/// A device in an auto-switch priority list. The name is remembered so the list still
/// reads well while the device is disconnected.
struct PriorityDevice: Codable, Sendable, Hashable, Identifiable {
    var uid: String
    var name: String

    var id: String { uid }
}

enum VolumeSettings {
    /// One volume step as a fraction: 0.0625 is macOS's 1/16.
    static let step = SettingKey("step", default: 0.0625)
    /// The highest output volume KKit allows, 0.1…1. Changes above it are pulled back.
    static let volumeLimit = SettingKey("volumeLimit", default: 1.0)
    /// Island HUD for changes made through KKit (commands, scrolling on the Island).
    static let showHUD = SettingKey("showHUD", default: true)
    /// Island HUD for changes made elsewhere (Control Center, other apps). macOS shows
    /// its own HUD for those too, so this is off by default.
    static let hudForSystemChanges = SettingKey("hudForSystemChanges", default: false)
    /// KKit handles the volume keys: its step size and limit, and the Island HUD instead
    /// of macOS's. Needs Accessibility (the shared input tap).
    static let takeOverVolumeKeys = SettingKey("takeOverVolumeKeys", default: true)
    /// Hold to unmute the microphone; it's muted the rest of the time.
    static let pushToTalkKey = SettingKey<Shortcut?>("pushToTalkKey", default: nil)
    /// Hold to mute the microphone.
    static let pushToMuteKey = SettingKey<Shortcut?>("pushToMuteKey", default: nil)
    /// Per-app volumes by bundle id, 0…1. Apps not listed play at full volume.
    static let appVolumes = SettingKey("appVolumes", default: [String: Double]())
    /// Scroll on the Island to change the volume; ⌥ for fine steps.
    static let scrollOnIsland = SettingKey("scrollOnIsland", default: true)
    static let soundOnMicMute = SettingKey("soundOnMicMute", default: false)
    // Auto-switch
    static let autoSwitchOutput = SettingKey("autoSwitchOutput", default: false)
    static let outputPriority = SettingKey("outputPriority", default: [PriorityDevice]())
    static let autoSwitchInput = SettingKey("autoSwitchInput", default: false)
    static let inputPriority = SettingKey("inputPriority", default: [PriorityDevice]())
}
