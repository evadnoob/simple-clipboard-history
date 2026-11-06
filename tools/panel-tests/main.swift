// Settings panel layout, controls, confirmation and keyboard checks. Run: bash tools/run-tests.sh
import AppKit
@testable import SimpleClipboardKit

var checks = 0
var failures = 0
func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    checks += 1
    if !condition() { failures += 1; print("FAIL: \(label)") }
}

let now = Date(timeIntervalSince1970: 1_800_000_000)
let latest = ClipSummary(id: 1, kind: "text", preview: "x", byteSize: 1, firstCopiedAt: now, lastCopiedAt: now.addingTimeInterval(-180),
                         copyCount: 1, sourceAppName: "kitty")
var settings = Settings()
var statistics = StoreStatistics(clipCount: 142, clipBytes: 3_500_000, diskBytes: 2_200_000,
                                 oldestCopiedAt: now.addingTimeInterval(-86_400), latest: latest)
var calls: [String] = []

let view = SettingsPanelView()
var actions = SettingsPanelActions()
func content() -> SettingsPanelContent {
    SettingsPanelContent(settings: settings, statistics: statistics, clipboardLine: "text, 1.2 KB from Firefox",
                         frontmostApp: (identifier: "net.kovidgoyal.kitty", name: "kitty"), notices: [],
                         appNames: ["com.1password.1password": "1Password"], hotkeyLabel: "\u{21E7}\u{2318}V", now: now)
}
actions.update = { change in change(&settings); calls.append("update"); view.show(content()) }
actions.keepHistory = { limit in settings.historyLimit = limit; calls.append("keep \(limit)"); view.show(content()) }
actions.clearHistory = { calls.append("clear") }
actions.openPicker = { calls.append("picker") }
actions.openNotice = { calls.append("notice \($0)") }
actions.quit = { calls.append("quit") }
actions.close = { calls.append("close") }
view.actions = actions
view.show(content())

func checkbox(_ name: String) -> PanelCheckbox? { view.control(named: name) as? PanelCheckbox }
func choices(_ name: String) -> PanelChoiceRow? { view.control(named: name) as? PanelChoiceRow }
func button(_ name: String) -> PanelButton? { view.control(named: name) as? PanelButton }
func key(_ code: UInt16, _ characters: String = "", _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                     characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
}
func render() -> NSBitmapImageRep {
    let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: bitmap)
    return bitmap
}

// MARK: layout
check(view.frame.width == SettingsPanelView.width && view.frame.height == view.preferredHeight, "view sized to its content")
check(view.preferredHeight > 300 && view.preferredHeight < 700, "height is reasonable (\(view.preferredHeight))")
check(view.controls.map(\.partName) == ["paste", "plainText", "pause", "hotkey", "keep", "largest", "ignoreFrontmost",
                                        "openPicker", "clearHistory", "quit"], "controls in order: \(view.controls.map(\.partName))")
check(view.controls.allSatisfy { view.bounds.contains($0.frame) }, "every control inside the panel")
for (index, control) in view.controls.enumerated() {
    for other in view.controls[(index + 1)...] where control.frame.intersects(other.frame) {
        check(false, "\(control.partName) overlaps \(other.partName)")
    }
}
check(checkbox("paste")?.isOn == true && checkbox("plainText")?.isOn == false && checkbox("pause")?.isOn == false, "checkbox states")
check(choices("hotkey")?.selectedIndex == 0 && choices("hotkey")?.titles.last == "None", "hotkey choices")
check(choices("keep")?.titles == ["100", "500", "1,000", "5,000", "10,000"] && choices("keep")?.selectedIndex == 2, "keep choices")
check(choices("largest")?.titles == ["5", "20", "50", "100"] && choices("largest")?.selectedIndex == 1, "largest clip choices")
check(button("openPicker")?.title == "Open Picker  \u{21E7}\u{2318}V", "open picker shows the hotkey")
check(button("ignoreFrontmost")?.title == "+ Ignore kitty", "ignore the frontmost app")
check(render().pixelsWide > 0, "panel draws")
if let choiceRow = choices("keep") {
    check(choiceRow.choiceRects().last!.maxX <= choiceRow.bounds.width, "keep choices fit their row")
}

// MARK: checkboxes and choices apply at once
checkbox("paste")?.toggle()
check(settings.recallMode == .clipboard && checkbox("paste")?.isOn == false, "unchecking paste switches to clipboard")
checkbox("plainText")?.toggle()
check(settings.alwaysPastePlainText && checkbox("plainText")?.isOn == true, "always plain text")
checkbox("pause")?.toggle()
check(settings.capturePaused, "pause")
choices("hotkey")?.select(2)
check(settings.pickerHotkey == .controlCommandV, "hotkey choice")
choices("hotkey")?.select(4)
check(settings.pickerHotkey == HotkeyChoice.none, "no hotkey")
choices("largest")?.select(3)
check(settings.maximumClipMegabytes == 100, "largest clip choice")
choices("keep")?.select(4)
check(settings.historyLimit == 10_000 && view.confirmation == nil, "a larger limit applies without asking")

