# Keyboard

The Hyper key, key bindings, leader sequences and a cheat sheet. DESIGN.md §3.9.

- **Does:**
  - **Hyper key:** Caps Lock is ⌃⌥⇧⌘ while held and Escape (or nothing) when tapped.
    KKit maps Caps Lock to F18 with `hidutil` (kept for the login session, removed
    when the feature stops; other `hidutil` mappings are kept) and the tap adds the
    four modifiers to every key pressed while F18 is down, so other apps' shortcuts see
    Hyper too.
  - **Key bindings:** any key (usually Hyper + a letter) opens an app (pressed again
    while the app is in front: hide it or cycle its windows with ⌘\`), a link, a file
    or folder, runs a KKit command (with a value), a Shortcuts.app shortcut or a shell
    script (`zsh -lc`).
  - **Leader sequences:** the leader key (Hyper Space), then keys (`n`, `d`) run an
    action. A panel lists what can follow; ⎋ cancels; a sequence that's also the start
    of a longer one runs after the timeout (2 s).
  - **Cheat sheet:** hold Hyper alone for 1 s (or run `keyboard.showCheatSheet`) to
    see every Hyper binding, the leader key and KKit commands bound to Hyper.
- **Surfaces:** Settings › Keyboard; commands `keyboard.showCheatSheet`,
  `keyboard.startLeader`, `keyboard.toggleHyper`; overlay panels for the cheat sheet
  and leader sequence.
- **APIs:** `InputTapService` (`context.input`, priority `.high`, key down/up; its
  `setCapsLockRemap`), `CommandRunnerService` (`context.commandRunner`), `OverlayService`,
  `NSWorkspace`, `/usr/bin/shortcuts`.
- **Permissions:** Accessibility (the event tap). macOS may also list KKit under Input
  Monitoring.
- **Limits:** bindings and the leader key don't fire while KKit's own Settings window
  is in front, so they can be recorded. If KKit quits without stopping (a crash), Caps
  Lock stays mapped to F18 until you log out. Caps Lock's own lock is gone while Hyper
  is on. A Floating Bar "Assign hotkey…" action is left for later.
