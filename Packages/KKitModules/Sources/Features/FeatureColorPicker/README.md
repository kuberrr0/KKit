# Colour Picker

Pick a colour anywhere on screen and copy it as text (DESIGN.md §3.6). It used to be part
of Screen Tools; it's its own feature so it has its own switch, settings and shortcut.

- **Pick** (`colorPicker.pick`, ⌃⌥P by default): `NSColorSampler`, the system loupe. Click
  to copy the colour in the chosen format, ⎋ cancels. It needs no permission (not even
  Screen Recording). The colour is converted to sRGB.
- **Formats** (`ColorFormatter`): HEX (optionally lowercase), RGB, HSL, CSS
  (`rgb(255 136 0 / 50%)`), SwiftUI `Color(red:green:blue:)` and `NSColor(srgbRed:…)`.
  Alpha is added only when the colour isn't opaque.
- **Island**: after a pick, the swatch and HEX show in the compact Island for 3 s
  (setting). The **Colours** page in the expanded Island shows the last colour in every
  format (click one to copy it), a Pick button and the recent colours; it can be turned
  off. `colorPicker.showColors` opens it.
- **Floating Bar** (`ColorProvider`): a colour typed in root search (`#F80`, `#FF8800`,
  `#FF880080`, `0xFF8800`, `rgb()`/`rgba()`, `hsl()`/`hsla()`, SwiftUI/NSColor code) is
  listed in every format with a swatch icon, the chosen format first; ↵ copies. `#` on
  its own lists Pick Colour and the recent colours; `#ff8800` reads hex. `ColorParser`
  reads back everything `ColorFormatter` writes.
- **History**: the last 24 colours, newest first, stored as hex in the feature's
  settings. `colorPicker.clearHistory` empties it.
- Not yet: picking in Display P3, a magnified zoom of our own, contrast checking,
  named CSS colours.
