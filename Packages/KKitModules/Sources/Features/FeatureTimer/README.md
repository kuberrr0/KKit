# Timer

Countdown timers, Pomodoro and a stopwatch, in the Island. DESIGN.md §3.16.

- **Does:** several labeled countdowns at once (`timer 10m tea`, `1h30m`, `90s`,
  `25 min`), a Pomodoro cycle (25/5 with a 15-minute break every 4, all configurable,
  auto-start optional), and a stopwatch with laps. Timers are saved, so they survive a
  relaunch; ones that ended while KKit was closed are announced on launch.
- **Surfaces:** an Island activity per countdown, one for the Pomodoro and one for the
  stopwatch (progress ring on the left ear, time on the right; expanded with controls),
  an Island “Timer” page with quick starts, a Quick Toggle tile (“Pomodoro”), and
  commands `timer.start`, `timer.startLabeled`, `timer.cancelAll`, `timer.pomodoro`,
  `timer.pausePomodoro`, `timer.skipPomodoro`, `timer.stopwatch`, `timer.lap`,
  `timer.resetStopwatch`. At the end: an Island HUD, a sound, and optionally a system
  notification.
- **APIs:** `IslandService`, `NotificationService`, `StorageService` (`state.json`).
- **Permissions:** Notifications (optional).
- **Limits:** the clock in the Island ticks only while it's on screen (`TimelineView`),
  and the feature sleeps until the next deadline, so nothing polls. "Start Focus during
  Pomodoro" (via Shortcuts) and a history of completed sessions are for later.
