// swift-tools-version: 6.0
// All of KKit's modules. One target per module so each can only import what it
// declares (ARCHITECTURE.md §2–3). Features go in Sources/Features/Feature<Name>/.

import PackageDescription

let package = Package(
    name: "KKitModules",
    platforms: [.macOS("14.2")],
    products: [
        .library(name: "KKitCore", targets: ["KKitCore"]),
        .library(name: "KKitUI", targets: ["KKitUI"]),
        .library(name: "KKitServicesAPI", targets: ["KKitServicesAPI"]),
        .library(name: "KKitServices", targets: ["KKitServices"]),
        .library(name: "KKitServicesTesting", targets: ["KKitServicesTesting"]),
        .library(name: "KKitHosts", targets: ["KKitHosts"]),
        .library(name: "FeaturePower", targets: ["FeaturePower"]),
        .library(name: "FeatureStats", targets: ["FeatureStats"]),
        .library(name: "FeatureNightShift", targets: ["FeatureNightShift"]),
        .library(name: "FeatureVolume", targets: ["FeatureVolume"]),
        .library(name: "FeaturePrivacyIndicator", targets: ["FeaturePrivacyIndicator"]),
        .library(name: "FeatureTimer", targets: ["FeatureTimer"]),
        .library(name: "FeatureToggles", targets: ["FeatureToggles"]),
        .library(name: "FeatureSearch", targets: ["FeatureSearch"]),
        .library(name: "FeatureCalculator", targets: ["FeatureCalculator"]),
        .library(name: "FeatureQuickNote", targets: ["FeatureQuickNote"]),
        .library(name: "FeatureClipboard", targets: ["FeatureClipboard"]),
        .library(name: "FeatureScreenTools", targets: ["FeatureScreenTools"]),
        .library(name: "FeatureShelf", targets: ["FeatureShelf"]),
        .library(name: "FeatureKeyboard", targets: ["FeatureKeyboard"]),
        .library(name: "FeatureWindows", targets: ["FeatureWindows"]),
        .library(name: "FeatureCleanMode", targets: ["FeatureCleanMode"]),
        .library(name: "FeatureBrightness", targets: ["FeatureBrightness"]),
        .library(name: "FeatureNowPlaying", targets: ["FeatureNowPlaying"]),
    ],
    dependencies: [
        // 2.x: 3.x needs swift-tools 6.2 (Xcode 26).
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", .upToNextMajor(from: "2.4.0")),
    ],
    targets: [
        // ── Foundation ────────────────────────────────────────────────────────
        .target(name: "KKitCore"),
        .target(name: "KKitUI", dependencies: ["KKitCore"]),

        // ── Services: protocols (what features see) and implementations ──────
        .target(name: "KKitServicesAPI", dependencies: ["KKitCore"]),
        .target(
            name: "KKitServices",
            dependencies: ["KKitCore", "KKitUI", "KKitServicesAPI", "KeyboardShortcuts"]
        ),
        // The fakes use the real SQLite database so feature tests run real SQL.
        .target(name: "KKitServicesTesting", dependencies: ["KKitCore", "KKitServicesAPI", "KKitServices"]),

        // ── Hosts: the shared surfaces (menu bar, Settings, Island, Floating Bar)
        .target(name: "KKitHosts", dependencies: ["KKitCore", "KKitUI", "KKitServicesAPI"]),

        // ── Features (depend on KKitCore, KKitUI, KKitServicesAPI only) ───────
        .feature("FeaturePower"),
        .feature("FeatureStats"),
        .feature("FeatureNightShift"),
        .feature("FeatureVolume"),
        .feature("FeaturePrivacyIndicator"),
        .feature("FeatureTimer"),
        .feature("FeatureToggles"),
        .feature("FeatureSearch"),
        .feature("FeatureCalculator"),
        .feature("FeatureQuickNote"),
        .feature("FeatureClipboard"),
        .feature("FeatureScreenTools"),
        .feature("FeatureShelf"),
        .feature("FeatureKeyboard"),
        .feature("FeatureWindows"),
        .feature("FeatureCleanMode"),
        .feature("FeatureBrightness"),
        .feature("FeatureNowPlaying"),

        // ── Tests ─────────────────────────────────────────────────────────────
        .testTarget(name: "KKitCoreTests", dependencies: ["KKitCore", "KKitServicesTesting"]),
        .testTarget(name: "KKitUITests", dependencies: ["KKitCore", "KKitUI"]),
        .testTarget(
            name: "KKitServicesTests",
            dependencies: ["KKitCore", "KKitServicesAPI", "KKitServices", "KKitServicesTesting"]
        ),
        .testTarget(
            name: "KKitHostsTests",
            dependencies: ["KKitCore", "KKitServicesAPI", "KKitHosts", "KKitServicesTesting"]
        ),
        .featureTests("FeaturePower"),
        .featureTests("FeatureStats"),
        .featureTests("FeatureNightShift"),
        .featureTests("FeatureVolume"),
        .featureTests("FeaturePrivacyIndicator"),
        .featureTests("FeatureTimer"),
        .featureTests("FeatureToggles"),
        .featureTests("FeatureSearch"),
        .featureTests("FeatureCalculator"),
        .featureTests("FeatureQuickNote"),
        .featureTests("FeatureClipboard"),
        .featureTests("FeatureScreenTools"),
        .featureTests("FeatureShelf"),
        .featureTests("FeatureKeyboard"),
        .featureTests("FeatureWindows"),
        .featureTests("FeatureCleanMode"),
        .featureTests("FeatureBrightness"),
        .featureTests("FeatureNowPlaying"),
    ]
)

// A feature target: depends on KKitCore, KKitUI and KKitServicesAPI only.
extension Target {
    static func feature(_ name: String) -> Target {
        .target(
            name: name,
            dependencies: ["KKitCore", "KKitUI", "KKitServicesAPI"],
            path: "Sources/Features/\(name)",
            exclude: ["README.md"]
        )
    }

    static func featureTests(_ name: String) -> Target {
        .testTarget(
            name: "\(name)Tests",
            dependencies: [.target(name: name), "KKitCore", "KKitServicesAPI", "KKitServicesTesting"],
            path: "Tests/Features/\(name)Tests"
        )
    }
}
