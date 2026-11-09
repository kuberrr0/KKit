# KKit — Roadmap

Ordered so that each milestone builds the shared parts the next one needs, and so that
the features needing the fewest permissions ship first. See
[ARCHITECTURE.md §10](ARCHITECTURE.md#10-how-each-feature-uses-the-shared-parts) for the
dependency table behind this order.

## M0 — Skeleton (no user-visible features yet)

- XcodeGen `project.yml`, app target, `Packages/KKitModules` with empty module targets
- `KKitCore`: `Feature`, `FeatureManifest`, `FeatureContext`, `FeatureManager`,
  `Command`/`CommandRegistry`, `SettingKey`/`SettingsStore`, `EventBus`, `ServiceRegistry`
- `KKitUI`: tokens and the first components (row, tile, slider, form)
- Services: Permissions, Hotkeys, Overlay, Storage
- Hosts: menu bar (empty toggle grid), Settings window (sidebar from manifests,
  Shortcuts and Permissions pages)
- GitHub Actions CI building and testing on macOS

## M1 — Low-permission essentials + Island

- **Island host** (compact, HUD, expanded; pill fallback for non-notch screens)
- **Power** (assertions, durations, Island indicator)
- **Stats** (CPU, memory, storage, battery, network; menu bar items; alerts)
- **Night Shift** (gamma-based, intensity up to 200%, schedule, extra dim)
- **Volume & Audio** (CoreAudio volume, device switching, mic mute, Island HUD; media-key
  takeover once the input tap lands)
- **Privacy Indicator** (mic/camera in use, in the Island)
- **Timer, Pomodoro & Stopwatch**
- **Quick Toggles**

## M2 — Floating Bar

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
