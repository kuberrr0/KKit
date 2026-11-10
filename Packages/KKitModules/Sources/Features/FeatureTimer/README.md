# Timer

Countdown timers and a stopwatch, in the Island. DESIGN.md §3.16.

- **Does:** several labeled countdowns at once (`timer 10m tea`, `1h30m`, `90s`,
  `25 min`) and a stopwatch with laps. Timers are saved, so they survive a relaunch;
  ones that ended while KKit was closed are announced on launch.
- **Surfaces:** an Island activity per countdown and one for the stopwatch (progress
  ring on the left ear, time on the right; expanded with controls), an Island “Timer”
  page with quick starts, and commands `timer.start`, `timer.startLabeled`,
  `timer.cancelAll`, `timer.stopwatch`, `timer.lap`, `timer.resetStopwatch`. At the
  end: an Island HUD, a sound, and optionally a system notification.
- **APIs:** `IslandService`, `NotificationService`, `StorageService` (`state.json`).
- **Permissions:** Notifications (optional).
- **Limits:** the clock in the Island ticks only while it's on screen (`TimelineView`),
  and the feature sleeps until the next deadline, so nothing polls. A history of
  completed timers is for later. Pomodoro was removed at KV's request (2026-11-09).
