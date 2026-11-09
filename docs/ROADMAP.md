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
- **Timer, Pomodoro & Stopwatch**
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

## M3 — Capture & clipboard

- **Clipboard History** (SQLite + FTS, picker panel, paste stack, snippets)
- **Screen Tools** (screenshot, OCR, QR scan, translate, colour picker, recording)
- **Shelf** (Island drop zone, item actions)

## M4 — Input power-user features

- **InputTapService** (single shared event tap, keyboard + armed mouse events)
- **Keyboard**: Hyper key, app launch hotkeys, leader sequences, cheat sheet
- **Window Management**: snap hotkeys, drag-to-snap, modifier + mouse move/resize, layouts
- **Clean Mode**
- Volume media-key takeover and push-to-talk, per-app volume (process taps)
- Menu-items provider (`m `) for the Floating Bar

## M5 — Menu Bar Manager

- **MenuBarItemsService** + **Menu Bar Manager** (sections, drop-down bar for hidden and
  behind-the-notch icons). Last of the core features because it's the most fragile.

## M6 — Extras (pick from DESIGN.md §4)

Next meeting, downloads watcher, on-device AI actions, external display brightness,
screenshot annotation, text expansion.

## Release track (in parallel from M1)

Developer ID signing, notarization, Sparkle updates, crash/error log export, settings
export/import, onboarding.
