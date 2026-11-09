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
| **Floating Bar** | Launcher: search, commands, Quick Note, clipboard, calculator | Hotkey (default `⌥Space`, or `Hyper+Space`) |
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

This is a **Dynamic Island–style overlay around the MacBook notch** (confirmed): it shows
live activities, replaces the system HUDs, and acts as a drop target. In the UI it's
called **Island**, so it isn't confused with the macOS Dock or the Floating Bar.

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

A **launcher**: press the hotkey, type, press `↵`. It's the keyboard front door to
everything in KKit, your files, the web, System Settings and other apps' menus.

```
Empty query                                    Typing
┌──────────────────────────────────────────┐   ┌──────────────────────────────────────────────────────────────┐
│ 🔍  Search or type a command…       ⌘K   │   │ 🔍  night sh▌                              [All ▾]  ⌘K      │
├──────────────────────────────────────────┤   ├─────────────────────────────────────┬────────────────────────┤
│ FAVOURITES                               │   │ 🌙 Night Shift: Toggle      ⌃⌥N     │  Night Shift           │
│  📁 Projects            ~/Code           │   │ 🌙 Night Shift: Set intensity…      │  Currently off         │
│  🌐 GitHub              github.com       │   │ 🌙 Night Shift: Darkroom mode       │  Schedule: sunset→…    │
│  📝 Inbox.md            Quick Note       │   │ ⚙︎  System Settings › Displays › …  │                        │
│ RECENT                                   │   │ 📄 night-shift-notes.md  ~/Vault    │  [Toggle] [Settings…]  │
│  🪟 Window: Left Half          ⌃⌥←       │   ├─────────────────────────────────────┴────────────────────────┤
│  🧮 1920/1080 = 1.7778                   │   │ ↵ Run   ⌘↵ Run & keep open   ⌘K Actions   Tab Preview   ⎋    │
└──────────────────────────────────────────┘   └──────────────────────────────────────────────────────────────┘
```

- **Empty state** shows *Favourites* (anything you starred with ⌘K → *Add to Favourites*)
  and *Recent* results, so common things are one `↵` away.
- **Search sources ("providers")** are contributed by features. Each has a prefix to scope
  the search:

  | Prefix | Source | Notes |
  |---|---|---|
  | *(none)* | Everything, ranked by frecency + fuzzy match | |
  | `a ` | Applications, A to Z | Apps also show in every search; `a ` alone lists them all |
  | `>` | Commands (all KKit features + system actions) | Lock, sleep, empty Trash, dark mode, eject all, window layouts… |
  | `f ` | Files & folders | Spotlight (`NSMetadataQuery`) |
  | `w ` | Web: URLs, search engines, bookmarks, open tabs | Tabs need Automation permission per browser |
  | `/` | System Settings panes | Deep links via `x-apple.systempreferences:` |
  | `m ` | Menu items of the frontmost app, and menu bar icons (incl. hidden ones) | Accessibility API; shares data with the Menu Bar Manager |
  | `c ` | Clipboard history | |
  | `n ` | Quick Note | Switches the panel into the note editor |
  | `=` | Calculator, units, currency, dates, time zones | Also detected automatically: typing `2^10` shows the result first |

- **Commands with arguments** parse inline: `timer 25m`, `awake 2h`, `vol 30`,
  `night 150`, `win left`. The command's parameter type (duration, percent, choice) does
  the parsing, so every feature gets this for free.
- **⌘K** opens an action menu for the selected result (Reveal in Finder, Copy path,
  Open with…, Add to Shelf, Add to Favourites, Assign hotkey…). Actions are also
  contributed by features.
- **Placement:** centred on the screen with the cursor; optional "top of screen" position.
- Remembers the last query for 30 s so ⎋ then reopen doesn't lose work.
- **Modes** (Clipboard History, Quick Note) fill the bar. ⎋ goes back to search when the
  mode was opened from the bar (a prefix or a result), and closes the bar when it was
  opened by its own hotkey; the ‹ in the mode's header always goes back to search. The
  bar's hotkey always opens search, never a mode it was last hidden in.

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

