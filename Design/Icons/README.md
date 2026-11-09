# KKit icons

**Concept: Island K.** The notch Island (a black pill with a green live dot and a
waveform) sits above a "Modular K" whose stem and two arms are separate pieces, like
KKit's plug-in features. Flat solid colours only, no gradients or shadows: graphite body,
white stem, blue upper arm, coral lower arm. The menu bar icon is the same idea in one
colour: a pill above the three-piece K.

| File | What |
|---|---|
| `AppIcon.svg` | App icon master (1024 × 1024, Apple's 824 pt body grid) |
| `MenuBarIcon.svg` | Menu bar icon master (18 × 18 pt, black, used as a template image) |
| `build-icons.js` | Generates both masters and the asset catalog entries below |

Generated into `App/Assets.xcassets`:

- `AppIcon.appiconset`: every macOS size (16–512 pt at 1× and 2×). `project.yml` sets
  `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`.
- `MenuBarIcon.imageset`: a vector PDF marked as a template, so macOS tints it for light
  and dark menu bars. `MenuBarHost` loads it with `NSImage(named: "MenuBarIcon")`.

To change the artwork, edit the geometry or colours at the top of `build-icons.js`, then
from the repo root:

```sh
npm install --no-save playwright && npx playwright install chromium   # once
node Design/Icons/build-icons.js
```
