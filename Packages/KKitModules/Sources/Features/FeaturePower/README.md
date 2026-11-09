# Power

Keeps the Mac (and optionally the display) awake. DESIGN.md §3.4.

- **Modes:** indefinitely, for a duration, until a time (`power.awakeUntil` takes
  "17:30" or "5pm"), and automatic rules: while the power adapter is connected, while
  an external display is connected, while chosen apps are running.
- **Battery cut-off:** on battery below the chosen percentage, sessions end and rules
  are ignored.
- **Surfaces:** Quick Toggle tile (“Awake”), Island compact activity with the time left
  (priority low) and a Power page, commands `power.toggle`, `power.awakeFor`,
  `power.awakeIndefinitely`, `power.awakeUntil`, `power.allowSleep`.
- **APIs:** `PowerService` (IOKit `IOPMAssertionCreateWithName`:
  `PreventUserIdleDisplaySleep` or `PreventUserIdleSystemSleep`), `DisplayService` for
  external displays, `NSWorkspace` launch/quit notifications for the app rule.
- **Permissions:** none.
- **Limits:** closed-lid awake on battery needs `pmset disablesleep` and an admin
  helper; not in v1. The "while a download is in progress" rule is for later.