| # | Feature | Origin |
|---|---|---|
| 3.1 | Volume & Audio (incl. device switching, mic mute) | Original + recommended |
| 3.2 | Floating Bar (launcher) | Original |
| 3.3 | Statistics | Original |
| 3.4 | Power (always-on) | Original |
| 3.5 | Island | Original ("Floating Dock") |
| 3.6 | Screen Tools (incl. QR scan & translate) | Original + recommended |
| 3.7 | Clipboard History | Original |
| 3.8 | Shelf | Original |
| 3.9 | Keyboard Shortcuts | Original |
| 3.10 | Night Shift | Original |
| 3.11 | Quick Local Note | Original |
| 3.12 | Window Management (incl. modifier + mouse move/resize) | Recommended |
| 3.13 | Menu Bar Manager | Recommended |
| 3.14 | Quick Toggles | Recommended |
| 3.15 | Privacy Indicator (mic & camera in use) | Recommended |
| 3.16 | Timer, Pomodoro & Stopwatch | Recommended |
| 3.17 | Calculator, Units & Currency | Recommended |
| 3.18 | Clean Mode (clean keyboard) | Recommended |

### 3.1 Volume & Audio

Includes the recommended *Audio devices & mic mute* feature.

- **Does:**
  - Replaces the system volume HUD with an Island HUD; finer volume steps; optional
    max-volume limit.
  - **Per-app volume mixer** (turn Zoom up and Music down independently).
  - **Output and input device switching**, with an auto-switch priority list
    ("AirPods when connected, else Studio Display, else built-in speakers").
  - **Global mic mute**: one hotkey mutes the current input device in every app. While
    muted and an app is using the mic, the Island shows a red 🎤̸ ear; click it to unmute.
    Optional **push-to-talk** (hold a key to unmute) and **push-to-mute**.
- **Surfaces:** Island HUD and mic-muted indicator, menu bar sliders + device pickers,
  Quick Toggle tile (mic mute), Floating Bar commands (`vol 30`, `Output: AirPods`,
  `Mute mic`).
- **Interactions:** media keys show the Island HUD; scrolling on the Island changes volume;
  `⌥` + scroll gives fine steps; click the device name to switch output.
- **Settings:** step size (1–10%), volume limit, HUD style, per-app volumes (remembered),
  device priority lists for output and input, mic-mute hotkey, push-to-talk key,
  "play a sound on mute/unmute".
- **Tech:** CoreAudio (`AudioObjectSetPropertyData` on the device's virtual main volume and
  `kAudioDevicePropertyMute` on the input scope; falls back to input volume 0 for
  devices without a mute control); per-app volume via Core Audio process taps
  (macOS 14.2+); volume-key takeover and push-to-talk need the shared `CGEventTap`
  (Accessibility permission).

### 3.2 Floating Bar

See §2.3 for the full design. It's a *host*: on its own it only knows how to show
results; files, web, settings, menu items, clipboard, notes and commands are all
providers contributed by features.

- **Settings:** hotkey, which providers are on and their prefixes, favourites, placement,
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
  - **QR & barcode scan:** select an area (or scan the whole screen) → the link or text is
    copied, with "Open link" as the main action.
  - **Translate:** select an area → OCR → translated on-device; the result shows in a
    small floating card with Copy. Also works on clipboard text and Floating Bar input
    (`tr hola`).
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
  macOS 15+), Vision text recognition and barcode detection, the Translation framework
  (on-device, macOS 15+; languages download on first use), `NSColorSampler`. Needs **Screen Recording**
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
  Island, *Add to Shelf* action on any Floating Bar result, optional mini shelf at a screen edge.
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
  editor; "Send to note" actions from
  Clipboard, OCR and Shelf.
- **Editor:** monospaced markdown with light syntax highlighting, `⌘↵` save & close,
  `⌘⇧↵` save & open in Obsidian, `Tab` switches target, an optional `#tag` / link
  autocomplete from the vault's file names.
- **Settings:** vault folder, default target, templates, timestamp format, include context
  (frontmost app, browser URL, selected text), open in Obsidian after save.
- **Tech:** writes files directly (atomic write, keep line endings and frontmatter);
  Obsidian picks up changes from disk. Opens notes via `obsidian://open?vault=…&file=…`.
  Folder access is remembered with a bookmark.

### 3.12 Window Management

- **Does:**
  - **Snap with hotkeys:** halves, thirds, two-thirds, quarters, maximise, almost-maximise,
    centre, restore, move to next/previous display, grow/shrink. Repeating a hotkey
    cycles sizes (`⌃⌥←` → ½ → ⅓ → ⅔).
  - **Drag to snap:** drag a window to an edge or corner and a translucent preview shows
    where it'll land. (macOS 15+ has basic tiling; KKit can replace it or stay out of its
    way.)
  - **Modifier + mouse to move and resize:** hold a modifier (default `⌃⌥`) and
    - **left-drag anywhere in a window** to move it (no need to find the title bar),
    - **right-drag** (or `⌃⌥⇧` + left-drag) to **resize from the nearest corner/edge**,
    - optional: modifier + scroll to resize around the centre, modifier + double-click to
      maximise/restore.
    The window under the cursor is used, not just the active one, and is raised and
    focused on drag (setting).
  - **Layouts:** save the current arrangement of apps as a named layout and restore it
    with a command or hotkey (`Layout: Coding`), optionally tied to a display setup.