// MARK: ignored apps
button("ignoreFrontmost")?.press()
check(settings.ignoredApps == ["net.kovidgoyal.kitty"], "ignore adds the frontmost app")
check(button("ignoreFrontmost") == nil && checkbox("ignored:net.kovidgoyal.kitty")?.isOn == true, "ignored app listed with a checkbox")
check(checkbox("ignored:net.kovidgoyal.kitty")?.title == "net.kovidgoyal.kitty", "unknown app name falls back to the identifier")
settings.ignoredApps.append("com.1password.1password")
view.show(content())
check(checkbox("ignored:com.1password.1password")?.title == "1Password", "known app name shown")
checkbox("ignored:net.kovidgoyal.kitty")?.toggle()
check(settings.ignoredApps == ["com.1password.1password"], "unchecking stops ignoring")
check(button("ignoreFrontmost") != nil, "the frontmost app can be ignored again")

// MARK: confirmation inside the panel
calls.removeAll()
choices("keep")?.select(0)
check(view.confirmation == .keepHistory(limit: 100, deleting: 42) && settings.historyLimit == 10_000, "a smaller limit asks first")
check(button("confirmDelete")?.isFocused == true && button("openPicker") == nil, "confirmation replaces the buttons, delete focused")
check(render().pixelsWide > 0, "confirmation draws")
view.keyDown(with: key(53, "\u{1b}"))
check(view.confirmation == nil && settings.historyLimit == 10_000 && calls.isEmpty, "escape cancels")
choices("keep")?.select(0)
view.keyDown(with: key(36, "\r"))
check(calls == ["keep 100"] && view.confirmation == nil && settings.historyLimit == 100, "return confirms")
calls.removeAll()
button("clearHistory")?.press()
check(view.confirmation == .clearHistory(clipCount: 142), "clear history asks first")
button("confirmCancel")?.press()
check(view.confirmation == nil && calls.isEmpty, "cancel button")
button("clearHistory")?.press()
button("confirmDelete")?.press()
check(calls == ["clear"], "delete button clears")
statistics.clipCount = 0
view.show(content())
calls.removeAll()
button("clearHistory")?.press()
check(view.confirmation == nil && calls.isEmpty, "nothing to clear, no question")
statistics.clipCount = 142
view.show(content())

// MARK: buttons and keys
calls.removeAll()
button("openPicker")?.press()
button("quit")?.press()
check(calls == ["picker", "quit"], "open picker and quit")
calls.removeAll()
view.resetInteraction()
check(view.focusedPart == "", "nothing focused at first")
view.keyDown(with: key(48, "\t"))
check(view.focusedPart == "paste", "tab focuses the first control")
view.keyDown(with: key(49, " "))
check(settings.recallMode == .paste && view.focusedPart == "paste", "space toggles the focused checkbox, focus kept")
view.keyDown(with: key(48, "\t", .shift))
check(view.focusedPart == "quit", "shift-tab wraps to the last control")
for _ in 0..<4 { view.keyDown(with: key(48, "\t")) }
check(view.focusedPart == "hotkey", "tab reaches the hotkey row")
check(settings.pickerHotkey == HotkeyChoice.none, "hotkey is none before the arrow keys")
view.keyDown(with: key(124))
check(settings.pickerHotkey == HotkeyChoice.none, "right arrow at the last choice stays")
view.keyDown(with: key(123))
check(settings.pickerHotkey == .shiftOptionCommandV, "left arrow changes the choice")
calls.removeAll()
view.keyDown(with: key(53, "\u{1b}"))
check(calls == ["close"], "escape closes the panel")
check(view.performKeyEquivalent(with: key(13, "w", .command)) && calls == ["close", "close"], "command-w closes")

// MARK: notices
var withNotices = content()
withNotices.notices = [.needsAccessibility, .hotkeyUnavailable(.shiftCommandV)]
view.show(withNotices)
let notices = view.controls.filter { $0.partName == "notice" }.compactMap { $0 as? PanelButton }
check(notices.count == 2 && notices[0].title.hasPrefix("Pasting needs Accessibility"), "notices listed")
calls.removeAll()
notices[0].press()
check(calls == ["notice needsAccessibility"], "notice opens its fix")
check(!PanelNotice.hotkeyUnavailable(.shiftCommandV).title.contains("\u{2014}"), "no em dash in notices")
let noticeWidth = SettingsPanelView.width - InterfaceStyle.gap * 2 - 6
let longestNotice = [PanelNotice.needsAccessibility] + HotkeyChoice.allCases.map { PanelNotice.hotkeyUnavailable($0) }
check(longestNotice.allSatisfy { InterfaceStyle.width(of: $0.title) <= noticeWidth }, "every notice fits on one line")
let detail = "last copy 59m ago in Visual Studio Code"
let labelWidth = InterfaceStyle.width(of: "Largest clip") + InterfaceStyle.gap * 2
check(InterfaceStyle.width(of: detail) <= SettingsPanelView.width - labelWidth - InterfaceStyle.gap * 2, "history detail fits")

// MARK: snapshots for a visual check (only with PANEL_SNAPSHOT_DIRECTORY set)
if let directory = ProcessInfo.processInfo.environment["PANEL_SNAPSHOT_DIRECTORY"] {
    for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
        view.appearance = NSAppearance(named: appearanceName)
        view.show(withNotices)
        try! render().representation(using: .png, properties: [:])!.write(
            to: URL(fileURLWithPath: directory).appendingPathComponent("panel-\(appearanceName.rawValue).png"))
        choices("keep")?.select(0)
        try! render().representation(using: .png, properties: [:])!.write(
            to: URL(fileURLWithPath: directory).appendingPathComponent("panel-confirm-\(appearanceName.rawValue).png"))
        view.cancelConfirmation()
    }
}

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
