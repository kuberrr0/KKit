# Privacy Indicator

Shows in the Island while an app uses the microphone or a camera. DESIGN.md §3.15.

- **Does:** a compact Island activity (priority high) with an orange mic and/or a
  green camera and the app's name; the mic ear turns red and struck through while the
  microphone is muted, and clicking it mutes or unmutes. The expanded page lists the
  apps using the mic. An optional 7-day log of use, stored on this Mac only.
- **Surfaces:** Island activity `inUse`, Settings page with the log, command
  `privacyIndicator.clearLog`.
- **APIs:** `DeviceUsageService` (CoreAudio `kAudioDevicePropertyDeviceIsRunningSomewhere`
  and audio process objects for which app is capturing; CoreMediaIO
  `kCMIODevicePropertyDeviceIsRunningSomewhere` for cameras), `AudioService` for the
  input mute state and toggling it, `StorageService` for `log.json`.
- **Permissions:** none (observing doesn't need microphone or camera access).
- **Limits:** macOS doesn't expose which app uses a camera, so it shows “Camera” without
  a name. App attribution for the mic needs macOS 14's audio process objects and is
  refreshed every few seconds while the mic is in use.
