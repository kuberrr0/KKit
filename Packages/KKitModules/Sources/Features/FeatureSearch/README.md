# Search

The Floating Bar's everyday sources (DESIGN.md §2.3, §3.2). The Floating Bar host
itself lives in `KKitHosts/FloatingBar/`; this feature only contributes providers.

| Provider | Prefix | In root search | Source |
|---|---|---|---|
| Applications | `a ` (alone: every app, A to Z) | yes | `AppIndex`: /Applications (one folder deep), /System/Applications, ~/Applications, CoreServices apps, Finder; rescanned in the background when older than 10 min |
| Files & Folders | `f ` | 3+ letters, a few strong matches (setting) | `context.fileSearch` (Spotlight `NSMetadataQuery`, home folder) |
| System Settings | `/` | strong matches | `SystemSettingsPane.all`, opened with `x-apple.systempreferences:` |
| Web | `w ` | URLs, keyword searches, bookmarks, fallback | `WebQuery`, `SearchEngine`, `BookmarkIndex` (Chromium-family JSON, Safari plist with Full Disk Access) |

- Commands: `search.applications`, `search.files`, `search.web`, `search.systemSettings` open the bar with the prefix.
- ⌘K action: *Search the Web for This* on any non-URL result.
- Settings: files in root search, default engine, browser for web results, fallback row,
  bookmarks.
- Not yet: open browser tabs (need Automation permission per browser).
