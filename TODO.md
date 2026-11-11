# Backlog

This file is the backlog for Simple Clipboard History. Keep queued work here across sessions. Do not implement the entire backlog without agreement on scope.

After changes pass their relevant checks, package with an ad-hoc signature and restart the app automatically. Do not use or repair signing identities or keychain permissions unless explicitly requested. A user may manually sign a completed development bundle with `bash tools/sign-app.sh` when ready.

Work quickly on approved design alignment. Make reasonable, reversible layout and label choices without repeatedly asking for scope approval or deferring straightforward changes. Batch related edits, use proportionate validation, and reserve user questions for consequential behavior, data loss, security permissions, or genuinely ambiguous intent. Do not use this instruction to invent working Import/Export behavior or bypass safety checks.

## Design alignment

Reference: `~/Desktop/clipboard design.png`. User approved the difference list. Preserve intentional changes: icon-only menu bar, picker without top input/title row, approved paste labels, Look and feel, numeric Maximum items, no age-based retention, no per-setting-row dividers, saved picker resizing and wider default. Do not restore screenshot settings that conflict with these decisions.

- [x] Implemented in source: settings header has clipboard icon and bold **Simple Clipboard History** title; compact chart upper-right uses a fixed five-day range with no range selector. This affects graph display only, not clipboard retention. Counts remain real transactional observed-copy activity.
- [x] Implemented in source: plain square Active indicator and emphasized Active, item count, and used/maximum size with percentage groups and dividers.
- [x] Removed the extra clipboard-content status line from the main header.
- [x] Renamed **Enable clipboard history** to **Keep clipboard history** without changing pause/resume capture semantics.
- [x] Implemented in source: picker rows use semibold primary text, muted secondary lines, larger type-specific icons, image thumbnails downsampled from stored image representations for visible rows only, and right-aligned row numbers. Blob-backed images decode directly from their file URL. A bounded per-view LRU cache is pruned for deleted clips; synthetic drawing/store tests cover thumbnail pixels, visible-only lookup and cache reuse.
- [x] Implemented in source: image rows show actual stored image format, ImageIO pixel dimensions, and stored representation byte size, loaded only for drawn rows and cached for redraws. Automated tests pass; live metadata appearance still needs validation.
- [x] Type icons scale with compact/normal/comfortable density (22/26/30 pt), centered and kept within row bounds; automated geometry checks pass. Live visual verification remains pending.
- [ ] Review image thumbnail sizing/alignment in the paste picker against the reference.
- [x] Implemented in source: right-clicking a visible clip row opens a native **Remove from history** menu for that stable clip ID only. Successful single-item removal leaves the picker open, preserves the query, selects the nearest remaining row, and uses existing store blob cleanup; stale/failed deletion beeps and leaves the model unchanged. Automated tests pass. User verified removal in the running picker.
- [x] Implemented in source: holding the primary pointer and dragging an eligible picker surface moves the borderless picker after a small movement threshold. Row clicks and double-click recall remain distinct, and corner resize areas retain priority. Automated gesture-geometry tests pass. User verified picker movement in the running app; detailed resize and nonactivation checks remain separate.
- [ ] Present picker bottom actions as clear icon-and-label groups while retaining existing keyboard behavior.
- [ ] Move editable picker shortcut selection into the future Settings popup; retain current shortcut setting and registration.
- [ ] Decide whether section headers should actually collapse before adding disclosure chevrons. Do not add nonfunctional chevrons.
- [x] Implemented in source: the footer presents **Clear, Export, Import, Settings** with symbols and separators; Export, Import and deferred Settings are disabled. Clear retains its confirmation flow. Open Picker and Quit remain on a separate secondary row.
- [x] Current header/footer/thumbnail batch passed 1,035 checks and the production release build; packaged with existing identity, strict signature verified, and restarted. User says picker and menu bar items look good/better and requested a commit. Remaining design differences stay queued; do not treat overall visual alignment as complete.

## Queued changes

