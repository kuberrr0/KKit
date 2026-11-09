# Quick Note

Capture a thought into an Obsidian vault (or any folder of markdown files) from the
Floating Bar (DESIGN.md §3.11).

- **Targets** (`NoteTargetKind`): append to a file (`Inbox.md`, optionally under a heading),
  today's daily note (`Daily/{yyyy}/{yyyy-MM-dd}.md`, created from a template), or a new
  note in a folder (first line → title and file name).
- **Editor**: a Floating Bar mode (`n ` or the `quickNote.new` command). ⌘↵ saves and
  closes, ⌘⇧↵ saves and opens the note in Obsidian, Tab/⇧Tab switch target, ⎋ goes back.
  Light markdown colouring and `[[` completion from the vault's note names. The draft is
  kept until it's saved.
- **Commands**: `quickNote.new`, `quickNote.append` (text argument: `add to note call mum`),
  `quickNote.openDaily`.
- **⌘K action**: *Send to Note* on text, URL and file results.
- **Service**: publishes `QuickNoteServicing` while running, for "Send to note" from
  Clipboard, OCR and Shelf later.
- **Files**: `NoteWriter` (actor) writes atomically; `MarkdownAppender` keeps line endings,
  frontmatter and the other sections; paths can't leave the vault. Notes open with
  `obsidian://open?vault=…&file=…` (`ObsidianLink`).
- **Settings**: vault (path + bookmark), default target, inbox file and heading, daily
  pattern/heading/template, new-note folder/template, entry template (`{{time}}`,
  `{{date}}`, `{{text}}`, `{{app}}`), time format, note the frontmost app, open after save.
- Not yet: the frontmost browser's URL and selected text as context (need Automation and
  Accessibility; later milestone).
