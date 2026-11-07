# Agent instructions

## Design rules

- The app lives in the menu bar only (`LSUIElement`). Do not add a Dock icon, a main window, a toolbar or a sidebar.
- Do not use `NSToolbar` or SwiftUI toolbars anywhere. Toolbar layout loops are the reason this app exists.
- Settings live in the control panel that opens from the menu bar icon, and are stored in user defaults. Use
  checkboxes and native dropdown controls (`PanelControls.swift`). Do not add a settings file or a separate
  preferences window.
- The menu bar stays icon-only. The control panel shows statistics and settings, not clips. Keep Import and
  Export visible, disabled and labeled "Not implemented" until those actions exist.
- The picker has no title row and no input field. Typing narrows the list; show the query and optional match
  count only while the query is nonempty. Keep keyboard hints compact and accurate.
- The picker is a nonactivating `NSPanel`, so the user's app stays active and receives the paste. Do not activate
  the app when the picker opens.
- The picker draws its own rows and prompt (like noteapp's `/import` popup) and maps keys in `PickerView.pickerKey`.
  Keep key behavior in `PickerModel`, which the tests drive without a window.
- Popups use flat box geometry, thin separators, system typography and restrained system-blue selection.
  Keep square or nearly square edges. Do not add decorative cards, toolbars, backdrop blur or dimming.
- Picker appearance controls independently set width, actual consecutive content lines, padding and maximum
  visible items. Keep resize corners. Height follows content, bounded by the display and a saved manual height
  cap; a width-only resize must not overwrite that cap.
- Preserve system dark appearance support without adding a separate visual redesign. Controls and picker rows
  need keyboard operation and accessibility labels, roles and actions.

## Resource use

- Idle CPU must stay near 0%. Clipboard polling reads only `changeCount`.
- Clip data stays on disk in SQLite (and blob files for large data). Load only what the UI shows.

## Testing

- Add each test harness to the `harnesses` list in `Package.swift`. `tools/run-tests.sh` runs them all.
- Automated tests do not prove that live clipboard, panel, picker or paste behavior works. State what still needs live
  validation.
