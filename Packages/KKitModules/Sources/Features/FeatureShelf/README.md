# Shelf

A holding area for files, images, links and text (DESIGN.md §3.8).

- **Adding**: drag something toward the notch and the Island opens into drop zones:
  *Shelf* (this feature), *AirDrop* (sends straight away) and *Add to Note* (Quick Note).
  Also *Add to Shelf* on Floating Bar results (files, apps, links, text, clipboard
  history), from screenshots, `shelf.addClipboard`, and `ShelfServicing` for other
  features.
- **Files**: by default the Shelf points to your files and never moves or deletes them;
  with "Keep a copy" on, dropped files are copied into `shelf/Files/`. Images dropped from
  apps (no file) are always saved there. The Shelf's own copies are deleted when their
  items are removed. Items whose files disappear are dropped at launch.
- **Island page**: tiles you drag out (double-click opens). Right-click: Open, Open With,
  Show in Finder, Copy, Copy Path, AirDrop, Share, Send to Note (text and links), Rename,
  Compress (zip with `ditto`), Convert Image (PNG/JPEG/HEIC, half size), Merge PDFs, Remove.
  New files from actions are written next to the original (or into the Shelf's folder
  for its own copies) and added to the Shelf.
- **Settings**: keep copies, clear after N hours (one timer until the oldest item expires,
  no polling), at most N items, open the Shelf after dropping.
- Stored in `shelf/items.json`.
- Not yet: dragging several items out at once, "remove after drag-out", the mini shelf at
  a screen edge, and WebP output (ImageIO can't write it).
