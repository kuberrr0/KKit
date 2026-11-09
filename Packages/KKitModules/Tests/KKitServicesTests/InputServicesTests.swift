import Foundation
import KKitCore
import KKitServicesAPI
import Testing
@testable import KKitServices

struct MediaKeyEventTests {
    @Test func decodesData1() {
        // Volume up (0) pressed: state 0xA in bits 8–15.
        let down = MediaKeyEvent(subtype: 8, data1: (0 << 16) | (0xA << 8))
        #expect(down == MediaKeyEvent(key: .volumeUp, isDown: true, isRepeat: false))
        // Mute (7) released.
        let up = MediaKeyEvent(subtype: 8, data1: (7 << 16) | (0xB << 8))
        #expect(up == MediaKeyEvent(key: .mute, isDown: false, isRepeat: false))
        // Brightness down (3) held: the repeat bit.
        let repeated = MediaKeyEvent(subtype: 8, data1: (3 << 16) | (0xA << 8) | 1)
        #expect(repeated == MediaKeyEvent(key: .brightnessDown, isDown: true, isRepeat: true))
    }

    @Test func ignoresOtherEvents() {
        #expect(MediaKeyEvent(subtype: 7, data1: 0xA00) == nil)
        #expect(MediaKeyEvent(subtype: 8, data1: (99 << 16) | (0xA << 8)) == nil)
        #expect(MediaKeyEvent(subtype: 8, data1: 0) == nil)
    }
}

struct HIDKeyRemapperTests {
    @Test func parsesHidutilOutput() {
        let output = """
        (
                {
                HIDKeyboardModifierMappingDst = 30064771181;
                HIDKeyboardModifierMappingSrc = 30064771129;
            },
                {
                HIDKeyboardModifierMappingDst = 0x700000029;
                HIDKeyboardModifierMappingSrc = 0x700000035;
            }
        )
        """
        let mappings = HIDKeyRemapper.parse(output)
        #expect(mappings == [
            .init(source: CapsLockRemap.capsLockUsage, destination: CapsLockRemap.f18.hidUsage),
            .init(source: 0x7_0000_0035, destination: 0x7_0000_0029),
        ])
        #expect(HIDKeyRemapper.parse("(null)").isEmpty)
    }

    @Test func writesJSON() {
        let json = HIDKeyRemapper.json([.init(source: 1, destination: 2)])
        #expect(json == #"{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":1,"HIDKeyboardModifierMappingDst":2}]}"#)
        #expect(HIDKeyRemapper.json([]) == #"{"UserKeyMapping":[]}"#)
    }
}

struct MenuShortcutTextTests {
    @Test func modifierMask() {
        #expect(AXMenuEngine.shortcutText(character: "s", modifiers: 0) == "⌘S")
        #expect(AXMenuEngine.shortcutText(character: "s", modifiers: 1) == "⇧⌘S")
        #expect(AXMenuEngine.shortcutText(character: "f", modifiers: 4) == "⌃⌘F")
        #expect(AXMenuEngine.shortcutText(character: "x", modifiers: 2 | 8) == "⌥X")
    }
}