- **Surfaces:** Floating Bar commands (`win left`, `Layout: Coding`), hotkeys, snap preview
  overlay, Settings page with a visual grid of snap hotkeys.
- **Settings:** modifier key(s) for move and resize, which mouse button resizes, resize
  from nearest corner vs. always bottom-right, raise on drag, snap while modifier-dragging,
  gaps between windows, excluded apps (games, remote desktops), override macOS tiling.
- **Tech:** Accessibility API (`AXUIElement` position/size attributes;
  `AXUIElementCopyElementAtPosition` to find the window under the cursor). Window updates
  are throttled to the display refresh rate because AX calls are slow. Modifier + mouse
  must *swallow* the click so the app underneath doesn't receive it, which is only
  possible with an event tap, so it uses the shared **InputTapService** (see
  [ARCHITECTURE.md §7](ARCHITECTURE.md#7-shared-services)). Needs **Accessibility**.

> **Where does modifier + mouse belong?** In **Window Management**. "Input" in KKit is a
> shared *service* (the single event tap), not a feature: Window Management, Keyboard,
> Clean Mode and Volume all *use* it. The behaviour belongs to the feature whose job it
> is (moving windows); the plumbing belongs to the service.

### 3.13 Menu Bar Manager

- **Does:** tidies the menu bar, which matters a lot on notched MacBooks where icons
  disappear behind the notch.
  - Three sections: **Always shown**, **Hidden** (revealed on click/hover of a `‹`
    chevron), and **Always hidden** (only reachable from the drop-down bar or the
    Floating Bar).
  - **Drop-down bar:** hidden icons (and icons pushed behind the notch) appear in a
    small bar under the menu bar, and clicking one opens its menu as normal.
  - Auto-hide again after N seconds; show all while `⌘` is held over the menu bar.
  - Rearrange: `⌘`-drag icons into sections, or use the Settings list.
  - Spacing: tighter icon spacing so more fit.
- **Surfaces:** a chevron/separator status item, the drop-down bar (an overlay panel),
  Floating Bar `m ` provider ("search menu bar icons"), Settings page with a draggable
  list of current icons.
- **Settings:** sections, reveal on hover vs. click, auto-hide delay, show drop-down bar
  instead of expanding in place, icon spacing.
- **Tech:** the established technique: separator status items whose length grows to push
  hidden items off-screen; listing other apps' items via the window list and
  Accessibility; opening an item by pressing its AX element. Needs **Accessibility**, and
  **Screen Recording** to show item images in the drop-down bar. This is the most fragile
  feature across macOS updates, so it's isolated in its own service and feature flag,
  and should step back where newer macOS versions offer their own menu bar controls.

### 3.14 Quick Toggles

- **Does:** one-tap system switches, each also a command and hotkey:
  dark mode, hide desktop icons, show hidden files, Do Not Disturb/Focus, Wi-Fi,
  Bluetooth, eject all disks, empty Trash, lock screen, sleep displays, keep
  screen-saver off, toggle Dock auto-hide, toggle menu bar auto-hide.
- **Surfaces:** menu bar popover grid (§2.1), Floating Bar commands, hotkeys.
- **Settings:** which toggles appear in the grid and their order.
- **Tech:** a mix, chosen per toggle to avoid restarts where possible: Wi-Fi via CoreWLAN;
  hide desktop icons via a click-through window showing the wallpaper (no Finder restart);
  hidden files via Finder defaults + relaunch; dark mode, Dock and empty Trash via
  AppleScript (Automation permission, asked per target app); Focus via a Shortcuts.app
  shortcut that KKit installs; eject via `NSWorkspace`; lock/sleep via system calls.
  Bluetooth power has no public API, so it's behind the private-API rule.

### 3.15 Privacy Indicator (mic & camera in use)

- **Does:** shows in the Island when any app is using the **microphone** or **camera**,
  with the app's icon where macOS exposes it. Pairs with mic mute: the ear turns red when
  you're muted, and clicking it toggles mute.
- **Surfaces:** Island compact activity (high priority), expanded page listing the apps
  currently using each device, optional log of recent use.
- **Settings:** show for mic / camera / both, show app names, keep a 7-day usage log.
- **Tech:** CoreAudio `kAudioDevicePropertyDeviceIsRunningSomewhere` and audio process
  objects (which process is capturing input) for the mic; CoreMediaIO
  `kCMIODevicePropertyDeviceIsRunningSomewhere` for cameras (camera app attribution isn't
  public, so it shows "Camera in use" without a name). No permissions needed to observe.

### 3.16 Timer, Pomodoro & Stopwatch

- **Does:** countdown timers (several at once, with labels: `timer 10m tea`), Pomodoro
  cycles (25/5 with a long break every 4, all configurable), and a stopwatch with laps.
- **Surfaces:** Island compact activity with the remaining time (progress ring on the
  left ear), expanded page with controls, Floating Bar commands with inline durations,
  menu bar tile, end-of-timer Island alert + sound + optional system notification.
- **Settings:** Pomodoro lengths, sounds, "start Focus during Pomodoro" (via Shortcuts),
  auto-start next interval, keep a history of completed sessions.
- **Tech:** pure app logic; schedules a `UNNotification` as a backup so a timer still
  fires if KKit is restarted.

### 3.17 Calculator, Units & Currency

- **Does:** maths (`(1920/1080)*100`, `2^10`, `sqrt 2`, percentages), units
  (`5 ft in cm`, `72 F to C`, `3 GB in MB`), currency (`100 usd in inr`), dates
  (`today + 45 days`, `days until dec 25`), time zones (`5pm PST in IST`), and base
  conversion (`0xff in dec`).
- **Surfaces:** Floating Bar `=` prefix, and automatic: if the root query looks like
  maths, the result is the first row. `↵` copies the result, `⌘↵` pastes it.
- **Settings:** decimal places, default currency, refresh rates daily (on/off),
  thousands separator.
- **Tech:** a small safe expression parser (not `NSExpression`, which can crash on bad
  input), Foundation `Measurement` for units, a free exchange-rate API cached for 24 h
  (works offline with the last rates).

### 3.18 Clean Mode (clean keyboard)

- **Does:** locks the keyboard (and optionally the trackpad/mouse) so you can wipe it
  without typing anything.
  - **Keyboard only** (default): a full-screen overlay shows "Keyboard locked — clean
    away" with a countdown and an **Unlock** button you click.
  - **Everything locked:** keyboard + trackpad + mouse, with a fixed countdown
    (30/60/90 s) as the only way out.
  - Media and brightness keys are blocked too; it auto-unlocks after 2 minutes no matter
    what, as a safety net.
- **Surfaces:** Floating Bar command, Quick Toggle tile, hotkey, the overlay.
- **Settings:** default mode, countdown length.
- **Tech:** the shared InputTapService consumes all key, flags-changed, system-defined
  (media key) and optionally mouse events; OverlayService draws the overlay on every
  display. The power/Touch ID button can't be blocked, which the overlay says.
  Needs **Accessibility** + **Input Monitoring**.

---

## 4. More feature ideas (not yet planned)

Everything that was starred, plus Clean Mode and the Menu Bar Manager, has moved into §3.
These are the remaining ideas, for later.

### Cheap (reuse existing services)

| Feature | What it does | Reuses |
|---|---|---|
| **Next meeting** | Calendar's next event in the Island with a "Join" button for Zoom/Meet/Teams links | Island, EventKit |
| **Downloads watcher** | New files in Downloads appear in the Island/Shelf for quick drag-out | Shelf, Island |
| **Scroll direction per device** | Natural scrolling on trackpad, normal on mouse | Input tap |
| **Battery & Bluetooth device levels** | AirPods/mouse/keyboard battery in Stats and Island | Stats |

### More work

| Feature | What it does | Notes |
|---|---|---|
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
| App and menu bar icon | "Island K": the notch Island above a K whose stem and arms are separate pieces (plug-in modules). Flat solid colours, no gradients. Sources and generator in `Design/Icons/`; the menu bar icon is a monochrome template PDF |
| Motion | Spring (response 0.35, damping 0.8) for Island grow/shrink; 120 ms fades for HUDs; cross-fade under Reduce Motion |
| Sound/haptics | Off by default; optional trackpad haptic on Island snap and HUD steps |
| Accessibility | VoiceOver labels on every control, full keyboard navigation, respects Reduce Motion, Reduce Transparency and Increase Contrast |
