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

## Milestones

1. Risk check: clipboard polling, SQLite storage, both recall modes, and idle CPU and memory measurements.
2. Capture and storage: history, duplicate removal, retention, concealed clips skipped, ignore list.
3. Picker: a hotkey popup styled like noteapp's `/import` popup, with search at the bottom.
4. Settings: hotkey, retention, ignore list, menu bar title, pinned clips.
5. Later: paste rules per app, paste filters, sequential paste.
