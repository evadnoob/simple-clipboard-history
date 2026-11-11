# Simple Clipboard History

A small, keyboard-first clipboard history app for macOS 13 or later. It lives in the menu bar, saves copies on disk, and pastes earlier clips into the app you are using.

## Picker

Press **Shift-Command-V**, then type to find a clip. There is no search box to focus.

![Clipboard picker](docs/screenshots/picker.png)

- **Up / Down:** select a clip.
- **Return:** paste it, or restore it to the clipboard when automatic paste is off.
- **Shift-Return:** use the alternate representation: plain text by default, or formatting when the default is plain text.
- **Command-Return:** open Paste Special text filters, when enabled.
- **Command-1 through Command-9:** recall a numbered clip.
- **Tab:** preview the selected clip. **Shift-Tab** focuses the footer’s icon-only gear button (tooltip: **Open control panel**); Space or Return opens the existing menu bar control panel on **Main**, with statistics and controls. Tab returns focus to the picker; typing or arrows also return to the picker and keep their normal behavior.
- **Escape:** dismiss the preview, clear a search, or close the picker. In Paste Special, return to the clips first.

The picker shows actual lines of copied content. Its height follows the results, bounded by your visible-item setting and display. Resize its edges or corners to change the width or height cap.

## Control panel

Click the clipboard icon in the menu bar. The icon stays icon-only; history count and storage usage appear inside the panel.

![Clipboard control panel](docs/screenshots/control-panel.png)

The main view shows history statistics, recent copy activity, and capture, paste, limit and picker controls. Its single footer row contains **Settings**, **Open Picker** (with the current shortcut), and **Quit**, separated by thin dividers. Click **Settings** for **Ignored apps** at the top, followed by the **Icon style** selector inside the same panel. The **Main** breadcrumb or Escape returns to the main view.

- **History:** keep clipboard history and launch at login. The picker shortcut stays visible on the main view.
- **Paste:** automatic paste or clipboard-only recall, formatting or plain text, and Paste Special.
- **Limits:** item count, total stored content size, and maximum size of one copy.
- **Look and feel:** width, actual content lines, density, maximum visible items, type icons, and timestamps.

**Icon style** selects Current (the default), Open outlines, Compact silhouettes, Framed symbols, or Editorial content marks for all picker type icons. Real image thumbnails remain unchanged, including when Show type icons is off. Families do not change the menu bar identity or panel action icons.

New families distinguish plain text, recorded rich-text/HTML representations, bounded first-line web links, images without thumbnails, and single or multiple stored files. Unknown types use a neutral fallback. The artwork vocabulary also includes folder, code, terminal, structured data, email, color, explicitly sensitive and mixed content symbols, but those remain renderer-only until reliable explicit metadata exists. No code, command or password heuristics are used, and the sensitive symbol does not imply protection.

Settings apply immediately and persist across launches. **Clear history…** is in a separate section below the icon styles in **Settings**, not on Main. It asks for confirmation with Cancel focused by default; choose **Clear history** explicitly to permanently delete all history. Import and Export are not shown.

Screenshots use synthetic clipboard content rendered by the app's test harnesses.

## Upgrade from Simple Clipboard

Quit the older Simple Clipboard app before launching Simple Clipboard History. On first launch, the old Application Support history directory is moved intact only if the new directory does not exist; if both exist, the new directory takes precedence and the old one is retained. A move failure is reported and prevents startup. Set `SIMPLE_CLIPBOARD_HISTORY_DATA` to override storage; legacy `SIMPLE_CLIPBOARD_DATA` remains a fallback, and the new variable takes precedence. The bundle identifier changed, so macOS may treat this as a different app: re-grant Accessibility permission and review Launch at Login in System Settings. Existing login-item approval may not follow the renamed app.

## Build and run

Install the Xcode Command Line Tools. A full Xcode installation is not required.

```bash
bash bundle.sh
open SimpleClipboardHistory.app
```

Automatic paste requires **System Settings > Privacy & Security > Accessibility** permission for Simple Clipboard History. Without it, recall still restores the clipboard; press Command-V yourself. Some apps may reject simulated paste or particular clipboard representations. macOS may require renewing Accessibility permission after development rebuilds.

`bash bundle.sh` builds and strictly verifies an ad-hoc signed development app. It does not access the keychain or prompt for a signing password. When you are ready to use an existing stable identity, manually sign the already-built bundle:

```bash
bash tools/sign-app.sh
```

The default identity is `evadnoob Local Code Signing`. To choose another existing identity, run `SIGNING_IDENTITY="Your Identity Name" bash tools/sign-app.sh`. This command signs only the existing bundle; it does not build or create identities. Missing identities or signing errors fail without an ad-hoc fallback. A stable manually signed build remains available, but Accessibility permission persistence is not guaranteed.

## Privacy and storage

Copies stay in `~/Library/Application Support/simple-clipboard-history/`, in SQLite and content-addressed blob files. Set `SIMPLE_CLIPBOARD_HISTORY_DATA` to use another directory. No cloud service is required.

Copies from excluded apps, copies marked concealed or transient, and oversized copies are skipped. These checks are not a guarantee that all sensitive content is excluded. The recorded source app is the app in front when the copy is detected. Copying identical content moves its existing entry to the top.

Old history is removed according to count, age, and total-content-size limits. Total content size is not the same as disk usage: the database, search index, and other storage overhead also occupy space. Previews inspect at most the first 64 KiB of text; full stored clipboard representations are unchanged.

## Development

```bash
bash tools/run-tests.sh
```

Tests use synthetic data. Offscreen rendering does not verify live focus, paste delivery, VoiceOver interaction, launch at login, or mouse resizing. Input methods that compose characters are not supported yet.

## License

MIT. See [LICENSE](LICENSE).
