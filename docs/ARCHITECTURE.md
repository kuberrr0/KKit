# KKit — Architecture & Framework Plan

This doc explains how KKit is put together: the tech stack, how the code is split into
modules, the `Feature` protocol every feature implements, the shared services they all
use, and the exact steps to add a new feature.

> The short version: **features are plug-ins**. Each feature lives in its own Swift
> package target, depends only on `KKitCore` (protocols), `KKitUI` (components) and the
> service *protocols* it needs, and plugs into shared **hosts** (Island, Floating Bar,
> menu bar, Settings) by returning **contributions**. Features never import each other.

---

## 1. Tech stack and platform decisions

| Decision | Choice | Why |
|---|---|---|
| Language | Swift 6, strict concurrency | Safe threading for a lot of background sampling and event handling |
| UI | SwiftUI for all views; AppKit for windows/panels, event taps, status items | SwiftUI can't do borderless non-activating panels, notch placement or event taps on its own |
| State | `@Observable` (Observation framework) | Simple, fast, works across SwiftUI and AppKit |
| Minimum macOS | **14.2 Sonoma** | Process taps (per-app volume), `SCScreenshotManager`, Observation. Features needing newer APIs check availability (e.g. `SCRecordingOutput` 15, Foundation Models 26) |
| App type | Agent app (`LSUIElement = YES`), optional Dock icon | Utility apps live in the menu bar |
| Distribution | **Outside the Mac App Store**: Developer ID signed, notarized, auto-updates with Sparkle | The App Store sandbox doesn't allow global event taps, Accessibility control of other apps, gamma tables across displays, or private frameworks |
| Project file | **XcodeGen** (`project.yml`) generates the `.xcodeproj` | `project.pbxproj` is painful to edit by hand or by Claude; `project.yml` is short and diff-friendly. The generated project is git-ignored |
| Code layout | One local Swift package, `Packages/KKitModules`, with a target per module | Enforces boundaries (a feature can only import what it declares), fast incremental builds, `swift test` per module |
| Dependencies | [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (hotkey recorder + Carbon hotkeys), [Sparkle](https://sparkle-project.org) (updates), [GRDB](https://github.com/groue/GRDB.swift) (SQLite with full-text search for clipboard history) | Small, well-maintained, each replaces a lot of fiddly code |
| Launch at login | `SMAppService.mainApp` | Built-in since macOS 13 |
| Optional helper | Privileged helper via `SMAppService.daemon` | Only for advanced features (closed-lid awake, battery charge limit). Not in v1 |
| Logging | `os.Logger`, one subsystem, one category per feature | Shows up in Console.app, filterable per feature |
| CI | GitHub Actions on `macos-latest`: `xcodegen` → `xcodebuild build test` | Claude works from a Linux container and can't build macOS apps locally, so CI is how changes get compiled and tested |

---

## 2. Layers

```
┌──────────────────────────────────────────────────────────────────────────┐
│ App target (KKit.app)                                                    │
│   KKitApp · AppDelegate · FeatureCatalog (list of all features) · plist │
└───────────────┬──────────────────────────────────────────────────────────┘
                │ composes
┌───────────────▼──────────────────────────────────────────────────────────┐
│ Features  (one target each; never import each other)                     │
│  Volume · Stats · Power · NightShift · ScreenTools · Clipboard · Shelf   │
│  Keyboard · QuickNote · Toggles · …                                      │
└───────┬────────────────────────────┬─────────────────────────────────────┘
        │ contribute to              │ call
┌───────▼──────────────────┐  ┌──────▼──────────────────────────────────────┐
│ Hosts (shared surfaces)  │  │ Services (shared system capabilities)       │
│  IslandHost              │  │  Permissions · Hotkeys · InputTap · Overlay │
│  FloatingBarHost         │  │  Audio · Display · Power · SystemInfo       │
│  MenuBarHost             │  │  Pasteboard · ScreenCapture · Accessibility │
│  SettingsHost            │  │  Storage · Notifications · NowPlaying       │
│  OnboardingHost          │  │  FileAccess · Location/Solar                │
└───────┬──────────────────┘  └──────┬──────────────────────────────────────┘
        │                            │
┌───────▼────────────────────────────▼─────────────────────────────────────┐
│ KKitUI   design tokens · components (rows, tiles, HUD, forms, panels)    │
├──────────────────────────────────────────────────────────────────────────┤
│ KKitCore Feature protocol · Manifest · Contributions · Commands ·        │
│          SettingsStore · EventBus · ServiceRegistry · FeatureManager     │
└──────────────────────────────────────────────────────────────────────────┘
```

Rules:

- **KKitCore** has no UI and no system-API code: only protocols, value types, the
  feature manager, settings and the event bus. Everything depends on it.
- **Services** wrap one macOS capability each, behind a protocol in `KKitServicesAPI`
  with the implementation in `KKitServices`. Features depend on the API target only, so
  tests can inject fakes.
- **Hosts** own the shared windows. They read contributions from all running features.
- **Features** depend on `KKitCore`, `KKitUI`, `KKitServicesAPI`, and nothing else.
  The Island and Floating Bar themselves are hosts, so even they are not features you
  import.

---

## 3. Repository structure

```
KKit/
├── project.yml                     # XcodeGen spec → KKit.xcodeproj (git-ignored)
├── App/
│   ├── KKitApp.swift               # @main, sets up AppDelegate
│   ├── AppDelegate.swift           # boots ServiceContainer, Hosts, FeatureManager
│   ├── FeatureCatalog.swift        # the one list of every feature type
│   ├── Info.plist                  # LSUIElement, usage descriptions
│   └── KKit.entitlements           # hardened runtime; no sandbox
├── Packages/KKitModules/
│   ├── Package.swift
│   ├── Sources/
│   │   ├── KKitCore/
│   │   │   ├── Feature.swift            # Feature protocol + lifecycle
│   │   │   ├── FeatureManifest.swift
│   │   │   ├── FeatureContext.swift
│   │   │   ├── FeatureManager.swift     # enable/disable/start/stop, state machine
│   │   │   ├── Contributions/           # Command, QuickToggle, SearchProvider,
│   │   │   │                            # SettingsPane, MenuBarItem, ResultAction…
│   │   │   ├── Commands/CommandRegistry.swift
│   │   │   ├── Settings/                # SettingKey, SettingsStore, @Setting
│   │   │   ├── Events/EventBus.swift    # typed AppEvent stream
│   │   │   └── Services/ServiceRegistry.swift
│   │   ├── KKitUI/
│   │   │   ├── Tokens.swift             # spacing, radii, motion
│   │   │   ├── Components/              # KKRow, KKTile, KKSlider, KKHUD, KKForm…
│   │   │   └── Panels/                  # KKPanel (NSPanel subclass helpers)
│   │   ├── KKitServicesAPI/             # protocols only: AudioService, …
│   │   ├── KKitServices/                # implementations: CoreAudioService, …
│   │   ├── KKitHosts/
│   │   │   ├── Island/                  # IslandHost, IslandWindow, layouts
│   │   │   ├── FloatingBar/             # panel, query engine, ranking, favourites
│   │   │   ├── MenuBar/                 # status item + popover with toggle grid
│   │   │   ├── Settings/                # window, sidebar, shortcuts table
│   │   │   └── Onboarding/
│   │   └── Features/
│   │       ├── FeatureVolume/           # volume, devices, per-app mixer, mic mute
│   │       ├── FeatureStats/
│   │       ├── FeaturePower/
│   │       ├── FeatureNightShift/
│   │       ├── FeatureScreenTools/
│   │       ├── FeatureClipboard/
│   │       ├── FeatureShelf/
│   │       ├── FeatureKeyboard/
│   │       ├── FeatureQuickNote/
│   │       ├── FeatureSearch/           # apps / files / web / System Settings
│   │       │                            # providers for the Floating Bar
│   │       ├── FeatureToggles/          # dark mode, hidden files, Wi-Fi, …
│   │       ├── FeatureWindows/          # snapping, modifier+mouse move/resize, layouts
│   │       ├── FeatureMenuBarManager/
│   │       ├── FeaturePrivacyIndicator/ # mic/camera in use
│   │       ├── FeatureTimer/
│   │       ├── FeatureCalculator/
│   │       └── FeatureCleanMode/
│   └── Tests/                           # one test target per module
├── Helper/                              # (later) privileged helper
├── docs/
│   ├── DESIGN.md
│   ├── ARCHITECTURE.md
│   └── ROADMAP.md
└── CLAUDE.md                            # conventions + "add a feature" recipe
```

Each feature folder looks the same:

```
FeatureNightShift/
├── NightShiftFeature.swift     # the Feature: manifest, start/stop, contributions
├── NightShiftSettings.swift    # SettingKey definitions
├── NightShiftController.swift  # the logic (an @Observable model or an actor)
├── Views/
│   ├── NightShiftSettingsPane.swift
│   └── NightShiftTile.swift
└── README.md                   # what it does, permissions, APIs, known limits
```

---

## 4. The Feature protocol

### 4.1 Manifest

Static metadata, readable without starting the feature (used by onboarding, Settings,
and permission checks).

```swift
public struct FeatureID: Hashable, Sendable, ExpressibleByStringLiteral { … }   // "nightShift"

public struct FeatureManifest: Sendable {
    public var id: FeatureID
    public var name: String                     // "Night Shift"
    public var symbol: String                   // SF Symbol: "moon.stars"
    public var summary: String                  // one sentence for onboarding/settings
    public var category: FeatureCategory        // .system, .capture, .productivity, .display …
    public var requiredPermissions: Set<Permission>   // can't run without these
    public var optionalPermissions: Set<Permission>   // unlock extra abilities
    public var enabledByDefault: Bool
    public var minimumOS: OperatingSystemVersion?
}
```

### 4.2 Feature

```swift
@MainActor
public protocol Feature: AnyObject {
    static var manifest: FeatureManifest { get }

    /// Cheap. No side effects. Called once when the feature is enabled.
    init(context: FeatureContext)

    /// Begin work: register observers, install hooks, publish services.
    /// Only called when required permissions are granted.
    func start() async throws

    /// Undo everything start() did. Must be safe to call after a failed start.
    func stop() async

    // ── Contributions (all optional; default implementations return empty) ──
    var commands: [Command] { get }
    var quickToggles: [QuickToggle] { get }
    var searchProviders: [any SearchProvider] { get }
    var resultActions: [ResultAction] { get }          // ⌘K actions on Floating Bar results / Shelf items
    var menuBarItems: [MenuBarItem] { get }            // extra status items (e.g. Stats CPU graph)
    var settingsPane: SettingsPane? { get }
    var islandPages: [IslandPage] { get }              // pages in the expanded Island
}

public extension Feature {
    var commands: [Command] { [] }
    var quickToggles: [QuickToggle] { [] }
    var searchProviders: [any SearchProvider] { [] }
    var resultActions: [ResultAction] { [] }
    var menuBarItems: [MenuBarItem] { [] }
    var settingsPane: SettingsPane? { nil }
    var islandPages: [IslandPage] { [] }
}
```

> **As built (M1):** the protocol has `commands`, `quickToggles`, `menuBarSections`
> (sliders and strips in the menu bar popover, ordered by `order`), `menuBarItems`,
> `islandPages` and `settingsPane`. Search providers and result actions arrive with the
> Floating Bar (M2). Feature classes are `public` so the app's `FeatureCatalog` can list
> them; everything else in a feature stays internal.

*Static* contributions (commands, toggles, providers, panes) are declared as properties.
*Dynamic* things (an activity that appears when recording starts) go through services on
the context, e.g. `context.island.present(…)`.

### 4.3 Context: what a feature gets

```swift
@MainActor
public struct FeatureContext {
    public let id: FeatureID
    public let settings: FeatureSettings      // namespaced: keys are stored as "nightShift.intensity"
    public let storage: FeatureStorage        // ~/Library/Application Support/KKit/<id>/, SQLite helper
    public let log: Logger                    // category = feature id
    public let events: EventBus               // publish/subscribe AppEvents
    public let services: ServiceRegistry      // resolve core and feature-published services
    public let permissions: PermissionsService
    public let island: IslandPresenting       // present(activity) → handle
    public let overlays: OverlayService       // full-screen helpers, region picker, tint
    public let hotkeys: HotkeyService
}
```

> **As built (M0):** `FeatureContext` in `KKitCore` holds `id`, `settings`, `log`,
> `events` and `services`. KKitCore can't see the service protocols (they live in
> `KKitServicesAPI`, which depends on KKitCore), so `KKitServicesAPI` adds
> `context.permissions`, `context.hotkeys`, `context.overlays` and `context.storage` as
> extensions resolved from the registry. M1 adds `context.island` (a `FeatureIsland`
> that fills in the owner), `context.audio`, `context.deviceUsage`, `context.power`,
> `context.display`, `context.systemInfo`, `context.notifications`,
> `context.systemActions` and `context.location` the same way; `context.input` follows
> in M4. Publish a service with
> `context.services.publish((any ShelfServicing).self, controller)`; it is removed
> automatically when the feature stops.

Features **don't create windows or global hooks themselves**; they ask a service. That's
what keeps multi-display handling, Spaces, full-screen behaviour and permissions
consistent across the app.

### 4.4 Lifecycle (FeatureManager)

```
                 user enables
   ┌──────────┐ ───────────────► ┌───────────────────────┐
   │ disabled │                  │ waitingForPermissions │ ◄── permission revoked
   └──────────┘ ◄─────────────── └──────────┬────────────┘
        ▲        user disables              │ all required granted
        │                                   ▼
        │                           ┌──────────────┐  throws   ┌────────────────┐
        └───────────────────────────│   running    │ ────────► │ failed(error)  │
               user disables        └──────────────┘ ◄──────── └────────────────┘
                                                      retry
```

- `FeatureManager` instantiates enabled features from `FeatureCatalog` at launch, checks
  permissions, and calls `start()`.
- It watches permission changes (Accessibility posts `com.apple.accessibility.api` on the
  distributed notification centre; others are re-checked when the app becomes active
  and every few seconds while a feature is waiting) and starts features as soon as
  they can.
- A thrown error moves the feature to `failed` and shows the message on its Settings
  page with a *Retry* button. One broken feature never takes the app down.
- When a feature stops, the hosts drop its contributions and the hotkey service
  unregisters its shortcuts automatically.

---

## 5. Commands: one definition, four entry points

Commands are the backbone. A feature defines an action once and gets all of this for free:

| Entry point | How |
|---|---|
| Floating Bar | Listed under `>` and in global search |
| Hotkey | Appears in Settings › Shortcuts; can have a default binding |
| Shortcuts.app / Siri / Spotlight | One generic App Intent, *Run KKit Command*, whose parameter is an `AppEntity` listing all commands |
| URL scheme | `kkit://run/nightShift.toggle?value=150` |

```swift
public struct Command: Identifiable, Sendable {
    public let id: CommandID                 // "nightShift.toggle" (feature id prefix is enforced)
    public var title: String                 // "Toggle Night Shift"
    public var subtitle: String?
    public var symbol: String
    public var keywords: [String] = []       // extra search terms
    public var defaultShortcut: Shortcut?    // nil = unbound by default
    public var parameter: CommandParameter?  // .percent, .duration, .text, .choice([…])
    public var isEnabled: @MainActor () -> Bool = { true }
    public var state: (@MainActor () -> CommandState)? = nil   // .on/.off/.value for live tiles & results
    public var perform: @MainActor (CommandInvocation) async throws -> Void
}
```

> **As built (M2):** `kkit://run/<commandID>?value=…` and `kkit://search?q=…` are
> parsed by `KKitLink` (KKitCore) and run by `ExternalCommandRunner` (KKitHosts), which
> waits for features to start, honours *Settings › General › Let kkit:// links run
> commands*, and parses `value` with `CommandArgumentParser` against the command's
> parameter, exactly like typed text. The App Intent (`App/RunCommandIntent.swift`) is
> `RunKKitCommandIntent` with a `KKitCommandEntity` parameter (an `EntityStringQuery`
> over every registered command) and an optional text value; it uses the same runner.

`QuickToggle` is a thin wrapper around a command with a state (`.on`/`.off`/`.value`), so a
toggle tile in the menu bar, a Floating Bar result, and a hotkey all stay in
sync.

---

## 6. Hosts

### 6.1 Island host

```swift
public struct IslandActivity: Identifiable {
    public let id: String
    public var priority: IslandPriority          // .critical (recording), .high (HUD), .normal, .low
    public var lifetime: Lifetime                // .transient(seconds: 1.5) or .ongoing
    public var compactLeading: AnyView?          // left ear
    public var compactTrailing: AnyView?         // right ear
    public var expanded: AnyView?                // shown when the user expands this activity
    public var onTap: (@MainActor () -> Void)?
}

@MainActor public protocol IslandPresenting {
    @discardableResult func present(_ a: IslandActivity) -> IslandHandle   // handle.update(…), handle.dismiss()
    func showHUD(_ hud: HUDContent)                                       // shorthand for transient HUDs
}
```

The host owns: one `NSPanel` per screen, notch geometry (`auxiliaryTopLeftArea` /
`auxiliaryTopRightArea`), pill fallback for non-notch screens, hover/click/scroll/drop
handling, priority queue, and animation. Features only provide content.

> **As built (M1):** `IslandService` in `KKitServicesAPI` has `present(_:owner:)` →
> `IslandHandle` (`update`, `dismiss`, `isActive`), `showHUD(_:owner:)` with an
> `IslandHUD` value (symbol, title, level bar, detail, tint), `dismissAll(owner:)` and
> `setScrollHandler(_:owner:)` (the newest handler gets vertical scrolls; Volume uses it).
> `IslandHost` in `KKitHosts` implements it, with the state in a testable
> `IslandModel`. The host drops a feature's activities and HUD when it stops.

The Island also exposes a **drop target** to the Shelf: when a drag nears the notch, the
host asks every running feature that registered a `DropHandler` (Shelf, AirDrop action,
Quick Note) and shows them as drop zones.

> **As built (M3):** features contribute `islandDropZones` (`IslandDropZone`: title,
> symbol, order, accepted `DropKind`s, an async `perform` that gets `[DroppedItem]`).
> The host notices a drag by the drag pasteboard's `changeCount` plus global mouse
> monitors, opens a drop area when the cursor is within ~150 pt of the notch, and
> splits it into equal zones (`IslandDropZoneItem.index`). Shelf offers *Shelf* (100) and
> *AirDrop* (200); Quick Note offers *Add to Note* (300). `IslandService.expand(page:
> activityID:owner:)` opens the Island on a feature's page or activity (screenshot
> thumbnails, scanned codes), and `IslandHandle.isExpanded` tells a feature the user is
> looking, so it waits before dismissing.

