# Volume & Audio

Output volume, mute, device switching, global mic mute, the volume keys, push-to-talk
and per-app volume. DESIGN.md §3.1.

- **Does:** finer volume steps (1–10%), a volume limit (changes above it are pulled
  back), output/input switching from the menu or by name (`volume.setOutput AirPods`),
  auto-switch priority lists for output and input, one-key mic mute for every app.
  Takes over the volume keys (on by default; KKit's step and limit, the Island HUD
  instead of macOS's, ⇧⌥ for quarter steps). Push-to-talk (the mic stays muted until
  the key is held) and push-to-mute, with any key or a modifier on its own (Right ⌥,
  fn). Per-app volume: a slider per app in Settings and under “App volume” in the
  menu, remembered by bundle id.
- **Surfaces:** menu bar section (order 100) with a slider and device pickers, Quick
  Toggle tile (“Mic Mute”), Island HUDs for volume, mute, mic and device changes,
  scrolling on the Island changes the volume (⌥ for quarter steps). Commands
  `volume.up`, `volume.down`, `volume.set` (`vol 30`), `volume.toggleMute`,
  `volume.toggleMicMute` (⌃⌥M), `volume.setOutput`, `volume.setInput`,
  `volume.nextOutput`.
- **APIs:** `AudioService` (CoreAudio virtual main volume and mute; input devices
  without a mute control are muted by setting their volume to 0 and restoring it;
  per-app volume through Core Audio process taps), `IslandService` for HUDs and the
  scroll handler, `InputTapService` (`context.input`: media keys at `.normal`, the
  push keys at `.high`).
- **Permissions:** Accessibility, optional: for the volume keys and push-to-talk.
  Turning an app down the first time asks to capture audio (“KKit would like to
  access audio from other apps”).
- **Limits:** an app turned down plays through KKit's tap, so if KKit quits it plays
  at full volume again. Apps can only be turned down, not above 100%. The red “mic
  muted” ear in the Island belongs to Privacy Indicator, which shows it while an app is
  using the muted microphone.
