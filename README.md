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

## Menu bar

The title shows the clip count and the age of the last copy, for example `142  3m`. The menu does not list
clips. It shows:

- Open Picker, with the picker hotkey.
- Clipboard: the current clip's kind, size and source app, or why it was not recorded.
- History: clip count, bytes copied, bytes on disk, the oldest clip and the last copy.
- Notices: recall is set to paste and Accessibility permission is missing, or the picker hotkey could not be
  registered.
- Settings: Picker Hotkey, Recall, Keep History, Largest Clip, Ignored Apps, Pause Capture.
- Clear History and Quit.

The source app of a clip is the frontmost app when the copy was seen. A copy made from a background process (for
example `pbcopy` in a terminal) is attributed to whatever app was frontmost.

## Picker

The hotkey (default Shift-Command-V) opens the picker over the current app. It is a borderless box in the style of
noteapp's `/import` popup: a title row with the clip count, the clips newest first, and a search prompt at the
bottom. Simple Clipboard does not become the active app, so the app you were in stays active and receives the
paste.

- Typing searches the text of every clip (substring, any case).
- Up and Down (or Control-N and Control-P), Page Up, Page Down, Home and End move the selection. The scroll wheel
  scrolls.
- Return, or a double-click, recalls the selected clip. Command-1 to Command-9 recall the numbered rows.
- Tab opens a preview of the selected clip (text, image or file paths). Escape closes the preview.
- Backspace deletes a character, Option-Backspace a word, Command-Backspace or Control-U the whole query.
- Escape, Command-W, Control-G, the hotkey again or a click outside closes the picker.

Recall puts the clip on the clipboard with every stored type. With Recall set to "Paste into Frontmost App", it
also sends Command-V.

The search prompt reads key events directly. Input methods that compose characters (for example Japanese) do not
work in it yet.

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

All settings are in the menu. The app saves them in its preferences (`com.evadnoob.simple-clipboard`).

- Picker Hotkey: Shift-Command-V (default), Option-Command-V, Control-Command-V, Shift-Option-Command-V or None.
  If another app already uses the combination, the menu shows a notice; choose another one.
- Recall: "Put on Clipboard" (you press Cmd-V) or "Paste into Frontmost App" (also sends Cmd-V; needs
  Accessibility permission). Choosing paste without the permission opens the Accessibility settings. Until it is
  granted, recalled clips go on the clipboard only.
- Keep History: 100, 500, 1,000 (default), 5,000 or 10,000 clips. Choosing fewer clips than are stored asks before
  deleting the least recently copied ones.
- Largest Clip: 5, 20 (default), 50 or 100 MB. Larger copies are not recorded.
- Ignored Apps: "Ignore <app>" adds the app that was in front when the menu opened. Choosing a listed app records
  its copies again.
- Pause Capture: stops recording until chosen again. The title shows `paused`.

## Milestones

1. Risk check: clipboard polling, SQLite storage, both recall modes, and idle CPU and memory measurements.
2. Capture and storage: history, duplicate removal, retention, concealed clips skipped, ignore list.
3. Picker: a hotkey popup styled like noteapp's `/import` popup, with search at the bottom.
4. More settings in the menu: hotkey, pinned clips.
5. Later: paste rules per app, paste filters, sequential paste.
