# Agent instructions

## Design rules

- The app lives in the menu bar only (`LSUIElement`). Do not add a Dock icon, a main window, a toolbar or a sidebar.
- Do not use `NSToolbar` or SwiftUI toolbars anywhere. Toolbar layout loops are the reason this app exists.
- Settings are a hand-written KDL file. Do not add a preferences window.
- Popups follow noteapp's `/import` popup: box geometry, title bar, separators, content insets, typography,
  selectable rows and bottom action bar. Popups add no backdrop blur, dimming, tint or full-window fill.
- `KDL.swift` is a copy from noteapp. Keep it in step with noteapp until both apps share a package.

## Resource use

- Idle CPU must stay near 0%. Clipboard polling reads only `changeCount`.
- Clip data stays on disk in SQLite (and blob files for large data). Load only what the UI shows.

## Testing

- Add each test harness to the `harnesses` list in `Package.swift`. `tools/run-tests.sh` runs them all.
- Automated tests do not prove that live clipboard, menu or paste behavior works. State what still needs live
  validation.