### 6.2 Floating Bar host

```swift
public protocol SearchProvider: Sendable {
    var id: String { get }
    var prefix: String? { get }                  // "f ", "w ", "/" …
    var displayName: String { get }
    func results(for query: Query) -> AsyncStream<[SearchResult]>   // stream so slow sources fill in
}

public struct SearchResult: Identifiable, Sendable {
    public let id: String
    public var title: String
    public var subtitle: String?
    public var icon: ResultIcon                  // symbol, file icon, app icon, image
    public var score: Double                     // provider's own relevance; host adds frecency
    public var kind: ResultKind                  // .command, .file(URL), .url(URL), .text, .menuItem …
    public var primary: @MainActor @Sendable () async -> Void
    public var preview: (@MainActor () -> AnyView)?
}
```

The host owns: the pre-warmed panel, query parsing (prefix → provider), fan-out to
providers with a 50 ms "first paint" deadline, merging and ranking (fuzzy match ×
provider score × frecency stored in SQLite), keyboard navigation, the empty-state favourites and recents, the
⌘K action menu (filled from all features' `resultActions` that accept the result's
`kind`), and *modes*: a feature can take over the panel's content area (Quick Note's
editor, Clipboard's grid) via `FloatingBarMode`.

> **As built (M2):** `SearchProvider` is a `@MainActor` class protocol (providers hold
> settings and indexes) with `prefix` and `includeInRootSearch`; results carry a
> `ResultKind` (`.command`, `.application`, `.file`, `.url`, `.text`, `.custom`) that the
> host runs by default, with an optional `perform` and `preview`. `ResultAction`s carry
> `appliesTo`, `FloatingBarMode` a view builder taking a `FloatingBarModeContext`
> (initial text, dismiss, exit, open settings). `FloatingBarHost` (the service behind
> `context.floatingBar`) owns the panel and keys; `FloatingBarModel` owns the engine
> (`QueryRouter`, `ResultRanker`, `FloatingBarHistory` with frecency, saved as JSON
> through `StorageService`). Commands are searched by the host's own
> `CommandSearchProvider`, which also matches inline arguments (`night 150`). Settings ›
> Floating Bar turns providers on and off, sets the hotkey (⌥Space), placement and
> history.

