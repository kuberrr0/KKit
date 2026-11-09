# Screen Tools

Screenshots, text and QR scanning, translation and screen recording (DESIGN.md §3.6).
The colour picker is its own feature, `FeatureColorPicker`.

- **Picking**: every capture starts with `OverlayService.pickRegion` (drag an area; Space
  switches to clicking a window; Return or a click picks a screen in screen mode; ⎋ cancels).
  `ScreenCaptureService` (ScreenCaptureKit) captures without KKit's own panels.
- **Screenshots** (`screenTools.captureArea/Window/Screen/Timed`): copied and/or saved as the
  settings say (PNG, JPEG or HEIC; name pattern with date formats in braces;
  `CaptureFileNamer`), then a thumbnail lands in the Island with Copy, Save/Show, Mark Up
  (opens Preview), Pin, Text and Shelf. Drag the thumbnail out to use the file. Unsaved
  shots keep a temporary file so dragging, shelving and editing work. Pinned shots are
  movable floating panels (double-click or ✕ closes; right-click for opacity).
- **Text** (`screenTools.captureText`): Vision OCR on the area; the text is copied and
  shown in the Island with Copy, Translate, Note and Shelf.
- **Codes** (`screenTools.scanCode`, `scanScreenCodes`): Vision barcode detection; payloads
  are copied, links get an Open button (or open straight away if the setting is on).
- **Translate** (`screenTools.translateArea`, `translateClipboard`, `tr hola` in the
  Floating Bar): a floating card that uses Apple's on-device Translation framework
  (macOS 15+; languages download on first use).
- **Recording** (`screenTools.recordArea/Window/Screen`, `stopRecording`, Record tile):
  macOS 15+ (`SCRecordingOutput`), MP4 into the save folder, optional system audio,
  microphone (asks for Microphone) and click highlights. A red dot and the elapsed time
  sit in the Island with a Stop button.
- **Permissions**: Screen Recording is requested the first time a capture runs; Settings
  shows a link to System Settings while it's off.
- Not yet: annotation editor, GIF export, keystroke overlay, taking over ⇧⌘3/4/5 by
  default (bind them yourself in Settings › Shortcuts after turning off the system ones).
