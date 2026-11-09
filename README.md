# KKit

An all-in-one macOS utility app: a notch **Island**, a **Floating Bar** command palette,
volume control, system stats, keep-awake, screen tools (screenshot, OCR, colour picker,
recording), clipboard history, a file shelf, keyboard superpowers (Hyper key), a much
stronger Night Shift, and quick notes straight into your Obsidian vault.

Status: **M0 (skeleton)**: the plug-in core, services, menu bar item and Settings window
are in; features arrive from M1. Docs:

- [Design](docs/DESIGN.md): UI/UX for every feature, plus suggested features
- [Architecture](docs/ARCHITECTURE.md): how it's built and how features plug in
- [Roadmap](docs/ROADMAP.md): build order

## Building

Requirements: macOS 14.2+, Xcode 16 or newer, [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```sh
xcodegen generate        # creates KKit.xcodeproj from project.yml (re-run after pulling)
open KKit.xcodeproj      # then Run the KKit scheme
```

Module tests run without Xcode's UI: `swift test --package-path Packages/KKitModules`.

**Signing.** By default the app is signed "to run locally" (ad-hoc). macOS forgets
privacy permissions (Accessibility, Input Monitoring…) for ad-hoc builds every time you
rebuild, so sign with your free Apple Development certificate instead:

1. `cp Config/Local.xcconfig.example Config/Local.xcconfig`
2. Put your team ID in it. In Xcode › Settings › Accounts, select your Apple ID and
   your "Personal Team"; or run
   `security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject`
   and copy the `OU=` value.
3. `xcodegen generate` again.

`Config/Local.xcconfig` is git-ignored, so your team ID stays on your Mac.
