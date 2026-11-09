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
        // Features: add `.library(name: "Feature<Name>", targets: ["Feature<Name>"])`.
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
        .target(name: "KKitServicesTesting", dependencies: ["KKitCore", "KKitServicesAPI"]),

        // ── Hosts: the shared surfaces (menu bar, Settings, later Island, Floating Bar)
        .target(name: "KKitHosts", dependencies: ["KKitCore", "KKitUI", "KKitServicesAPI"]),

        // ── Features (depend on KKitCore, KKitUI, KKitServicesAPI only) ───────
        // .target(
        //     name: "FeatureTimer",
        //     dependencies: ["KKitCore", "KKitUI", "KKitServicesAPI"],
        //     path: "Sources/Features/FeatureTimer"
        // ),

        // ── Tests ─────────────────────────────────────────────────────────────
        .testTarget(name: "KKitCoreTests", dependencies: ["KKitCore", "KKitServicesTesting"]),
        .testTarget(name: "KKitUITests", dependencies: ["KKitCore", "KKitUI"]),
        .testTarget(
            name: "KKitServicesTests",
            dependencies: ["KKitCore", "KKitServicesAPI", "KKitServices", "KKitServicesTesting"]
        ),
    ]
)
