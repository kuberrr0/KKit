# KKit icons

**Concept: Modular K.** The stem and the two arms of the K are separate pieces, like
KKit's plug-in features. Dark graphite body, white stem, blue and coral arms.

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
