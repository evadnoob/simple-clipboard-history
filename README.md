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

The title shows the clip count and the age of the last copy, for example `142  3m`. The menu shows:

- Clipboard: the current clip's kind, size and source app, or why it was not recorded.
- History: clip count, bytes copied, bytes on disk, the oldest clip and the last copy.
- Recent clips: the 10 most recently copied clips. Cmd-1 to Cmd-9 recall the first nine while the menu is open.
- Notices: a missing Accessibility permission and settings file problems.
- Pause Capture, Open Settings File, Quit.

The source app of a clip is the frontmost app when the copy was seen. A copy made from a background process (for
example `pbcopy` in a terminal) is attributed to whatever app was frontmost.

## What is recorded

The app checks the pasteboard change counter 4 times per second and reads the contents only after a change.
Every pasteboard item and type is stored, so rich text, images and files paste back unchanged. A copy is skipped
when:

- it carries an nspasteboard.org marker such as `org.nspasteboard.ConcealedType` (password managers set these),
- it was made in an app listed under `capture ignore-app`,
- it is larger than `history maximum-clip-megabytes`,
- capture is paused.

Copying the same content again moves the existing clip to the top instead of storing it twice.

## Storage

`~/Library/Application Support/simple-clipboard/` (override with `SIMPLE_CLIPBOARD_DATA`):

- `clips.sqlite`: clips, small representations and a trigram full-text index of clip text. WAL mode, and
  memory-mapped reads, so pages live in the OS file cache instead of the app's heap.
- `blobs/`: representations larger than 128 KB, one file per distinct content (named by SHA-256).

The least recently copied clips beyond `history limit` are deleted, with their unused blob files.

Measured on macOS 27.2 with 3 clips: 0.09% CPU over 120 seconds idle, 15 MB memory footprint (`footprint`).

## Settings

`~/.config/simple-clipboard/simple-clipboard.kdl` (override with `SIMPLE_CLIPBOARD_SETTINGS`). Open Settings File
creates it from a commented template. Changes apply within 2 seconds of saving. Invalid values keep their
defaults and show as notices in the menu.

```kdl
recall {
    # "clipboard": choosing a clip puts it on the clipboard; you press Cmd-V.
    # "paste": also sends Cmd-V to the frontmost app. Needs Accessibility permission.
    mode "clipboard"
}
history {
    limit 1000
    maximum-clip-megabytes 20
}
capture {
    ignore-app "com.1password.1password"
}
```

With `mode "paste"` and no Accessibility permission, the clip still goes on the clipboard and the menu shows a
notice that opens the Accessibility settings.

## Milestones

1. Risk check: clipboard polling, SQLite storage, both recall modes, and idle CPU and memory measurements.
2. Capture and storage: history, duplicate removal, retention, concealed clips skipped, ignore list.
3. Picker: a hotkey popup styled like noteapp's `/import` popup, with search at the bottom.
4. Settings: hotkey, retention, ignore list, menu bar title, pinned clips.
5. Later: paste rules per app, paste filters, sequential paste.