- [ ] Add an **About** page describing what Simple Clipboard History is, that David Boon made it with help from AI, and its design aesthetic. Agree on the wording and level of detail before implementation. Keep it accessible from the menu bar settings panel and consistent with the menu-bar-only design; do not add a main window or preferences window.
- [x] Renamed **Picker UI** to **Look and feel**. Packaged, signed, and relaunched together with the chart-height reduction from 64 to 43 points. Panel tests pass (207 checks); live appearance still needs user verification.
- [ ] Add password masking. Store password clips as requested, but conceal their contents in the picker, previews, and other app displays. Investigate clipboard metadata from password managers as a detection signal; do not assume arbitrary password text can be identified reliably. Decide how users can mark unrecognized clips as sensitive, whether revealing is allowed, and how search and accessibility output avoid exposing masked contents. Masking is a display feature, not encryption or secure storage. User asked: "If a password is on the clipboard, we do want to store it but we don't want to see it".
- [x] Header tightened from 76 to 64 points, chart reduced from 31 to 17 points, and clipboard header symbol uses a broader 24×26-point frame. The History row shows the configured picker shortcut as a read-only hint. Settings rows use 16-point insets. User approved the updated panel appearance; shortcut editing is deferred to a future Settings popup.
- [x] Implemented in source: **Maximum items** is a freeform positive integer input, persisted without a preset cap. Automated validation covers invalid and overflowing input, native field-editor focus, Tab/Return/blur commits and confirmation lockout; live control behavior still needs checking. This is separate from **Maximum visible items**.
- [x] Implemented in source: green **Active** indicator uses a small square symbol.
- [x] Shared broad empty clipboard outline for the settings header and monochrome menu bar template; generated multi-resolution Finder app icon on a neutral backing and packaged as `AppIcon.icns`. Automated checks pass; live menu bar/Finder appearance still needs user verification.
- [x] Removed **Retention days** from the panel and disabled age-based deletion, including when legacy retention values are present. Count and byte limits remain active; tests updated. Live data-retention behavior still needs checking.
- [x] Header chart shows observed captured-copy activity as six broad blue bars aggregated into 20-hour groups for a fixed five-day range, without a separate label or range selector. Counts are transactionally aggregated in SQLite by absolute Unix-hour bucket, include successful repeated deduplicated copies, and survive clip deletion/eviction. No historical backfill or paste tracking. Packaged, signed, and launched; user approved the improved appearance.

## Questions and follow-up

- [x] Explained that the right-side numbers identify Command-1 through Command-9 shortcuts for visible rows, not permanent clip identifiers. Displaying the modifier beside each number is a possible follow-up, not implemented.
- [ ] Distinguish plain-text-only clips with a capital T from clips with formatted text using the document icon. User approved this distinction; it is not implemented. Defer the code icon until reliable classification rules are defined.
- [ ] Optional manual signing: when ready, sign the already-built app with `bash tools/sign-app.sh` (or `SIGNING_IDENTITY="name" bash tools/sign-app.sh`). Normal development packaging is ad-hoc and does not access the keychain. Do not investigate or repair keychain signing unless explicitly requested.
- [x] Implemented in source: **When pasting**, with choices **Preserve original formatting** and **Paste as plain text**. Display labels only; stored clips and paste semantics are unchanged.
- [ ] Verify appearance settings in the running app: width, content lines, density, maximum visible items, icons, and timestamps. They are intended to work when the picker reopens. A saved manual height cap can limit visible items. No live failure has been confirmed.
- [ ] Improve design instructions: general styling preferences are defaults, not blanket bans on approved design elements. Preserve approved decoration/charts. Ask about conflicts between reference images and written guidance instead of silently omitting elements. Do not invent data semantics for decoration. The proposed instruction has not been installed in an instructions file.

## Current validation and handoff

- All five harnesses pass with 1,069 checks after density-dependent icon sizing. Ad-hoc packaging, strict signature verification, and whitespace checks pass.
- User approved live right-click removal and dragging, then requested committing, merging into `main`, and pushing to `origin`.
- The latest density-dependent type-icon sizing passes automated checks; live appearance remains pending.
- The working branch includes local commit `96ffb4b` above `main` commit `d9a4076`, plus the approved changes awaiting the requested commit and merge. Verify Git history for the final merge state.
- Normal packaging does not access the keychain. Named signing is an optional manual command; do not resume keychain repairs unless requested.

## Historical resume context

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
