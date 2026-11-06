# Agent instructions

## Design rules

- The app lives in the menu bar only (`LSUIElement`). Do not add a Dock icon, a main window, a toolbar or a sidebar.
- Do not use `NSToolbar` or SwiftUI toolbars anywhere. Toolbar layout loops are the reason this app exists.
- Settings live in the menu bar menu as submenus and are stored in user defaults. Do not add a settings file or a
  preferences window.
- The menu shows statistics and settings, not clips. Clips are recalled from the picker.
- The picker is a nonactivating `NSPanel`, so the user's app stays active and receives the paste. Do not activate
  the app when the picker opens.
- The picker draws its own rows and prompt (like noteapp's `/import` popup) and maps keys in `PickerView.pickerKey`.
  Keep key behavior in `PickerModel`, which the tests drive without a window.
- Popups follow noteapp's `/import` popup: box geometry, title bar, separators, content insets, typography,
  selectable rows and bottom action bar. Popups add no backdrop blur, dimming, tint or full-window fill.

## Resource use

- Idle CPU must stay near 0%. Clipboard polling reads only `changeCount`.
- Clip data stays on disk in SQLite (and blob files for large data). Load only what the UI shows.

## Testing

- Add each test harness to the `harnesses` list in `Package.swift`. `tools/run-tests.sh` runs them all.
- Automated tests do not prove that live clipboard, menu or paste behavior works. State what still needs live
  validation.
