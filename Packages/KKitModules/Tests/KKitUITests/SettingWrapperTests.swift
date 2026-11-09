import KKitCore
import KKitUI
import SwiftUI
import Testing

@MainActor
struct KKitUITests {
    @Test func tokensFollowTheFourPointGrid() {
        for value in [KKSpacing.xs, KKSpacing.s, KKSpacing.m, KKSpacing.l, KKSpacing.xl] {
            #expect(value.truncatingRemainder(dividingBy: 4) == 0)
        }
    }

    @Test func settingWithoutEnvironmentUsesDefault() {
        let setting = Setting(SettingKey("intensity", default: 0.5))
        #expect(setting.wrappedValue == 0.5)
    }
}
