import FeatureBrightness
import FeatureCalculator
import FeatureCleanMode
import FeatureColorPicker
import FeatureClipboard
import FeatureKeyboard
import FeatureNightShift
import FeaturePower
import FeaturePrivacyIndicator
import FeatureQuickNote
import FeatureScreenTools
import FeatureSearch
import FeatureShelf
import FeatureStats
import FeatureTimer
import FeatureToggles
import FeatureVolume
import FeatureWindows
import KKitCore

/// The one list of every feature type, in the order they appear in Settings.
/// Add new features here (ARCHITECTURE.md §11).
enum FeatureCatalog {
    @MainActor
    static let all: [any Feature.Type] = [
        VolumeFeature.self,
        BrightnessFeature.self,
        StatsFeature.self,
        PowerFeature.self,
        NightShiftFeature.self,
        TogglesFeature.self,
        PrivacyIndicatorFeature.self,
        TimerFeature.self,
        SearchFeature.self,
        CalculatorFeature.self,
        QuickNoteFeature.self,
        ClipboardFeature.self,
        ScreenToolsFeature.self,
        ColorPickerFeature.self,
        ShelfFeature.self,
        KeyboardFeature.self,
        WindowsFeature.self,
        CleanModeFeature.self,
    ]
}
