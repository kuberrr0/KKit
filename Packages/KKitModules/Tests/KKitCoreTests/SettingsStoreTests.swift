import Foundation
import KKitCore
import Testing

@MainActor
struct SettingsStoreTests {
    enum Mode: String, Codable, Sendable {
        case warm, amber
    }

    enum Keys {
        static let intensity = SettingKey("intensity", default: 0.7)
        static let mode = SettingKey("mode", default: Mode.warm)
    }

    let store: SettingsStore

    init() {
        let suite = "KKitTests-\(UUID().uuidString)"
        store = SettingsStore(defaults: UserDefaults(suiteName: suite)!)
    }

    @Test func readsDefaultsAndWritesNamespacedKeys() {
        let settings = FeatureSettings(featureID: "nightShift", store: store)
        #expect(settings[Keys.intensity] == 0.7)

        settings[Keys.intensity] = 1.4
        settings[Keys.mode] = .amber

        #expect(settings[Keys.intensity] == 1.4)
        #expect(settings[Keys.mode] == .amber)
        #expect(store.hasValue(for: "nightShift.intensity"))
        #expect(store.value(for: "nightShift.intensity", default: 0.0) == 1.4)
    }

    @Test func featuresDontShareKeys() {
        let a = FeatureSettings(featureID: "a", store: store)
        let b = FeatureSettings(featureID: "b", store: store)
        a[Keys.intensity] = 2
        #expect(b[Keys.intensity] == 0.7)
    }

    @Test func resetReturnsToDefault() {
        let settings = FeatureSettings(featureID: "nightShift", store: store)
        settings[Keys.intensity] = 1.1
        settings.reset(Keys.intensity)
        #expect(settings[Keys.intensity] == 0.7)
        #expect(!store.hasValue(for: "nightShift.intensity"))
    }

    @Test func changesStreamsCurrentThenNewValues() async {
        let settings = FeatureSettings(featureID: "nightShift", store: store)
        var values: [Double] = []
        for await value in settings.changes(of: Keys.intensity) {
            values.append(value)
            if values.count == 1 {
                settings[Keys.intensity] = 1.2
            } else {
                break
            }
        }
        #expect(values == [0.7, 1.2])
    }
}
