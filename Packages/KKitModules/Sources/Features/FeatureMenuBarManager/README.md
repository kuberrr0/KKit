# Menu Bar Manager

Tidies the menu bar: hides icons behind a ‹ chevron, keeps some out of the way for
good, and shows hidden and behind-the-notch icons in a drop-down bar. DESIGN.md §3.13.

- **Does:**
  - Three sections, set by where icons sit relative to KKit's items. Right to left:
    **Always Shown** icons, the **‹ chevron** (which is the Hidden divider too),
    **Hidden** icons, the Always Hidden divider (optional), **Always Hidden** icons.
    ⌘-drag icons across the chevron or the divider to move them, as you would any menu
    bar icon. Holding ⌘ over the menu bar (or ⌘-clicking it) shows every section
    first, because a collapsed section is too long to drag an icon past.
  - Click the chevron (or point at it, a setting) to show hidden icons; ⌥-click or
    right-click shows always-hidden ones too. They hide again after 10 s (5–60 s or
    never), but not while a menu is open or the pointer is on the menu bar.
  - **Drop-down bar:** on screens with a notch (or always, or never — a setting) the
    chevron opens a bar under the menu bar with the icons that aren't in it: behind
    the notch, hidden, always hidden. Clicking one shows its section for a moment and
    opens its menu, because apps open menus under their icon.
  - Holding ⌘ with the pointer on the menu bar shows every icon while it's held, for
    ⌘-dragging.
  - Settings lists every icon by section; drag between the lists or use an icon's ⋯
    menu to move it (KKit does the ⌘-drag for you). Tighter icon spacing.
  - The Floating Bar's `m ` search lists menu bar icons next to the app's menu items.
- **Surfaces:** commands `menuBarManager.toggle` (Quick Toggle "Hidden Icons"),
  `menuBarManager.showAll`, `menuBarManager.dropDown`, `menuBarManager.hide`; the chevron
  and dividers (status items owned by `MenuBarItemsService`); the drop-down bar (an
  `OverlayService` panel at `.statusBar`); Settings › Menu Bar Manager; `m ` results
  through `MenuBarIconsServicing`, which the feature publishes.
- **APIs:** `MenuBarItemsService` (`context.menuBarItems`), `InputTapService` (`.low`,
  flags-changed only, for ⌘), `OverlayService`, `ScreenCaptureService` (pictures of
  icons by window id).
- **Permissions:** none to hide icons. Accessibility to list, open and move them and for
  ⌘ over the menu bar; Screen Recording for pictures of icons (app icons otherwise).
- **Limits:** this relies on how macOS lays out status items and can break with any
  macOS update; turning the feature off (or quitting KKit) brings every icon back.
  KKit's own icons (the KKit menu, Stats) aren't listed, though they can be ⌘-dragged
  into a section. Moving icons from Settings posts a ⌘-drag, which some icons ignore.
  Pictures exist only for icons that have been on screen since KKit started. The clock
  and Control Center can't move. Icon spacing applies to apps as they relaunch.
