# Simple Clipboard

A minimal clipboard history for macOS. It lives in the menu bar, records every copy, and lets you recall
earlier copies. It has no Dock icon and no permanent window.

Status: early development. See the milestones below.

## Build and run

Needs the Swift toolchain from the Xcode Command Line Tools. Xcode is not needed.

```bash
bash tools/run-tests.sh   # build and run every test harness
bash bundle.sh            # build SimpleClipboard.app
open SimpleClipboard.app
```

## Code signing

`bundle.sh` signs the app with the code signing identity "evadnoob Local Code Signing" (override with
`SIGNING_IDENTITY`). A fixed identity keeps the app's designated requirement the same across rebuilds, so macOS
keeps its Accessibility permission. An ad-hoc signature changes with every build, and macOS then asks again.

Create the identity once per machine; it is a self-signed certificate in the login keychain:

```bash
bash tools/create-signing-identity.sh
```

`security find-identity -p codesigning` lists it as `CSSMERR_TP_NOT_TRUSTED`. That is expected; `codesign` does not
need a trusted certificate. Without the identity, `bundle.sh` prints a warning and signs ad-hoc.

## Menu bar

The menu bar item is a clipboard icon (the `list.clipboard` symbol), dimmed while capture is paused. Clicking it
opens the settings panel under it. Clicking it again, Escape or a click elsewhere closes the panel.

The panel has no menus or dropdowns. From the top:

- Clipboard: the current clip's kind, size and source app, or why it was not recorded.
- History: clip count, bytes copied, bytes on disk, the oldest clip and the last copy.
- Checkboxes: Paste into the frontmost app, Always paste plain text, Pause capture.
- Choice rows: Hotkey, Keep (clips), Largest clip (MB).
- Ignored apps: a checkbox per ignored app (uncheck to record it again) and "+ Ignore <app>" for the app that was
  in front when the panel opened.
- Notices, when needed: missing Accessibility permission, or a hotkey that another app already uses. Clicking a
  notice opens its fix.
- Open Picker, Clear History and Quit.

Every change applies at once. Clear History, and a Keep value smaller than the clip count, ask inside the panel
before deleting. Tab moves between controls, Space toggles a checkbox and the arrow keys change a choice row.

The source app of a clip is the frontmost app when the copy was seen. A copy made from a background process (for
example `pbcopy` in a terminal) is attributed to whatever app was frontmost.

## Picker

The hotkey (default Shift-Command-V) opens the picker over the current app. It is a borderless box in the style of
noteapp's `/import` popup: the clips newest first, and a bar at the bottom with the count and the key hints. There
is no title row and no input field. Simple Clipboard does not become the active app, so the app you were in stays
active and receives the paste.

- Typing narrows the list to clips whose text contains what you typed (any case). The match is shown in bold in
  each row, and the bar shows the count and the typed text.
- Up and Down (or Control-N and Control-P), Page Up, Page Down, Home and End move the selection. The scroll wheel
  scrolls.
- Return, or a double-click, pastes the selected clip. Command-1 to Command-9 paste the numbered rows.
- Shift-Return pastes plain text (or, with "Always paste plain text" on, keeps the formatting).
- Command-Return opens the filters for the selected clip. See Filters below.
- Tab opens a preview of the selected clip (text, image or file paths). Escape closes the preview.
- Backspace deletes a typed character, Option-Backspace a word, Command-Backspace or Control-U all of it.
- Escape, Command-W, Control-G, the hotkey again or a click outside closes the picker.
- The edges and corners resize the picker, with the same corner squares and diagonal cursors as noteapp. The size
  is remembered.

Pasting puts the clip on the clipboard with every stored type, then sends Command-V (needs Accessibility
permission). With "Paste into the frontmost app" off, the clip only goes on the clipboard.

Typing reads key events directly. Input methods that compose characters (for example Japanese) do not work yet.

## Filters

Filters change a clip's text before pasting, like Pastebot's. Command-Return in the picker lists them under three
headings; typing narrows the list and Return pastes the result as plain text. Escape goes back to the clips.

- Text & Writing: Convert to Plain Text, Single Line, Trim Whitespace, Normalize Whitespace, Convert to
  Uppercase, Lowercase and Titlecase, Convert to Straight Punctuation, Sort Lines, Remove Duplicate Lines, Remove
  List Numbering.
- Developer: URL Encode and Decode, Base64 Encode and Decode, Hex Encode and Decode, HTML Entity Encode and
  Decode, Escape for JSON String, Format JSON, Slugify, To snake_case, To camelCase.
- Web & Markdown: Strip HTML, Markdown Link from URL, Markdown Blockquote, Extract URLs, Extract Email Addresses,
  Create List, Wrap in Paragraph Tags.

A filter that does not apply (for example Base64 Decode on text that is not Base64) beeps and leaves the picker
open. Filter results are not saved as new clips; the original clip moves to the top.

## What is recorded

The app checks the pasteboard change counter 4 times per second and reads the contents only after a change.
Every pasteboard item and type is stored, so rich text, images and files paste back unchanged. A copy is skipped
when:

- it carries an nspasteboard.org marker such as `org.nspasteboard.ConcealedType` (password managers set these),
- it was made in an app in Ignored Apps,
- it is larger than the Largest Clip setting,
- capture is paused.

Copying the same content again moves the existing clip to the top instead of storing it twice.

## Storage

`~/Library/Application Support/simple-clipboard/` (override with `SIMPLE_CLIPBOARD_DATA`):

- `clips.sqlite`: clips, small representations and a trigram full-text index of clip text. WAL mode, and
  memory-mapped reads, so pages live in the OS file cache instead of the app's heap.
- `blobs/`: representations larger than 128 KB, one file per distinct content (named by SHA-256).

The least recently copied clips beyond the Keep History setting are deleted, with their unused blob files.

Measured on macOS 27.2 with 3 clips: 0.09% CPU over 120 seconds idle, 15 MB memory footprint (`footprint`).

## Settings

All settings are in the settings panel. The app saves them in its preferences (`com.evadnoob.simple-clipboard`).

- Paste into the frontmost app (default on): sends Command-V after putting the clip on the clipboard. Needs
  Accessibility permission. Turning it on without the permission shows the system prompt and opens the
  Accessibility settings; until it is granted, clips go on the clipboard only.
- Always paste plain text (default off).
- Pause capture: stops recording until unchecked. The menu bar icon is dimmed.
- Hotkey: Shift-Command-V (default), Option-Command-V, Control-Command-V, Shift-Option-Command-V or None.
- Keep: 100, 500, 1,000 (default), 5,000 or 10,000 clips.
- Largest clip: 5, 20 (default), 50 or 100 MB. Larger copies are not recorded.
- Ignored apps.

## Milestones

1. Risk check: clipboard polling, SQLite storage, both recall modes, and idle CPU and memory measurements.
2. Capture and storage: history, duplicate removal, retention, concealed clips skipped, ignore list.
3. Picker: a hotkey popup styled like noteapp's `/import` popup, with search at the bottom.
4. Settings panel, plain text and filter pastes, picker resizing. Next: pinned clips, deleting a clip from the
   picker.
5. Later: paste rules per app, paste filters, sequential paste.
