# Brightness

Display brightness with the Island HUD. Part of DESIGN.md §3.5 (the Island replaces
the system HUDs).

- **Does:** takes over the brightness keys (on by default): KKit's step size (1/16
  like macOS; ⇧⌥ for quarter steps) and the Island HUD instead of macOS's. A slider in
  the KKit menu, and commands to step or set the brightness. It acts on the display
  under the pointer when KKit can control it, else the built-in one.
- **Surfaces:** commands `brightness.up`, `brightness.down`, `brightness.set` (`bright
  40`); a menu bar section (order 110, only when a display can be controlled); the
  Island HUD; Settings › Brightness.
- **APIs:** `DisplayService.brightness(of:)` / `setBrightness(_:for:)` (the private
  DisplayServices framework, loaded with `dlopen`, falling back to CoreDisplay; only
  built-in displays for now), `InputTapService` (`context.input`, priority `.normal`:
  key down/up for keys 144/145 and media keys 2/3), `IslandService`.
- **Permissions:** Accessibility, optional: only for the key takeover. The slider and
  commands work without it.
- **Limits:** external displays need DDC, which isn't supported yet; their keys stay
  with macOS. Auto-brightness keeps working and may change the level afterwards.
