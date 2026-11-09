# Clean Mode

Locks the keyboard (and optionally the trackpad and mouse) so you can wipe it.
DESIGN.md §3.18.

- **Does:**
  - **Keyboard only** (default): a cover on every display says "Keyboard locked — clean
    away", with a countdown and an Unlock button to click.
  - **Everything:** keyboard, trackpad and mouse are blocked and the pointer is
    frozen; only the countdown (30/60/90/120 s) unlocks.
  - Media and brightness keys are blocked too. It always unlocks after 2 minutes.
- **Surfaces:** commands `cleanMode.start` (toggle, uses the default mode),
  `cleanMode.lockKeyboard`, `cleanMode.lockEverything`, `cleanMode.stop`; a Quick
  Toggle tile; the cover (an `OverlayService` panel per display at `.screenSaver`);
  Settings › Clean Mode.
- **APIs:** `InputTapService` (`context.input`, priority `.safety`: key down, flags and
  media keys, plus mouse buttons and armed motion in "everything" mode), `OverlayService`,
  `CGAssociateMouseAndMouseCursorPosition`.
- **Permissions:** Accessibility (the event tap). Refuses to lock if the tap isn't
  running.
- **Limits:** the power button and Touch ID can't be blocked. Key releases (and letting
  go of every modifier) are let through so no key stays stuck in other apps.
