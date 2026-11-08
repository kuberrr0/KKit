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
- **Volume** (CoreAudio volume/devices, Island HUD; media-key takeover once Input tap lands)
- **Quick Toggles pack**

## M2 — Floating Bar

- **Floating Bar host** (panel, providers, ranking, pins, ⌘K actions, modes)
- Providers: commands, apps, files, System Settings, web, calculator
- **Quick Note** (Obsidian targets, templates, editor mode)
- URL scheme and the *Run KKit Command* App Intent

## M3 — Capture & clipboard

- **Clipboard History** (SQLite + FTS, picker panel, paste stack, snippets)
- **Screen Tools** (screenshot, OCR, QR, colour picker, recording)
- **Shelf** (Island drop zone, item actions)

## M4 — Input power-user features

- **InputTapService** (single shared event tap)
- **Keyboard**: Hyper key, app launch hotkeys, leader sequences, cheat sheet
- Volume media-key takeover, menu-items provider for the Floating Bar
- Per-app volume (process taps)

## M5 — Extras (pick from DESIGN.md §4)

Window management, timer/Pomodoro, mic mute + in-use indicator, next meeting,
downloads watcher, on-device AI actions, external display brightness, menu bar manager,
screenshot annotation.

## Release track (in parallel from M1)

Developer ID signing, notarization, Sparkle updates, crash/error log export, settings
export/import, onboarding.
