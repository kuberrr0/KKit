# Window Management

Snapping, moving and resizing other apps' windows, and saved layouts. DESIGN.md §3.12.

- **Does:**
  - **Snap with keys:** ⌃⌥ + ←/→/↑/↓ (halves; pressing again cycles ½ → ⅓ → ⅔),
    U/I/J/K (quarters), D/F/G (thirds), E/T (two thirds), ↩ (maximise), C (centre).
    "Almost maximise" has no default key. ⌃⌥⌫ puts the window back where it was
    before KKit first moved it. ⌃⌥⌘ ←/→ moves it to the previous/next display,
    keeping its place and size relative to the screen. ⌃⌥ =/- grows or shrinks it.
  - **Drag to snap:** drag a window by its title bar to a screen edge (sides: halves,
    top: maximise) or corner (quarters); a preview shows where it'll go. Off while
    macOS 15's own edge tiling is on, unless "Leave it to macOS" is turned off.
  - **Modifier + mouse:** hold ⌃⌥ and drag anywhere in a window to move it; right-drag
    (or ⌃⌥⇧ + drag) resizes from the nearest corner or edge. ⌃⌥ + double-click
    maximises or restores.
  - **Layouts:** save where every visible window is ("Coding") and restore it from
    Settings, the Floating Bar (`Layout: Coding`) or `windows.restoreLayout`. Windows are
    matched by app, then title.
  - A gap between snapped windows, and apps KKit leaves alone.
- **Surfaces:** Settings › Window Management; commands `windows.<snap>` (one per
  position: `windows.leftHalf`, `windows.topRight`…), `windows.snap` (`win left`),
  `windows.restore`, `windows.nextDisplay`, `windows.previousDisplay`, `windows.grow`,
  `windows.shrink`, `windows.saveLayout`, `windows.restoreLayout`; the "Window Layouts"
  search provider; a snap-preview overlay panel.
- **APIs:** `WindowService` (`context.windows`, Accessibility AXUIElement windows),
  `InputTapService` (`context.input`: flags at `.normal` arm mouse events while the
  modifiers are held; left mouse down/up at `.low` arm drags for drag-to-snap),
  `OverlayService` (screens, the preview), `FeatureStorage` (`layouts.json`).
- **Permissions:** Accessibility.
- **Limits:** full-screen windows and some apps' panels can't be moved. Windows are
  identified for Restore only while KKit runs. A layout restores only windows that are
  open; it doesn't launch apps. Apps that ignore Accessibility size requests (some
  Electron apps, Terminal's character grid) land close to, not exactly on, the target.
