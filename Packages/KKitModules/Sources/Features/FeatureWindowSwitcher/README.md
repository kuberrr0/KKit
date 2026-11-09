# Window Switcher

Switch between windows, not just apps, with live previews. Takes over ⌘Tab.
DESIGN.md §3.19.

- **Does:**
  - Hold ⌘ and press Tab: the switcher shows every window on the current Space front
    to back (most recent first), then minimised windows and hidden apps' windows, then
    apps with no open windows. The previous window is selected (the frontmost window is
    first), so ⌘Tab and let go flips between two windows. A quick ⌘Tab never shows the
    panel (it appears after 80 ms).
  - Tab / → next, ⇧Tab / ← previous, ↑/↓ by row, ↩ or Space switches, ⎋ or a click
    outside cancels, W closes the selected window, Q quits its app, H hides it.
    Letting go of the modifier switches. Hover selects, click switches.
  - Live previews (Screen Recording) or app icons; three preview sizes. Tiles shrink to
    fit many windows and the grid scrolls past 80 % of the screen height.
  - The modifier can be ⌘ (default), ⌥ or ⌃, or the shortcut turned off and the switcher
    opened only by command.
- **Surfaces:** the switcher panel (`OverlayService`, `.screenSaver` level, on the
  screen with the pointer); command `windowSwitcher.show` ("Switch Windows", stays open
  until you choose); Settings › Window Switcher.
- **APIs:** `InputTapService` (`context.input`: key down/up and flags at `.high`; left
  and right mouse down only while open, to cancel on clicks elsewhere),
  `WindowService.switchableWindows`, `raise`, `close`, `activateApp`
  (`context.windows`), `ScreenCaptureService.windowThumbnails` (`context.screenCapture`,
  only while the panel shows), `NSWorkspace` for running apps, activation order, hide
  and quit.
- **Permissions:** Accessibility; Screen Recording for previews (optional).
- **Limits:** windows on other Spaces and full-screen windows aren't listed (their apps
  show as app tiles, and switching to one moves to its Space). Minimised windows'
  previews are often blank (macOS keeps no live picture of them), so they may show the
  app icon. ⌘Tab passes to macOS while secure input is on (password fields), because
  event taps don't see keys then. On macOS 15 and later, macOS may periodically ask
  whether KKit may keep capturing the screen.
