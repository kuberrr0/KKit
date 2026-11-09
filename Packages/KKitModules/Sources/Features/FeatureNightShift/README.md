# Night Shift

Warms the screen with gamma tables, from a gentle tint to well past what macOS Night
Shift allows. DESIGN.md §3.10.

- **Does:** intensity 0–200% (100% ≈ macOS's warmest, 200% ≈ 1200 K), modes Warm,
  Amber and Darkroom (red only), extra dim, a fade when it turns on or off, pause for an
  hour, and a schedule: off, sunset to sunrise (NOAA solar calculation from a
  remembered location), or custom times.
- **Exceptions:** displays and frontmost apps where the tint is lifted (photo editors).
- **Surfaces:** Quick Toggle tile (“Night”), menu bar section with a slider (order 200),
  commands `nightShift.toggle` (⌃⌥N), `nightShift.setIntensity` (`night 150`),
  `nightShift.stronger`, `nightShift.weaker`, `nightShift.darkroom`, `nightShift.pause`.
- **APIs:** `DisplayService` (`CGSetDisplayTransferByTable`, multiplied onto the
  display's own table and re-applied after wake and display changes),
  `LocationService` once, to remember a coordinate for the sunset schedule.
- **Permissions:** Location (optional; you can also type a coordinate).
- **Limits:** gamma tables don't affect screenshots or screen recordings, and some
  apps that set their own gamma (games) can override the tint while they're frontmost.
  It doesn't change macOS's own Night Shift; turn one off if you use the other.