### 6.3 Menu bar host

One KKit status item with the popover (toggle grid, sliders, stats strip). Features add
tiles via `quickToggles` and extra standalone status items via `menuBarItems`.

### 6.4 Settings host

Builds the sidebar from manifests, the per-feature pages from `settingsPane`, the
Shortcuts table from every feature's commands, and the Permissions page from manifests and
`PermissionsService`. Uses shared `KKForm` components so every pane looks the same.

---

## 7. Shared services

Each is a protocol in `KKitServicesAPI` with one implementation in `KKitServices`.
Services are created once, lazily, by the `ServiceContainer` at launch.

| Service | Responsibility | macOS APIs | Permission |
|---|---|---|---|
| **PermissionsService** | Status, request, open the right Settings pane, change notifications | `AXIsProcessTrusted`, `CGPreflightScreenCaptureAccess`, `IOHIDCheckAccess`, AVFoundation auth, EventKit auth | — |
| **HotkeyService** | Register/unregister global shortcuts by `CommandID`, conflict detection, recorder UI | Carbon `RegisterEventHotKey` via KeyboardShortcuts | none |
| **InputTapService** | The **single** `CGEventTap` for the app, for keyboard *and* mouse. Features add handlers with a priority; the first one that consumes an event wins. See below | `CGEvent.tapCreate`, `hidutil` mappings | Accessibility, Input Monitoring |
| **OverlayService** | Create KKit panels with correct level, Spaces, full-screen and multi-display behaviour; region picker; click-through tint/dim overlays | `NSPanel`, `NSScreen`, `CGDisplayRegisterReconfigurationCallback` | — |
| **AudioService** | Devices, default in/out, volume/mute, per-app volume via process taps, device change events | CoreAudio, `AudioHardwareCreateProcessTap` (14.2+) | Audio capture prompt for taps |
| **DisplayService** | Displays, brightness (built-in + DDC later), gamma tables, re-apply on reconfiguration/wake | CoreGraphics `CGSetDisplayTransferByTable`, IOKit | — |
| **PowerService** | Sleep assertions, power source, battery details, power events | IOKit `IOPMAssertion*`, `IOPSCopyPowerSourcesInfo` | — |
| **SystemInfoService** | CPU, memory, disk, network, processes, thermal; **demand-driven sampling** (samples only while subscribed) | Mach host APIs, `libproc`, `getifaddrs`, `URLResourceValues` | — |
| **PasteboardService** | Change stream (polls `changeCount` at 250–500 ms), read typed items, write, synthetic paste | `NSPasteboard`, `CGEvent` | Accessibility (paste), pasteboard access prompt |
| **ScreenCaptureService** | Shareable content, screenshot, stream/record, exclude KKit windows | ScreenCaptureKit | Screen Recording, Microphone |
| **AccessibilityService** | Frontmost app, focused element, selected text, app menu items | `AXUIElement` | Accessibility |
| **WindowService** | Window under cursor, list/focus/raise windows, get/set frames (throttled to display refresh), screen visible frames, macOS tiling detection | `AXUIElement`, `CGWindowListCopyWindowInfo`, `NSScreen` | Accessibility |
| **MenuBarItemsService** | List other apps' menu bar icons, their positions and images, press them, hide/show via separator items. Isolated because it's fragile | `NSStatusItem`, window list, `AXUIElement` | Accessibility, Screen Recording (icon images) |
| **DeviceUsageService** | Which mic/camera is in use, and by which process where macOS says | CoreAudio process objects, CoreMediaIO | — |
| **NowPlayingService** | Current track, artwork, controls; isolated because the backing API is unstable | MediaRemote (restricted since macOS 15.4) or AppleScript fallback | Automation |
| **StorageService** | Per-feature folders, SQLite (GRDB) databases, JSON blobs, migrations | FileManager, GRDB | — |
| **FileAccessService** | Remember user-picked folders (e.g. Obsidian vault) with bookmarks, watch for changes | Bookmarks, FSEvents / `DispatchSource` | — |
| **NotificationService** | Route to Island first, fall back to system notifications | UserNotifications | Notifications |
| **LocationService** | Approximate location / city for sunset times (or manual city) | CoreLocation | Location (optional) |
| **FileSearchService** (M2) | File and folder name search in the home folder, most recently used first | `NSMetadataQuery` (Spotlight) | — |
| **FloatingBarService** (M2) | Open the Floating Bar with a query or in a feature's mode; implemented by `FloatingBarHost` | — | — |

