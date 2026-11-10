# KKit — Roadmap

Ordered so that each milestone builds the shared parts the next one needs, and so that
the features needing the fewest permissions ship first. See
[ARCHITECTURE.md §10](ARCHITECTURE.md#10-how-each-feature-uses-the-shared-parts) for the
dependency table behind this order.

## M0 — Skeleton (no user-visible features yet) ✅

Done. Notes on what was built versus the plan below: the `Feature` protocol has the
contributions M0 hosts can show (commands, quick toggles, settings pane); search
providers, result actions, Island pages and extra menu bar items are added with their
hosts. Storage is JSON files per feature for now; GRDB/SQLite comes with Clipboard (M3).
KKit's own commands (`app.openSettings`, `app.openMenu`) show in Settings › Shortcuts.

- XcodeGen `project.yml`, app target, `Packages/KKitModules` with empty module targets
- `KKitCore`: `Feature`, `FeatureManifest`, `FeatureContext`, `FeatureManager`,
  `Command`/`CommandRegistry`, `SettingKey`/`SettingsStore`, `EventBus`, `ServiceRegistry`
- `KKitUI`: tokens and the first components (row, tile, slider, form)
- Services: Permissions, Hotkeys, Overlay, Storage
- Hosts: menu bar (empty toggle grid), Settings window (sidebar from manifests,
  Shortcuts and Permissions pages)
- GitHub Actions CI building and testing on macOS

## M1 — Low-permission essentials + Island ✅

Done. Notes on what was built versus the plan below:

- The `Feature` protocol gained `menuBarSections`, `menuBarItems` and `islandPages`.
  New services in `KKitServicesAPI` (with fakes in `KKitServicesTesting`): Island,
  Audio, DeviceUsage, Power, Display, SystemInfo, Notifications, SystemActions,
  Location. Each starts listening only while something subscribes.
- The Island lives in a fixed-size panel per screen (built-in, main or all screens) and
  hides in full-screen apps unless turned on; clicks pass through its transparent parts.
  HUDs cover the compact activity for a moment; horizontal scroll switches pages.
- Volume shows its HUD for changes made through KKit; the volume keys still show
  macOS's HUD until the takeover in M4. The red "mic muted" ear is Privacy Indicator's.
- Quick Toggles: Bluetooth (no public API) and Focus (needs a Shortcuts shortcut) are
  left out for now; "keep the screen saver off" is Power's Awake tile.
- Timer's backup `UNNotification` isn't scheduled; timers are saved instead and the
  ones that ended while KKit was closed are announced on launch.

- **Island host** (compact, HUD, expanded; pill fallback for non-notch screens)
- **Power** (assertions, durations, Island indicator)
- **Stats** (CPU, memory, storage, battery, network; menu bar items; alerts)
- **Night Shift** (gamma-based, intensity up to 200%, schedule, extra dim)
- **Volume & Audio** (CoreAudio volume, device switching, mic mute, Island HUD; media-key
  takeover once the input tap lands)
- **Privacy Indicator** (mic/camera in use, in the Island)
- **Timer & Stopwatch** (Pomodoro removed later at KV's request)
- **Quick Toggles**

## M2 — Floating Bar ✅

Done. Notes on what was built versus the plan below:

- `Feature` gained `searchProviders`, `resultActions` and `floatingBarModes`. New in
  `KKitCore`: `SearchProvider`, `SearchResult`, `ResultKind`, `FloatingBarMode`,
  `FuzzyMatch`, `CommandArgumentParser` and `KKitLink`. New services:
  `FloatingBarService` (the host, `context.floatingBar`) and `FileSearchService`
  (Spotlight); Quick Note publishes `QuickNoteServicing`.
- The host (`KKitHosts/FloatingBar/`) keeps its engine in a testable
  `FloatingBarModel`: prefix routing, a 50 ms first-paint deadline, ranking by provider
  score + frecency, Favourites and Recent (`floatingBar/history.json`, not SQLite yet),
  ⌘K actions, Tab preview, modes and inline arguments. Typing a parameterised command
  without its value turns it into a chip that takes the value. Commands are a host
  provider (`>`); files, apps, System Settings and the web are the **Search** feature
  (`FeatureSearch`, the "FeatureFinder" of the plan).
- Web: URLs, keyword engines (`yt lofi`), Chromium-family and Safari bookmarks and a
  "Search Google for …" fallback. Open browser tabs (Automation per browser) are left
  for later.
- Calculator uses KKit's own unit table (Foundation `Measurement` doesn't parse unit
  names); ⌘↵ to paste the answer waits for the paste service in M3, ↵ copies.
- Quick Note's context is the frontmost app's name; the browser URL and selected text
  need Automation/Accessibility and come later.
- `kkit://run/<command>?value=…` and `kkit://search?q=…` go through
  `ExternalCommandRunner`, as does the *Run KKit Command* App Intent (with an optional
  value). Links can be stopped from running commands in Settings › General.

- **Floating Bar host** (launcher panel, providers, ranking, favourites/recents, ⌘K actions, modes, inline command arguments)
- Providers: commands, apps, files, System Settings, web
- **Calculator, Units & Currency**
- **Quick Note** (Obsidian targets, templates, editor mode)
- URL scheme and the *Run KKit Command* App Intent

## M3 — Capture & clipboard ✅

Done. Notes on what was built versus the plan below:

- Storage gained SQLite: `StorageService.openDatabase` returns a `Database` backed by the
  system `libsqlite3` (`SQLiteDatabase`, WAL, migrations by `user_version`) rather than
  GRDB, so there's no new dependency. Clipboard search uses FTS5 with the trigram
  tokenizer and falls back to `LIKE`.
- New services: `PasteboardService` (`context.pasteboard`; polls `changeCount` every
  0.4 s only while subscribed, marks KKit's own writes, ⌘V paste needs Accessibility) and
  `ScreenCaptureService` (`context.screenCapture`; ScreenCaptureKit screenshots on 14.2,
  recording on macOS 15 with `SCRecordingOutput`). `OverlayService.pickRegion` is the
  shared area/window/screen picker. Shelf publishes `ShelfServicing`.
- `Feature` gained `islandDropZones`: the Island watches the drag pasteboard and the
  cursor, opens into one zone per feature (Shelf, AirDrop, Add to Note) and hands the
  dropped files, links, text or image data to the zone. Island handles report
  `isExpanded`, and features can open the Island on a page or activity
  (`context.island.showPage/showActivity`), which collapses again after a few seconds
  unless the pointer is on it.
- New events: `AppEvent.clipboardChanged`, `AppEvent.screenshotCaptured(URL)`.
- Calculator's ⌘↵ paste and Quick Note's selected-text context still wait (paste is
  available now; selection needs the M4 Accessibility service).
- Translation needs macOS 15 (Apple's on-device framework); on 14 the card says so.
- Left for later: clipboard encryption at rest, screenshot annotation, GIF export and
  keystroke overlay, multi-item drag-out and the mini shelf. See each feature's README.

- **Clipboard History** (SQLite + FTS, picker panel, paste stack, snippets)
- **Screen Tools** (screenshot, OCR, QR scan, translate, colour picker, recording)
- **Shelf** (Island drop zone, item actions)

## M4 — Input power-user features ✅

Done. Notes on what was built versus the plan below:

- `InputTapService` (`CGEventTapInputService`): one `CGEventTap` at the HID level on
  the main run loop. Features add closures with a priority (`.safety` > `.high` >
  `.normal` > `.low`) and interests; the mask is the union of interests plus armed
  high-frequency types (drags, mouse moved, scroll), and the tap is rebuilt when it
  changes. It re-enables itself after a timeout, skips events KKit posts, decodes media
  keys (`NX_SYSDEFINED` subtype 8) and logs handlers slower than 2 ms. Handlers are
  dropped when their feature stops. It also owns the Caps Lock remap (`hidutil`).
- The Hyper key is Caps Lock → F18 with `hidutil` (per login session, removed on stop,
  other mappings kept); the tap adds ⌃⌥⇧⌘ to keys pressed while F18 is down.
- New services: `WindowService` (`AXWindowService`; AX windows with a cached element
  per window, CGWindowList for the window list and under the cursor, macOS 15 tiling
  detection), `AccessibilityService` (`AXAccessibilityService`; frontmost app, menu
  items cached for 8 s, pressing them, selected text) and `CommandRunnerService` (run
  any command by id, used by Keyboard bindings and leader sequences).
- The `m ` menu-items provider lives in the Floating Bar host, not a feature.
- Brightness is its own small feature (built-in display through the private
  DisplayServices framework, CoreDisplay fallback) so the Island replaces both the
  volume and brightness HUDs. Both takeovers are on by default and pass keys to macOS
  when KKit can't act (no volume control, external display).
- Per-app volume taps only apps turned below 100% (process tap + private aggregate
  device + IOProc gain); untouched apps never go through KKit.
- Drag-to-snap stands aside while macOS 15's own edge tiling is on (a setting).
- Left for later: the ⌘K "Assign hotkey…" action on Floating Bar results, Quick Note's
  selected-text context, DDC brightness for external displays, scroll-direction per
  device.

- **InputTapService** (single shared event tap, keyboard + armed mouse events)
- **Keyboard**: Hyper key, app launch hotkeys, leader sequences, cheat sheet
- **Window Management**: snap hotkeys, drag-to-snap, modifier + mouse move/resize, layouts
- **Clean Mode**
- Volume media-key takeover and push-to-talk, per-app volume (process taps)
- Menu-items provider (`m `) for the Floating Bar

## M5 — Menu Bar Manager

- **MenuBarItemsService** + **Menu Bar Manager** (sections, drop-down bar for hidden and
  behind-the-notch icons). Last of the core features because it's the most fragile.

## Window Switcher (added after M5)

- **Window Switcher** (DESIGN.md §3.19): ⌘Tab through windows with live previews, on
  the shared input tap, `WindowService` and `ScreenCaptureService`. On by default.

## M6 — Extras (pick from DESIGN.md §4)

Next meeting, downloads watcher, on-device AI actions, external display brightness,
screenshot annotation, text expansion.

## Release track (in parallel from M1)

Developer ID signing, notarization, Sparkle updates, crash/error log export, settings
export/import, onboarding.
