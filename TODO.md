# Backlog

This file is the backlog for Simple Clipboard. Keep queued work here across sessions. Do not implement the entire backlog without agreement on scope.

After changes pass their relevant checks, package with the existing signing identity and restart the app automatically. User requested not to wait for a separate restart instruction. Do not change keychain permissions or identities without approval.

## Queued changes

- [ ] Add an **About** page describing what Simple Clipboard is, that David Boon made it with help from AI, and its design aesthetic. Agree on the wording and level of detail before implementation. Keep it accessible from the menu bar settings panel and consistent with the menu-bar-only design; do not add a main window or preferences window.
- [x] Renamed **Picker UI** to **Look and feel**. Packaged, signed, and relaunched together with the chart-height reduction from 64 to 43 points. Panel tests pass (207 checks); live appearance still needs user verification.
- [ ] Add password masking. Store password clips as requested, but conceal their contents in the picker, previews, and other app displays. Investigate clipboard metadata from password managers as a detection signal; do not assume arbitrary password text can be identified reliably. Decide how users can mark unrecognized clips as sensitive, whether revealing is allowed, and how search and accessibility output avoid exposing masked contents. Masking is a display feature, not encryption or secure storage. User asked: "If a password is on the clipboard, we do want to store it but we don't want to see it".
- [x] Implemented in source: **Maximum items** is a freeform positive integer input, persisted without a preset cap. Automated validation covers invalid and overflowing input, native field-editor focus, Tab/Return/blur commits and confirmation lockout; live control behavior still needs checking. This is separate from **Maximum visible items**.
- [x] Implemented in source: green **Active** indicator uses a small square symbol.
- [ ] Menu bar uses the empty clipboard outline (`clipboard`) in `StatusItemController.swift`. Packaged, signed, and launched; actual menu bar appearance still needs user verification.
- [x] Removed **Retention days** from the panel and disabled age-based deletion, including when legacy retention values are present. Count and byte limits remain active; tests updated. Live data-retention behavior still needs checking.
- [x] Implemented in source: header chart shows observed captured-copy activity as hourly blue bars, with native 3/5/10-day range choice and persisted 5-day default. Counts are transactionally aggregated in SQLite by absolute Unix-hour bucket, include successful repeated deduplicated copies, and survive clip deletion/eviction. Rolling range includes the current hour and preceding intervals; displayed labels use relative range endpoints. No historical backfill or paste tracking. Automated storage/settings/panel checks pass. Packaged, signed, and launched; activity capture and visual rendering still need live validation.

## Questions and follow-up

- [ ] Investigate why items have numbers beside them. Explain what the numbers mean and whether they are needed before changing them. User asked: "why do the items have numbers by them?"
- [ ] Resolve repeated signing-password prompts. User asked: "do I need to provide this password every time we build? Or can we automate that with 1password and the fingerprint reader?" Investigate supported macOS keychain access, 1Password, and Touch ID options. Prefer the narrowest safe permission. Do not store passwords in scripts, pass secrets on command lines, change keychain permissions, or create identities without approval. The suggested **Always Allow** solution has not been verified across repeat builds. The 1Password/Touch ID question remains unanswered.
- [x] Implemented in source: **When pasting**, with choices **Preserve original formatting** and **Paste as plain text**. Display labels only; stored clips and paste semantics are unchanged.
- [ ] Verify appearance settings in the running app: width, content lines, density, maximum visible items, icons, and timestamps. They are intended to work when the picker reopens. A saved manual height cap can limit visible items. No live failure has been confirmed.
- [ ] Improve design instructions: general styling preferences are defaults, not blanket bans on approved design elements. Preserve approved decoration/charts. Ask about conflicts between reference images and written guidance instead of silently omitting elements. Do not invent data semantics for decoration. The proposed instruction has not been installed in an instructions file.

## Resume context

- Worktree: `/Users/davidboon/Projects/simple-clipboard/.worktrees/evadnoob-feat-design-update`.
- Implementation branch: `evadnoob/feat/design-update`. The packaged design before the settings and chart batch was based on `bd0c719`. Use Git history for the final commit and merge state.
- Visual correction passed 879 checks, release build, and independent review. README contains synthetic screenshots.
- Signing retry subsequently succeeded with `evadnoob Local Code Signing`; strict signature verification passed and the corrected app was launched. User said the latest design looks great. Earlier packaging failure is no longer the launch blocker.
- Final independent validation: `bash tools/run-tests.sh /tmp/simple-clipboard-final-validation` passed all five harnesses with 954 checks and zero failures. `swift build -c release --product SimpleClipboard` passed. Independent code review accepted the settings changes and chart geometry. `git diff --check` passed.
- The broader `swift build -c release` failed while compiling test harnesses with `unable to resolve Swift module dependency to a compatible module: 'SimpleClipboardKit'`. This failure remains uninvestigated; the production app product and the dedicated test script pass.
- Packaged with `bash bundle.sh`, signed with the existing `evadnoob Local Code Signing` identity, and passed `codesign --verify --strict`. Parent launched the updated bundle and verified its running executable path. No keychain permissions or identities were changed. Latest pre-package checks: 960 checks, zero failures; production release build passed with Command Line Tools search-path warnings.
- The running app includes the settings changes, copy-activity chart, and removal of per-setting-row dividers. User approved the appearance after launch. Detailed numeric editing, retention behavior, paste permission persistence and panel interaction still need live checks.
- Design source: `~/Downloads/Simple_Clipboard_History_Design_Package.zip`; extracted handoff and reference images: `/tmp/sc-design/simple-clipboard-design/`. Re-extract if temporary files disappear. Preserve approved type-to-search, icon-only menu bar, native controls, resize corners, and content-driven picker height.
- User requested merging the design branch into `main` and pushing after approving the packaged app. No design pull request was opened before this request. Signing pull requests were previously open: Simple Clipboard #4 and noteapp #71; recheck before changing them.