> **As built (M3):** StorageService opens SQLite databases with the system
> `libsqlite3` (`SQLiteDatabase` in KKitServices; no GRDB). `PasteboardService`
> (`NSPasteboardService`) polls every 0.4 s only while a feature listens and tags KKit's
> own writes. `ScreenCaptureService` (`ScreenCaptureKitService`) captures displays,
> areas and windows without KKit's panels; recording needs macOS 15. The region picker
> lives in `OverlayService.pickRegion`.

> **As built (M4):** `InputTapService` is `CGEventTapInputService`: handlers are
> `@MainActor` closures added with `context.input.add(priority:interests:)` and return
> `.pass` or `.consume` (the Hyper key rewrites `event.cgEvent.flags` in place and
> passes). Priorities are `.safety`, `.high`, `.normal`, `.low`. `WindowService`
> (`AXWindowService`) and `AccessibilityService` (`AXAccessibilityService`) do their AX
> calls in actors with a 0.3 s messaging timeout per app. `CommandRunnerService` runs
> commands by id. `DisplayService` gained brightness (built-in displays) and
> `AudioService` per-app volume (`ProcessTapMixer`, macOS 14.2 process taps).

> **As built (M5):** `MenuBarItemsService` is `StatusBarMenuBarItemsService`: it owns the
> Menu Bar Manager's chevron and divider status items (features still never make status
> items; standalone items go through the menu bar host), lists icons through each app's
> `AXExtrasMenuBar` in an actor (`AXMenuBarEngine`, never KKit's own process), presses
> them with `AXPress`, and moves them with a synthetic ⌘-drag. The pure geometry
> (sections, notch, drop points) is `MenuBarLayout`, unit-tested.

### InputTapService in detail

Keyboard, Window Management, Volume, Clean Mode and (later) scroll-direction all need to
see or swallow low-level input. Several separate taps would each add latency and fight
over event order, so there is exactly one, owned by this service.

```swift
public protocol InputHandler: AnyObject, Sendable {
    var id: String { get }
    var priority: InputPriority { get }            // .safety (Clean Mode) > .high > .normal
    var interests: InputInterests { get }           // e.g. [.keys, .flags] or [.mouseButtons, .mouseDrag]
    /// Must return within ~0.1 ms. Return .consume to swallow, .pass to let it through,
    /// or .replace(events) to rewrite (Hyper key).
    func handle(_ event: CGEvent, type: CGEventType) -> InputDecision
}

context.input.add(handler)          // returns a token; removed automatically on feature stop
context.input.arm(handlerID, for: .mouseDrag)   // ask for expensive events only while needed
```

- **Event masks are built from the union of what running handlers need**, so if no
  feature wants mouse events, the tap never sees them.
- **Arming:** high-frequency events (mouse moved/dragged, scroll) are only added to the
  mask while a handler arms them. Window Management watches `flagsChanged`; when the
  move/resize modifier goes down it arms mouse events, and disarms when it's released.
  So "modifier + mouse" costs nothing the rest of the time.
- Handlers decide fast and hand real work (e.g. AX window moves) to `WindowService` on
  another queue, coalesced to one update per display frame.
- `.safety` priority lets Clean Mode swallow everything ahead of other handlers.


### Feature-published services

A feature can publish a service for others to *optionally* use, without them importing it:

```swift
// In KKitServicesAPI (as built: `add(_ items: [DroppedItem]) async throws`)
public protocol ShelfServicing: AnyObject { func add(_ items: [ShelfItem]) }

// Shelf feature, in start():
context.services.publish(ShelfServicing.self, self.controller)
// … and in stop():
context.services.unpublish(ShelfServicing.self)

// Screen Tools, when building the after-capture actions:
if let shelf = context.services.resolve(ShelfServicing.self) {
    actions.append(.init(title: "Add to Shelf", symbol: "tray.and.arrow.down") { shelf.add([.file(url)]) })
}
```

If the Shelf is disabled, `resolve` returns `nil` and the "Add to Shelf" action simply
doesn't appear. Same pattern for `QuickNoteServicing` (OCR → note, Clipboard → note).

### Event bus

For loose "something happened" signals that several features may care about:

```swift
public enum AppEvent: Sendable {
    case screenshotCaptured(URL)
    case clipboardChanged(ClipboardItemID)
    case volumeChanged(Float, deviceID: AudioDeviceID)
    case powerSourceChanged(isOnAC: Bool)
    case displaysChanged
    case frontmostAppChanged(bundleID: String?)
    case fileDragStarted, fileDragEnded
    case custom(name: String, payload: [String: String])   // escape hatch for new features
}

for await event in context.events.stream(where: { if case .displaysChanged = $0 { true } else { false } }) { … }
```

Rule of thumb: **services for doing, events for telling.**

---

## 8. Settings

```swift
public struct SettingKey<Value: Codable & Sendable>: Sendable {
    public let name: String          // "intensity"; stored as "<featureID>.intensity"
    public let defaultValue: Value
}

enum NightShiftSettings {
    static let intensity = SettingKey("intensity", default: 0.7)        // 0…2
    static let mode      = SettingKey("mode", default: TintMode.warm)
    static let schedule  = SettingKey("schedule", default: Schedule.sunsetToSunrise)
}

// In a SwiftUI view:
@Setting(NightShiftSettings.intensity) var intensity
// In logic:
context.settings[NightShiftSettings.intensity] = 1.4
for await value in context.settings.changes(of: NightShiftSettings.intensity) { apply(value) }
```

- Backed by `UserDefaults` (app suite) for small values; anything large or list-like
  (clipboard history, shelf items, frecency) lives in the feature's SQLite database via
  `StorageService`.
- Export/import of all settings as JSON (for backups and moving to a new Mac).

---

## 9. Concurrency and performance rules

- Features, hosts and views are `@MainActor`. Heavy or frequent work (sampling, OCR,
  database, file I/O, image conversion) runs in actors or detached tasks and hops back to
  the main actor to publish results.
- **Nothing polls unless someone is looking.** `SystemInfoService` only samples while a
  view, menu bar item or alert rule subscribes. The pasteboard poller is the one exception
  and is very cheap.
- The `InputTapService` callback must return in well under 1 ms: handlers do a quick
  match and hand off real work asynchronously. A slow tap gets disabled by macOS
  (`tapDisabledByTimeout`); the service re-enables it and logs which handler was slow.
- Panels (Floating Bar, Island, Clipboard picker) are created at launch and hidden, not
  rebuilt each time.

---

## 10. How each feature uses the shared parts

`●` = uses, `○` = optional / for an extra ability.

| Feature | Island | Floating Bar | Menu bar | Hotkeys | Input tap | Overlay | Audio | Display | Power | SysInfo | Pasteboard | Capture | AX | Storage | Permissions needed |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Volume & Audio | ● HUD, scroll | ● cmds | ● slider, devices, app volume, tile | ● | ○ media keys, push-to-talk | | ● per-app taps | | | | | | | | Accessibility (keys, optional), audio capture (per-app) |
| Brightness | ● HUD | ● cmds | ● slider | ● | ○ brightness keys | | | ● brightness | | | | | | | Accessibility (keys, optional) |
| Floating Bar host | | — | | ● | | ● | | | | | | | ○ `m ` menu items | ● frecency | Accessibility (menu items), Automation (tabs) |
| Stats | ● alerts, page | ● cmds | ● items | | | | | | ● battery | ● | | | | ○ history | — |
| Power | ● indicator, page | ● cmds | ● tile | ● | | | | ○ external display | ● | | | | | | — |
| Island host | — | | | | | ● | ○ | | | | | | | | Automation (now playing fallback) |
| Screen Tools | ● thumbnail, rec | ● cmds | ● | ● | | ● picker | ○ audio | | | | ● copy | ● | | ● | Screen Recording, Microphone |
| Clipboard | ○ flash | ● provider, mode | ● | ● | | ● picker | | | | | ● | | ● paste | ● SQLite | Accessibility, pasteboard access |
| Shelf | ● drop zone, page | ● actions | ○ | ● | | | | | | | | | | ● | — |
| Keyboard | ○ errors | ○ commands to bind | | ● | ● Hyper, bindings, leaders | ● cheat sheet, leader | | | | | | | | | Accessibility |
| Night Shift | | ● cmds | ● tile, slider | ● | | | | ● gamma, dim, wake | | | | | | | Location (optional) |
| Quick Note | ○ "saved" | ● `n ` mode, ⌘K action | | ● | | | | | | | ○ | | ○ selection | ● bookmark | — (folder picked by user) |
| Window Management | ○ layout saved | ● cmds, layouts provider | | ● | ● modifier + mouse, drag snap | ● snap preview | | | | | | | ● WindowService | ● layouts | Accessibility |
| Menu Bar Manager | | ● icons in `m ` (`MenuBarIconsServicing`) | ● chevron, dividers (MenuBarItems), tile | ● | ○ ⌘ shows all (`.low`) | ● drop-down bar | | | | | | ○ icon images | ● MenuBarItems | | — (Accessibility to list/open/move, Screen Recording for pictures; both optional) |
| Quick Toggles | | ● cmds | ● tiles | ● | | ○ hide desktop | | | | | | | | | Automation (per toggle) |
| Privacy Indicator | ● ear, page | ● cmd | | | | | ● DeviceUsage, mute | | | | | | | ○ log | — |
| Timer | ● countdowns, alert, page | ● cmds | ● tile | ● | | | | | | | | | | ● saved timers | Notifications (optional) |
| Calculator | | ● `=` provider, auto-detect | | | | | | | | | ● copy | | | ● rate cache | — (network: exchange rates) |
| Search | | ● apps, `f `, `/`, `w ` providers | | | | | | | | | | | | | — (Full Disk Access for Safari bookmarks) |
| Clean Mode | | ● cmds | ● tile | ● | ● swallow all (`.safety`) | ● lock overlay | | | | | | | | | Accessibility |

This table is also the build order hint: **Overlay, Hotkeys, Permissions, Settings and the
Island are used by almost everything**, so they come first.

---

## 11. Adding a new feature (the recipe)

Example: the *Timer* feature (DESIGN.md §3.16), simplified.

1. **Create the target.** Add `Sources/Features/FeatureTimer/` and a matching
   `.target(name: "FeatureTimer", dependencies: ["KKitCore", "KKitUI", "KKitServicesAPI"])`
   (plus a test target) in `Package.swift`, and add it to the app target's dependencies in
   `project.yml`.
2. **Write the feature.**

   ```swift
   import KKitCore, KKitUI, KKitServicesAPI

   @MainActor
   final class TimerFeature: Feature {
       static let manifest = FeatureManifest(
           id: "timer", name: "Timer", symbol: "timer",
           summary: "Countdowns and Pomodoro in the Island.",
           category: .productivity, requiredPermissions: [], optionalPermissions: [],
           enabledByDefault: false)

       private let context: FeatureContext
       private let model: TimerModel
       private var activity: IslandHandle?

       init(context: FeatureContext) {
           self.context = context
           self.model = TimerModel(settings: context.settings)
       }

       func start() async throws {}
       func stop() async { model.cancel(); activity?.dismiss() }

       var commands: [Command] {[
           Command(id: "timer.start", title: "Start Timer", symbol: "timer",
                   parameter: .duration(default: .minutes(25))) { [weak self] inv in
               self?.begin(inv.duration ?? .minutes(25))
           },
           Command(id: "timer.cancel", title: "Cancel Timer", symbol: "xmark.circle",
                   isEnabled: { [weak self] in self?.model.isRunning == true }) { [weak self] _ in
               self?.model.cancel(); self?.activity?.dismiss()
           },
       ]}

       var settingsPane: SettingsPane? { SettingsPane { TimerSettingsView() } }

       private func begin(_ d: Duration) {
           model.start(d)
           activity = context.island.present(IslandActivity(
               id: "timer", priority: .normal, lifetime: .ongoing,
               compactLeading: AnyView(Image(systemName: "timer")),
               compactTrailing: AnyView(TimerCountdownText(model: model)),
               expanded: AnyView(TimerExpandedView(model: model))))
       }
   }
   ```

3. **Register it** in `App/FeatureCatalog.swift`:

   ```swift
   static let all: [any Feature.Type] = [
       PowerFeature.self, VolumeFeature.self, …, TimerFeature.self,
   ]
   ```

4. **Document it** in `Sources/Features/FeatureTimer/README.md` (what, permissions, APIs,
   limits) and add a row to the table in §10.
5. **Test it**: unit-test `TimerModel` with fake services; CI builds the app.

That's it. The feature now has a Settings page and an on/off switch, its commands are in
the Floating Bar and Shortcuts table, can be bound to hotkeys, run from Shortcuts.app and
`kkit://run/timer.start`, and its activity shows in the Island with the shared priority
rules.

### Conventions (also in CLAUDE.md)

- IDs: feature ids are `lowerCamelCase`; command ids are `<featureID>.<verb>`; setting keys
  are namespaced automatically.
- No feature imports another feature. Share through a protocol in `KKitServicesAPI` +
  `services.publish/resolve`, or through `AppEvent`.
- No feature creates its own `NSWindow`/`NSPanel` or `CGEventTap`; use `OverlayService`
  and `InputTapService`.
- Private or fragile APIs (MediaRemote, CoreBrightness, SMC) live only inside a service
  implementation, behind a protocol, with a public-API fallback or a clear "unavailable"
  state.
- Every user-facing string goes through `String(localized:)`.

---

## 12. Testing and CI

- **Unit tests** per module (`swift test` on macOS): ranking, schedule maths (sunset),
  clipboard dedupe, note path templating, settings migration, command routing.
- **Fakes** for every service protocol live in `KKitServicesTesting` so feature logic can
  be tested without real permissions or hardware.
- **SwiftUI previews** for every component and pane, using fakes.
- **CI** (GitHub Actions, `.github/workflows/ci.yml`, macOS 15, latest stable Xcode):
  `swift test --package-path Packages/KKitModules` for every module's tests, then
  `xcodegen generate` and `xcodebuild build` for the app (unsigned). SwiftLint/SwiftFormat
  checks to come. Release workflow later: archive, sign, notarize, publish Sparkle
  appcast (needs a paid Developer ID).

---

## 13. Risks and known platform limits

| Area | Risk | Mitigation |
|---|---|---|
| Now Playing | MediaRemote restricted for third-party apps since macOS 15.4 | Isolated `NowPlayingService`; AppleScript fallback for Music/Spotify; feature degrades gracefully |
| Night Shift >100% | Gamma tables conflict with other gamma apps; reset on display change; don't affect some HDR content | Re-apply on reconfiguration/wake; detect conflicts and warn |
| Clipboard | Apple is moving toward prompting for programmatic pasteboard reads | Handle the prompt in onboarding; explain why |
| Event tap | Disabled if slow; needs two permissions | One shared tap, strict time budget, auto re-enable |
| Menu Bar Manager | Hiding and listing other apps' menu bar icons relies on techniques Apple can break in any release | Own service + feature flag; the Floating Bar `m ` provider still works for app menus if it breaks |
| Window Management | AX window moves are slow and some apps ignore or fight them; conflicts with macOS tiling | Coalesce to one update per frame; per-app exclusions; detect and optionally disable system tiling |
| Clean Mode | A stuck lock would leave the user without a keyboard | Hard 2-minute auto-unlock; if macOS disables the tap the lock fails open; keyboard-only mode always has a click-to-unlock button |
| Permissions UX | Users deny and forget | Permissions page, per-feature reduced modes, just-in-time asks |
| Notarization | Private frameworks and helper need care | Load private frameworks dynamically (`dlopen`) so the app still launches if they're missing |
