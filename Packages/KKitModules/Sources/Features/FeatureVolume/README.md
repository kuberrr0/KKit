# Volume & Audio

Output volume, mute, device switching and global mic mute. DESIGN.md §3.1.

- **Does:** finer volume steps (1–10%), a volume limit (changes above it are pulled
  back), output/input switching from the menu or by name (`volume.setOutput AirPods`),
  auto-switch priority lists for output and input, one-key mic mute for every app.
- **Surfaces:** menu bar section (order 100) with a slider and device pickers, Quick
  Toggle tile (“Mic Mute”), Island HUDs for volume, mute, mic and device changes,
  scrolling on the Island changes the volume (⌥ for quarter steps). Commands
  `volume.up`, `volume.down`, `volume.set` (`vol 30`), `volume.toggleMute`,
  `volume.toggleMicMute` (⌃⌥M), `volume.setOutput`, `volume.setInput`,
  `volume.nextOutput`.
- **APIs:** `AudioService` (CoreAudio virtual main volume and mute; input devices
  without a mute control are muted by setting their volume to 0 and restoring it),
  `IslandService` for HUDs and the scroll handler.
- **Permissions:** none.
- **Limits:** the volume keys still show macOS's own HUD; taking them over needs the
  shared event tap (M4), as does push-to-talk. Per-app volume (Core Audio process
  taps) is M4 too. The red “mic muted” ear in the Island belongs to Privacy Indicator,
  which shows it while an app is using the muted microphone.
