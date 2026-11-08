# KKit — Product & UI/UX Design

KKit is a native macOS all-in-one utility app. It lives in the menu bar and around the
notch, stays out of the way until called, and is keyboard-first. Every feature is a
module that can be switched off, and everything it can do is reachable from one command
bar and bindable to a hotkey.

> Companion docs: [ARCHITECTURE.md](ARCHITECTURE.md) (how it's built) ·
> [ROADMAP.md](ROADMAP.md) (build order).

---

## 1. Design principles

1. **Invisible until needed.** No Dock icon by default (`LSUIElement`). KKit shows up as a
   menu bar icon, the notch Island, and the Floating Bar, and nothing else unless asked.
2. **Keyboard-first, mouse-friendly.** Every action is a *Command*. Commands appear in the
   Floating Bar, can be bound to a hotkey, run from Shortcuts.app, and opened by URL
   (`kkit://run/<command-id>`). See [ARCHITECTURE.md §5](ARCHITECTURE.md#5-commands-one-definition-four-entry-points).
3. **Feels like macOS.** SF Symbols, system materials (Liquid Glass on macOS 26+, vibrancy
   materials below that), system fonts, semantic colours, standard settings controls.
   No custom chrome where a native control exists.
4. **One place for each kind of thing.** *Glanceable status* goes to the Island. *Intent*
   (search, run, capture, write) goes to the Floating Bar. *Configuration* goes to
   Settings. *At-a-glance toggles* go to the menu bar popover.
5. **Modular and honest about permissions.** Each feature can be turned off. A feature asks
   for a permission only when it's switched on, explains why in one sentence, and keeps
   working in a reduced mode if the user says no.
6. **Fast.** Floating Bar opens in under 50 ms (the panel is pre-warmed), HUDs appear in
   under 16 ms, and idle CPU stays near 0% (sampling only while something is visible).

---

## 2. The five surfaces

Every feature plugs into one or more of these shared surfaces instead of building its own
windows. That keeps the app consistent and is what makes new features cheap.

| Surface | What it's for | Summoned by |
|---|---|---|
| **Menu bar extra** | Quick toggles, mini stats, entry to Settings | Clicking the KKit icon |
| **Island** (notch overlay) | Live status, HUDs, drop target for the Shelf, now playing | Always present; expands on hover/click |
| **Floating Bar** | Search, commands, pinned items, Quick Note, clipboard | Hotkey (default `⌥Space`, or `Hyper+Space`) |
| **Settings window** | Per-feature configuration, permissions, all shortcuts | Menu bar, Floating Bar, `⌘,` |
| **Overlays** | Full-screen helpers: capture region picker, colour loupe, recording bar, Night Shift tint | Started by a command |

### 2.1 Menu bar extra

```
┌──────────────────────────────────────────┐
│  KKit                         ⚙︎  ⏻       │
├──────────────────────────────────────────┤
│ ┌────────┐ ┌────────┐ ┌────────┐ ┌──────┐│
│ │ ☕︎      │ │ 🌙      │ │ 🎤      │ │ 🖥    ││   ← Quick Toggles grid
│ │ Awake  │ │ Night  │ │ Mic    │ │ Hide ││     (any feature can add tiles)
│ │ 1h 20m │ │ 70%    │ │ Muted  │ │ Desk ││
│ └────────┘ └────────┘ └────────┘ └──────┘│
│                                          │
│ 🔊 ━━━━━━━━━━━━━○──────  62%   AirPods ▾ │   ← Volume + output device
│ ☀︎ ━━━━━━━━━━○──────────  48%   Studio ▾  │   ← Brightness (if Displays enabled)
│                                          │
│ CPU 12% ▁▂▁▃▂  MEM 61%  SSD 214 GB free  │   ← Stats strip (click → details)
│ 🔋 86% · 4h 10m · Health 91%             │
│                                          │
│ Shelf: 3 items        Clipboard: 128     │
└──────────────────────────────────────────┘
```

- The grid is user-arrangeable (drag to reorder, right-click → remove). Tiles are
  contributed by features (see *QuickToggle* in the architecture doc).
- Optionally, Stats can put its own compact items in the menu bar (CPU graph, network
  speed, battery %) as separate status items.

### 2.2 Island (the "Floating Dock")

> **Assumption:** the brief says *"Floating Dock (works like the floating island on iPhone
> but for mac, like with …)"* and the sentence was cut off. This design reads it as a
> **Dynamic Island–style overlay around the MacBook notch**: it shows live activities,
> replaces the system HUDs, and acts as a drop target. If "like with …" meant something
> specific (a particular app, music, AirDrop, calls), tell me and I'll adjust this section.
> In the UI it's called **Island**, so it isn't confused with the macOS Dock or the Floating Bar.

The Island is a black, borderless panel drawn over the notch so it looks like the notch
itself grows. On Macs without a notch, and on external displays, it's a pill that slides
down from the top-centre only when there's something to show.

**States**

```
Idle            ▐████████▌                  (exactly notch-sized, invisible against it)

Compact         ▐🎵 ▸ ████████ ∿∿∿ ▌       (“ears” grow left/right of the notch)
  examples:     ▐● 02:14 ███████ ■ ▌        recording in progress (tap ■ to stop)
                ▐☕︎  ████████ 1:20▌        Power: awake, 1h 20m left
                ▐⏱  ████████ 24:59▌        focus timer

HUD (transient) ▐🔊 ████████ ━━━━━○── ▌    volume/brightness, auto-hides after 1.5 s

Expanded        ┌──────────────────────────────────────────────┐
(hover 300 ms   │ ▐████████▌                                   │
 or click)      │  ┌─────┐  Song Title                ⏮  ⏯  ⏭ │
                │  │ art │  Artist — Album         ━━━━○────    │
                │  └─────┘                                      │
                │  ─────────────────────────────────────────── │
                │  Shelf  [📄 report.pdf] [🖼 shot.png] [+1]    │
                │  ● Now Playing   ○ Shelf   ○ Calendar  ○ Stats │  ← pages
                └──────────────────────────────────────────────┘

Drop target     While a file drag is in progress and the cursor nears the notch,
                the Island opens into a big “Drop to Shelf / AirDrop / Open with…” zone.
```

**Behaviour**

- **Priority:** one compact activity is shown at a time; the rest are reachable by
  expanding. Order: recording › call/mic-in-use › HUD › timer › now playing › Power.
  Users can reorder this list in Settings.
- **Gestures:** scroll over the Island adjusts volume; two-finger swipe left/right switches
  pages; click an ear to open that activity's page; drag files onto it to shelve them.
- **Full-screen apps:** hidden by default (setting: *Show in full screen*).
- **Multiple displays:** show on the built-in display (default), the display with the
  cursor, or all displays.
- **Respect Reduce Motion** (cross-fade instead of the spring "grow" animation).

### 2.3 Floating Bar

> **Interpretation:** "Floating Bar (for file, browser, settings, actions, menu bar items,
> this app's features)" can mean a *launcher you type into* (like Spotlight) or a *toolbar
> of pinned things*. The design does both in one panel: a **pinned row** on top and a
> **command field** below. Either half can be turned off.

```
┌────────────────────────────────────────────────────────────────────┐
│ 📁 Projects  🌐 GitHub  ⚙︎ Wi-Fi  ☕︎ Awake  📝 Inbox.md  ⋯   (pins)  │
├────────────────────────────────────────────────────────────────────┤
│ 🔍  night sh▌                                       [All ▾]  ⌘K    │
├───────────────────────────────────────┬────────────────────────────┤
│ 🌙 Night Shift: Toggle        ⌃⌥N    │  Night Shift               │
│ 🌙 Night Shift: Set intensity…        │  Currently off             │
│ 🌙 Night Shift: Darkroom mode         │  Schedule: sunset→sunrise  │
│ ⚙︎  System Settings › Displays › Ni…  │                            │
│ 📄 night-shift-notes.md   ~/Vault     │  [Toggle]  [Settings…]     │
├───────────────────────────────────────┴────────────────────────────┤
│ ↵ Run   ⌘↵ Run & keep open   ⌘K Actions   Tab Preview   ⎋ Close    │
└────────────────────────────────────────────────────────────────────┘
```

- **Pinned row:** files, folders, URLs, apps, KKit commands/toggles (show live state),
  other apps' menu bar items, and widgets (e.g. a tiny Quick Note field). Drag anything
  in to pin it.
- **Search sources ("providers")** are contributed by features. Each has a prefix to scope
  the search:

  | Prefix | Source | Notes |
  |---|---|---|
  | *(none)* | Everything, ranked by frecency + fuzzy match | |
  | `>` | Commands (all KKit features + system actions) | Lock, sleep, empty Trash, dark mode, eject all… |
  | `f ` | Files & folders | Spotlight (`NSMetadataQuery`) |
  | `w ` | Web: URLs, search engines, bookmarks, open tabs | Tabs need Automation permission per browser |
  | `/` | System Settings panes | Deep links via `x-apple.systempreferences:` |
  | `m ` | Menu items of the frontmost app & menu bar extras | Accessibility API |
  | `c ` | Clipboard history | |
  | `n ` | Quick Note | Switches the panel into the note editor |
  | `=` | Calculator / units / currency | Inline result, `↵` copies |

- **⌘K** opens an action menu for the selected result (Reveal in Finder, Copy path,
  Open with…, Add to Shelf, Pin, Assign hotkey…). Actions are also contributed by features.
- **Placement:** centred on the active screen by default; can be docked to the top or a
  screen edge, and can be *pinned open* to behave like a persistent floating toolbar.
- Remembers the last query for 30 s so ⎋ then reopen doesn't lose work.

### 2.4 Settings window

```
┌──────────────┬──────────────────────────────────────────────────────┐
│ General      │  Night Shift                                    [●]  │
│ Permissions ⚠│  ─────────────────────────────────────────────────── │
│ Shortcuts    │  Intensity      ━━━━━━━━━━━━━━━━━━━○━━  140%          │
│ Appearance   │                 (above 100% uses extended gamma)      │
│──────────────│  Mode           (•) Warm  ( ) Amber  ( ) Darkroom    │
│ ☕︎ Power      │  Schedule       Sunset to sunrise ▾                   │
│ 🔊 Volume     │  Extra dim      ━━━━○━━━━━━━━  20%                    │
│ 📊 Stats      │  Displays       ☑ Built-in  ☑ Studio Display          │
│ 🏝 Island     │                                                      │
│ 🔍 Floating…  │  Shortcuts                                           │
│ 📸 Screen     │   Toggle Night Shift          [ ⌃⌥N ]                 │
│ 📋 Clipboard  │   Darkroom mode               [ Record… ]             │
│ 🗂 Shelf      │                                                      │
│ ⌨︎ Keyboard   │  Permissions: none needed                            │
│ 🌙 Night Sh…  │                                                      │
│ 📝 Quick Note │                                                      │
└──────────────┴──────────────────────────────────────────────────────┘
```

- Sidebar lists every feature with its enable switch state; a ⚠ badge means a permission
  is missing.
- **Shortcuts** page: one table of every command from every feature, with search, a
  record field, and conflict warnings (including conflicts with system shortcuts).
- **Permissions** page: each macOS permission, its status, which features need it, and a
  button that opens the right System Settings pane.
- Each feature's page is built from shared form components so they all look alike.

### 2.5 Onboarding

Three screens: *Welcome* → *Pick your features* (cards with toggles, all off except
low-permission ones: Power, Stats, Volume, Night Shift, Island) → *Hotkeys* (Floating Bar
key, optional Hyper key). Permissions are **not** asked up front; each is requested
just-in-time when a feature that needs it is enabled.

---

## 3. Feature designs

Each feature below lists: what it does, where it shows up, key interactions, settings,
and the macOS permissions/APIs involved. Tech notes are summarised here and detailed in
the architecture doc.

### 3.1 Volume Control

- **Does:** replaces the system volume HUD with an Island HUD; finer volume steps;
  output/input device switching; **per-app volume mixer**; optional max-volume limit;
  global mic mute.
- **Surfaces:** Island HUD, menu bar slider + device picker, Floating Bar commands
  (`Volume: 30%`, `Output: AirPods`), Quick Toggle (mic mute).
- **Interactions:** media keys show the Island HUD; scrolling on the Island changes volume;
  `⌥` + scroll gives fine steps; click the device name to switch output.
- **Settings:** step size (1–10%), volume limit, HUD style, per-app volumes (remembered),
  "Switch to AirPods when connected".
- **Tech:** CoreAudio (`AudioObjectSetPropertyData` on the default output device's
  virtual main volume); per-app volume via Core Audio process taps (macOS 14.2+);
  intercepting volume keys needs a `CGEventTap` (Accessibility permission).

### 3.2 Floating Bar

See §2.3 for the full design. It's a *host*: on its own it only knows how to show
results; files, web, settings, menu items, clipboard, notes and commands are all
providers contributed by features.

- **Settings:** hotkey, which providers are on and their prefixes, pinned items, placement,
  theme (compact/regular), browser for web results, search engines.
- **Permissions:** Accessibility (menu items), Automation (browser tabs), none for the rest.

### 3.3 Statistics

- **Does:** CPU (total, per core, top processes), memory (used, pressure, swap), storage
  (per volume, free space), battery (charge, time remaining, cycle count, health, power
  draw), network (up/down rate, local/public IP), thermal state, and optionally
  temperatures and fans.
- **Surfaces:** menu bar items (each metric can be its own compact item: sparkline,
  number, or icon), a detailed popover per metric, a Stats page in the expanded Island,
  and **alerts** in the Island ("Battery 15%", "Memory pressure high", "Disk almost full").
- **Settings:** which metrics, sample rate (1–10 s), menu bar style per metric, alert
  thresholds, units.
- **Tech:** `host_statistics64` / `host_processor_info` (CPU, memory), `libproc`
  (per-process), `IOPSCopyPowerSourcesInfo` and the `AppleSmartBattery` IORegistry entry
  (battery), `URLResourceValues` (storage), `getifaddrs` (network),
  `ProcessInfo.thermalState`. Temperatures/fans use private SMC / HID sensor APIs, so
  that part is optional and isolated.
- Sampling runs only while some view or alert needs the data.

### 3.4 Power (always-on)

- **Does:** keeps the Mac (and optionally the display) awake. Modes: *indefinitely*,
  *for a duration* (15 m, 1 h, 2 h, custom), *until a time*, *while app X is running*,
  *while on power adapter*, *while a download/copy is in progress* (later),
  *while external display connected*.
- **Surfaces:** Quick Toggle tile (tap = toggle, long-press = duration menu), Island compact
  indicator with time remaining, Floating Bar commands (`Awake for 2h`), hotkey.
- **Settings:** default duration, keep display awake vs. system only, allow screen saver,
  auto-rules, battery cut-off ("stop when battery < 20%").
- **Tech:** `IOPMAssertionCreateWithName` (`PreventUserIdleDisplaySleep` /
  `PreventUserIdleSystemSleep`). No permission needed. *Closed-lid without power* needs
  `pmset disablesleep`, which requires an admin helper; that's an optional advanced mode.

### 3.5 Island (Floating Dock)

See §2.2. It's a *host* like the Floating Bar: features push **activities** into it.

- **Built-in activities:** Now Playing (art, controls, scrubber), HUDs (volume, brightness,
  keyboard backlight), Power indicator, recording indicator, timer, Shelf page,
  battery/charging animation, mic/camera-in-use indicator, notifications from KKit features
  (screenshot taken, note saved, clipboard copied).
- **Settings:** enabled activities and their priority, hover delay, show on which displays,
  hide in full screen, size (compact/large), haptic feedback on trackpad.
- **Tech:** borderless non-activating `NSPanel` above the menu bar level, positioned with
  `NSScreen.auxiliaryTopLeftArea`/`auxiliaryTopRightArea` and `safeAreaInsets`; joins all
  Spaces. Now Playing: Apple restricted the private MediaRemote framework for third-party
  apps in macOS 15.4, so plan for a fallback (AppleScript for Music/Spotify, or a
  maintained adapter) and keep it isolated behind a `NowPlayingService`.

### 3.6 Screen Tools

- **Does:**
  - **Screenshot:** area, window, full screen, timer; pin as a floating window; copy/save.
  - **OCR:** select an area → recognised text is copied (and can go to a Quick Note).
    Includes QR/barcode reading.
  - **Colour picker:** system loupe; copies in your chosen format (HEX, RGB, HSL, SwiftUI,
    CSS); keeps a colour history.
  - **Screen recording:** area/window/screen, system audio + mic, optional click and
    keystroke overlay; export MP4 (GIF later).
- **Surfaces:** after capture, a **thumbnail lands in the Island** with actions (Copy,
  Save, Annotate, Pin, Add to Shelf, drag out). Recording shows a red-dot compact activity
  with elapsed time and a stop button. Floating Bar commands for every mode.
- **Settings:** save folder, filename pattern, format, after-capture action, shortcuts
  (optionally take over `⇧⌘3/4/5`; the user disables the system ones), OCR languages.
- **Tech:** ScreenCaptureKit (`SCScreenshotManager`, `SCStream`, `SCRecordingOutput` on
  macOS 15+), Vision text recognition, `NSColorSampler`. Needs **Screen Recording**
  permission (screenshot/recording/OCR) and **Microphone** for mic audio.

### 3.7 Clipboard History

- **Does:** remembers text, rich text, images, files, links and colours; search; pin
  favourites; paste as plain text; **paste stack** (copy several, paste in order);
  snippets with placeholders (`{date}`, `{clipboard}`).
- **Surfaces:** its own picker panel (`⇧⌘V`) built on Floating Bar components, `c ` prefix
  in the Floating Bar, drag items onto the Shelf, Island "Copied" flash (optional).
- **Interactions:** `↵` pastes into the previous app, `⌘↵` pastes as plain text,
  `⌘1…9` quick paste, `⌘P` pin, `⌫` delete.
- **Settings:** history length / age, ignored apps (password managers ignored by default),
  types to keep, sync off (local only), clear on quit.
- **Privacy:** honours `org.nspasteboard.ConcealedType` and `TransientType`, so password
  manager copies are never stored. History is stored locally and can be encrypted.
- **Tech:** polls `NSPasteboard.changeCount` (there's no change notification); pasting
  sends a synthetic `⌘V` (Accessibility permission). Apple has been previewing pasteboard
  privacy prompts, so the onboarding flow must handle a "Allow paste" permission too.

### 3.8 Shelf

- **Does:** a temporary holding area for files, images, text and links; drag things in,
  drag them out later (one, several, or all).
- **Surfaces:** Island drop zone (drag a file toward the notch), Shelf page in the expanded
  Island, Floating Bar pin, optional mini shelf at a screen edge.
- **Item actions:** AirDrop, Share, Copy, Reveal, Open With, Rename, Compress (zip),
  Convert image (PNG/JPEG/HEIC/WebP, resize), Merge PDFs, Copy path, Remove.
- **Settings:** keep a *reference* vs. *copy* of the file, auto-clear after N hours,
  remove after drag-out, max items.
- **Tech:** standard drag-and-drop (`NSDraggingDestination`/`onDrop`); detects a drag in
  progress by watching the drag pasteboard and the cursor position. No permissions.

### 3.9 Keyboard Shortcuts

- **Does:**
  - **Hyper/super key:** Caps Lock becomes `⌃⌥⇧⌘` when held and `Esc` (or Caps Lock)
    when tapped.
  - **Launch/focus:** `Hyper+B` → browser, `Hyper+O` → Obsidian; a second press
    hides or cycles windows.
  - **Open things:** file, folder, URL, Obsidian note.
  - **Run things:** any KKit command, a Shortcuts.app shortcut, a shell script.
  - **Leader sequences:** `Hyper+Space`, then `n`, `d` → "new daily note".
  - **Cheat sheet:** hold Hyper for 1 s to see all Hyper bindings as an overlay.
- **Surfaces:** Settings › Shortcuts (the global table) and Settings › Keyboard (Hyper key,
  app launchers, leader sequences), Floating Bar ("Assign hotkey…" action on any result).
- **Tech:** plain hotkeys use the Carbon `RegisterEventHotKey` API (no permissions).
  Hyper key and leader sequences need the shared `CGEventTap` (Input Monitoring +
  Accessibility). Caps Lock remap uses `hidutil` key mapping to an unused key, then the
  tap turns that key into the modifier combo.

### 3.10 Night Shift

- **Does:** warms the screen, from a gentle tint to **very high intensity**, beyond what
  macOS allows. Modes: *Warm* (classic), *Amber* (strong), *Darkroom* (red only, for
  night use), plus *Extra dim* (below the minimum brightness). Schedule: sunset→sunrise
  (computed from location or a set city), custom times, or manual.
- **Surfaces:** Quick Toggle (tap toggles, scroll changes intensity), menu bar slider,
  Floating Bar commands (`Night Shift 150%`), hotkeys for toggle/stronger/weaker.
- **Settings:** intensity (0–200%, where >100% is beyond the system maximum), mode,
  schedule, transition length, per-display enable, "Pause for 1 hour", "Disable in app X"
  (e.g. photo editors).
- **Tech:** colour is applied with per-display gamma tables (`CGSetDisplayTransferByTable`,
  public API), which can go well past macOS's Night Shift limit. Re-apply on display
  reconfiguration and wake. Optionally drive the built-in Night Shift through the
  private CoreBrightness API for the 0–100% range. Extra dim scales the gamma curve or
  uses a click-through black overlay. Note: other gamma-based apps (f.lux, some monitor
  tools) will conflict.

### 3.11 Quick Local Note (part of the Floating Bar)

- **Does:** capture a thought into your Obsidian vault (plain markdown files) in
  2 keystrokes. Targets:
  1. **Append to a file** (e.g. `Inbox.md`), optionally under a heading.
  2. **Daily note**: path pattern `Daily/{yyyy}/{yyyy-MM-dd}.md`, created from a template if
     missing.
  3. **New note in a folder**: first line becomes the title/filename.
- **Surfaces:** `n ` prefix or a dedicated hotkey turns the Floating Bar into a small
  editor; a pinned "Quick Note" widget in the pinned row; "Send to note" actions from
  Clipboard, OCR and Shelf.
- **Editor:** monospaced markdown with light syntax highlighting, `⌘↵` save & close,
  `⌘⇧↵` save & open in Obsidian, `Tab` switches target, an optional `#tag` / link
  autocomplete from the vault's file names.
- **Settings:** vault folder, default target, templates, timestamp format, include context
  (frontmost app, browser URL, selected text), open in Obsidian after save.
- **Tech:** writes files directly (atomic write, keep line endings and frontmatter);
  Obsidian picks up changes from disk. Opens notes via `obsidian://open?vault=…&file=…`.
  Folder access is remembered with a bookmark.

---

## 4. Suggested additional features

Grouped by how much they'd add versus how hard they are. ★ = recommended early, because
they reuse services the core features already need.

### High value, cheap (reuse existing services)

| Feature | What it does | Reuses |
|---|---|---|
| ★ **Quick Toggles pack** | Dark mode, hide desktop icons, show hidden files, Do Not Disturb/Focus, Bluetooth, Wi-Fi, eject all disks, empty Trash, lock screen | Commands, Quick Toggles |
| ★ **Audio devices & mic mute** | Global mic-mute hotkey with an Island indicator (great for calls), auto-switch output | Volume's audio service, Island |
| ★ **Mic/camera in-use indicator** | Island shows which app is using the mic/camera | Island, audio/video device state |
| ★ **Timer / Pomodoro / Stopwatch** | Countdown in the Island, notification at the end, optional Focus mode | Island, Commands |
| ★ **Calculator / units / currency** | `=` provider in the Floating Bar | Floating Bar |
| ★ **QR code scan & translate** | Scan QR on screen; translate OCR text on-device (Translation framework) | Screen Tools, Vision |
| **Next meeting** | Calendar's next event in the Island with a "Join" button for Zoom/Meet/Teams links | Island, EventKit |
| **Downloads watcher** | New files in Downloads appear in the Island/Shelf for quick drag-out | Shelf, Island |
| **Clean keyboard mode** | Lock all keys/trackpad for 60 s so you can wipe the keyboard | Input tap, Overlay |
| **Scroll direction per device** | Natural scrolling on trackpad, normal on mouse | Input tap |
| **Battery & Bluetooth device levels** | AirPods/mouse/keyboard battery in Stats and Island | Stats |

### High value, more work

| Feature | What it does | Notes |
|---|---|---|
| ★ **Window management** | Snap/tile with hotkeys and drag-to-edge, layouts, move to display | Accessibility API; macOS 15 added basic tiling, so focus on hotkeys and layouts |
| **Menu bar manager** | Hide/collapse other apps' menu bar icons; surface them in the Floating Bar | Fragile across macOS versions; pairs well with "menu bar items" in the Floating Bar |
| **Text expansion / snippets** | `;sig` → signature, date macros | Shares Clipboard's snippet store and the input tap |
| **External display brightness & volume** | DDC/CI control of external monitors from the brightness keys, in the same HUD | Displays service; works on most monitors |
| **Screenshot annotation editor** | Arrows, text, blur, crop, then copy/save | Builds on Screen Tools |
| **Scrolling capture** | Capture a long page by scrolling | Hard; later |
| **On-device AI actions** | Summarise/rewrite clipboard text, clean up a Quick Note, describe a screenshot, using Apple's on-device Foundation Models (macOS 26+) | Private, offline; Commands on clipboard/note/OCR items |
| **Battery charge limit** | Stop charging at 80% (AlDente-style) | Needs privileged helper + private SMC keys; advanced |
| **File actions / automations** | Folder rules (e.g. auto-move screenshots, convert HEIC→JPEG on drop) | Shelf's conversion actions, file watching |

### Nice-to-have

Keystroke visualiser (for screen recordings), screen ruler/pixel measure, "pin any
window on top", app-specific keyboard remaps, focus mode presets (hide apps, mute
notifications, start timer), Wi-Fi/network quick info, KKit plug-ins written as Shortcuts.

---

## 5. Visual language

| Token | Value |
|---|---|
| Spacing | 4-pt grid: 4 / 8 / 12 / 16 / 24 |
| Corner radius | 6 (controls), 10 (rows/tiles), 16 (panels), Island uses the notch radius |
| Materials | `.glassEffect` on macOS 26+, `.ultraThinMaterial` / `.hudWindow` below that; the Island is always solid black |
| Typography | SF Pro, system text styles; SF Mono for numbers in Stats, the note editor and colour values |
| Colour | Semantic system colours; one accent (follows system accent, overridable); status colours green/orange/red only for Stats alerts and recording |
| Icons | SF Symbols only, hierarchical rendering; each feature owns one symbol used everywhere |
| Motion | Spring (response 0.35, damping 0.8) for Island grow/shrink; 120 ms fades for HUDs; cross-fade under Reduce Motion |
| Sound/haptics | Off by default; optional trackpad haptic on Island snap and HUD steps |
| Accessibility | VoiceOver labels on every control, full keyboard navigation, respects Reduce Motion, Reduce Transparency and Increase Contrast |
