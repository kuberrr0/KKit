# Quick Toggles

One-tap system switches and actions. DESIGN.md §3.14.

- **Switches:** Dark Mode, Hide Desktop (icons), Hidden Files in Finder, Wi-Fi, Dock
  auto-hide, menu bar auto-hide. **Actions:** Eject All Disks, Empty Trash, Lock
  Screen, Sleep Displays, Start Screen Saver.
- **Surfaces:** menu bar grid tiles (which ones and their order are set in Settings;
  default Dark Mode, Hide Desktop, Wi-Fi, Lock Screen) and a command for each,
  `quickToggles.<name>` (`quickToggles.darkMode`, `quickToggles.wifi`, …), so each can
  have a hotkey. Eject and Empty Trash confirm with an Island HUD.
- **APIs:** `SystemActionsService` (AppleScript for dark mode, Dock, menu bar and Trash;
  Finder defaults + relaunch for hidden files; CoreWLAN for Wi-Fi; `NSWorkspace` for
  eject; `SACLockScreenImmediate` loaded dynamically, with a fallback, for lock;
  `pmset displaysleepnow` for sleep), `OverlayService` for Hide Desktop: a
  click-through panel just above the desktop icons showing each screen's wallpaper,
  so Finder isn't restarted.
- **Permissions:** Automation (optional), asked per target app the first time.
- **Limits:** Bluetooth power has no public API and Focus needs a Shortcuts shortcut
  KKit installs; both are left for later. “Keep the screen saver off” is Power's
  Awake tile with “keep the display awake” on.
