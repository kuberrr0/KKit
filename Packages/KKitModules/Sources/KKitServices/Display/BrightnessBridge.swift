import CoreGraphics
import Darwin
import Foundation

/// Built-in display brightness. macOS has no public API for it, so this loads Apple's
/// private DisplayServices framework at run time (falling back to CoreDisplay). If
/// neither is there, `isAvailable` is `false` and KKit leaves the brightness keys to macOS.
final class BrightnessBridge {
    private typealias GetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (UInt32, Float) -> Int32
    private typealias CanChange = @convention(c) (UInt32) -> Bool
    private typealias Changed = @convention(c) (UInt32, Double) -> Void
    private typealias CoreDisplayGet = @convention(c) (UInt32) -> Double
    private typealias CoreDisplaySet = @convention(c) (UInt32, Double) -> Void

    private let getBrightness: GetBrightness?
    private let setBrightness: SetBrightness?
    private let canChange: CanChange?
    private let changed: Changed?
    private let coreDisplayGet: CoreDisplayGet?
    private let coreDisplaySet: CoreDisplaySet?

    init() {
        let displayServices = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
        let coreDisplay = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY)
        func load<T>(_ handle: UnsafeMutableRawPointer?, _ name: String, as type: T.Type) -> T? {
            guard let handle, let symbol = dlsym(handle, name) else { return nil }
            return unsafeBitCast(symbol, to: type)
        }
        getBrightness = load(displayServices, "DisplayServicesGetBrightness", as: GetBrightness.self)
        setBrightness = load(displayServices, "DisplayServicesSetBrightness", as: SetBrightness.self)
        canChange = load(displayServices, "DisplayServicesCanChangeBrightness", as: CanChange.self)
        changed = load(displayServices, "DisplayServicesBrightnessChanged", as: Changed.self)
        coreDisplayGet = load(coreDisplay, "CoreDisplay_Display_GetUserBrightness", as: CoreDisplayGet.self)
        coreDisplaySet = load(coreDisplay, "CoreDisplay_Display_SetUserBrightness", as: CoreDisplaySet.self)
    }

    var isAvailable: Bool { getBrightness != nil || coreDisplayGet != nil }

    func brightness(of display: UInt32) -> Double? {
        if let canChange, !canChange(display) {
            return nil
        }
        if let getBrightness {
            var value: Float = 0
            if getBrightness(display, &value) == 0 {
                return Double(value)
            }
        }
        // CoreDisplay only knows built-in panels; elsewhere it returns garbage.
        if let coreDisplayGet, CGDisplayIsBuiltin(display) != 0 {
            return min(max(coreDisplayGet(display), 0), 1)
        }
        return nil
    }

    func setBrightness(_ value: Double, for display: UInt32) {
        let clamped = min(max(value, 0), 1)
        if let setBrightness, setBrightness(display, Float(clamped)) == 0 {
            // Tells Control Center and System Settings to update their sliders.
            changed?(display, clamped)
            return
        }
        if let coreDisplaySet, CGDisplayIsBuiltin(display) != 0 {
            coreDisplaySet(display, clamped)
        }
    }
}
