// Settings panel layout, controls, confirmation and keyboard checks. Run: bash tools/run-tests.sh
import AppKit
import ServiceManagement
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
func choices(_ name: String) -> PanelDropdown? { view.control(named: name) as? PanelDropdown }
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
check(view.controls.map(\.partName) == ["pause", "login", "hotkey", "ignoreFrontmost", "paste", "plainText", "pasteSpecial",
    "keep", "largest", "historySize", "retention", "clearHistory", "import", "export", "pickerWidth", "contentLines", "density",
    "visibleItems", "typeIcons", "timestamps", "openPicker", "quit"], "four sections in order")
check(view.controls.allSatisfy { view.bounds.contains($0.convert($0.bounds, to: view)) }, "every control inside the panel")
for (index, control) in view.controls.enumerated() {
    for other in view.controls[(index + 1)...] where control.convert(control.bounds, to: view).intersects(other.convert(other.bounds, to: view)) {
        check(false, "\(control.partName) overlaps \(other.partName)")
    }
}
check(checkbox("paste")?.isOn == true && choices("plainText")?.selectedIndex == 0 && checkbox("pause")?.isOn == true, "checkbox states")
check(choices("hotkey")?.selectedIndex == 0 && choices("hotkey")?.titles.last == "None", "hotkey choices")
check(choices("keep")?.titles == ["100", "500", "1,000", "5,000", "10,000"] && choices("keep")?.selectedIndex == 2, "keep choices")
check(choices("largest")?.titles == ["5", "20", "50", "100"] && choices("largest")?.selectedIndex == 1, "largest clip choices")
check(button("openPicker")?.title == "Open Picker  \u{21E7}\u{2318}V", "open picker shows the hotkey")
check(button("ignoreFrontmost")?.title == "+ Ignore kitty", "ignore the frontmost app")
check(render().pixelsWide > 0, "panel draws")
// MARK: checkboxes and choices apply at once
checkbox("paste")?.toggle()
check(settings.recallMode == .clipboard && checkbox("paste")?.isOn == false, "unchecking paste switches to clipboard")
choices("plainText")?.select(1)
check(settings.alwaysPastePlainText && choices("plainText")?.selectedIndex == 1, "always plain text")
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
check(view.focusedPart == "pause", "tab focuses the first control")
view.keyDown(with: key(49, " "))
check(!settings.capturePaused && view.focusedPart == "pause", "space toggles the focused checkbox, focus kept")
view.keyDown(with: key(48, "\t", .shift))
check(view.focusedPart == "quit", "shift-tab wraps to the last control")
for _ in 0..<3 { view.keyDown(with: key(48, "\t")) }
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
// MARK: menu bar icon
check(StatusItemController.icon.isTemplate && StatusItemController.icon.size.width > 0, "menu bar icon is a template image")

// MARK: snapshots for a visual check (only with PANEL_SNAPSHOT_DIRECTORY set)
if let directory = ProcessInfo.processInfo.environment["PANEL_SNAPSHOT_DIRECTORY"] {
    try! FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    // README uses an ordinary production view with default settings and synthetic statistics.
    let normalView = SettingsPanelView()
    var normalContent = content()
    normalContent.settings = Settings()
    normalView.appearance = NSAppearance(named: .aqua)
    normalView.show(normalContent)
    normalView.layoutSubtreeIfNeeded()
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(normalView.bounds.width * 2),
        pixelsHigh: Int(normalView.bounds.height * 2), bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = normalView.bounds.size
    normalView.cacheDisplay(in: normalView.bounds, to: bitmap)
    check(bitmap.pixelsWide == Int(normalView.bounds.width * 2), "README panel snapshot renders at 2x")
    try! bitmap.representation(using: .png, properties: [:])!.write(
        to: URL(fileURLWithPath: directory).appendingPathComponent("control-panel.png"))
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

// MARK: native popup action wiring
if let dropdown = choices("pickerWidth") {
    check(dropdown.popup.accessibilityRole() == .popUpButton, "native popup accessibility role: \(String(describing: dropdown.popup.accessibilityRole()))")
    dropdown.popup.selectItem(at: 0)
    check(dropdown.popup.sendAction(dropdown.popup.action, to: dropdown.popup.target), "native popup sends target action")
    check(settings.pickerWidth == 360 && view.focusedPart == "pickerWidth", "native action binds and preserves focus across rebuild")
}

// MARK: direct appearance/limit bindings are independent
view.show(content())
let beforeAppearance = settings
choices("pickerWidth")?.select(2)
check(settings.pickerWidth == 560 && settings.pickerContentLines == beforeAppearance.pickerContentLines
    && settings.pickerDensity == beforeAppearance.pickerDensity && settings.maximumVisibleItems == beforeAppearance.maximumVisibleItems,
    "width changes independently")
choices("contentLines")?.select(3)
check(settings.pickerContentLines == 5 && settings.pickerWidth == 560 && settings.pickerDensity == 4, "consecutive content lines binding")
choices("density")?.select(1)
check(settings.pickerDensity == 7 && settings.pickerContentLines == 5, "density independent of lines")
choices("visibleItems")?.select(3)
check(settings.maximumVisibleItems == 15 && settings.pickerDensity == 7, "visible cap binding")
checkbox("typeIcons")?.toggle()
checkbox("timestamps")?.toggle()
checkbox("pasteSpecial")?.toggle()
check(!settings.showTypeIcons && settings.showTimestamps && !settings.showPasteSpecial, "picker toggles bind")
choices("historySize")?.select(3)
choices("retention")?.select(0)
check(settings.maximumHistoryMegabytes == 1000 && settings.retentionDays == 7, "history size and retention bind")
check(view.statusLine.contains("142 items") && view.statusLine.contains(Format.bytes(statistics.clipBytes))
    && view.statusLine.contains("1000 MB") && view.statusLine.hasPrefix("Active"), "real status and configured byte limit")
checkbox("pause")?.toggle()
check(view.statusLine.hasPrefix("Paused"), "paused status")
var missingStats = content()
missingStats.statistics = nil
view.show(missingStats)
check(view.statusLine.contains("unavailable"), "unknown history does not claim zero")
view.show(content())

// MARK: disabled operations, accessibility, keyboard focus
for name in ["import", "export"] {
    let control = button(name)!
    check(!control.isEnabled && control.title == "\(name.capitalized): Not implemented"
        && !control.title.unicodeScalars.contains(where: { $0.properties.generalCategory == .dashPunctuation }),
        "\(name) visibly unavailable with a colon label and no dash characters")
    var invoked = false
    control.onPress = { invoked = true }
    control.press()
    _ = control.handleKey(key(49, " "))
    check(!control.accessibilityPerformPress() && !invoked, "\(name) cannot activate by mouse/key/accessibility")
    check(control.accessibilityRole() == .button && control.isAccessibilityEnabled() == false, "\(name) accessibility disabled button")
}
check(checkbox("pause")?.accessibilityRole() == .checkBox, "custom checkbox accessibility role")
check(checkbox("pause")?.accessibilityLabel() == "Enable clipboard history", "checkbox accessible label")
check(choices("pickerWidth")?.popup.accessibilityLabel() == "Width", "native popup accessible label")
check(choices("pickerWidth")?.popup.itemTitles == ["Narrow (360 pt)", "Standard (460 pt)", "Wide (560 pt)"], "native popup choices")
view.resetInteraction()
var visited: [String] = []
for _ in 0..<view.controls.filter({ $0.isEnabled }).count {
    view.moveFocus(by: 1)
    visited.append(view.focusedPart)
}
check(!visited.contains("import") && !visited.contains("export") && visited.contains("pickerWidth"), "tab skips disabled controls and reaches native dropdowns")
view.moveFocus(by: 1)
check(view.focusedPart == "pause", "tab wraps")
button("clearHistory")?.press()
view.moveFocus(by: 1)
check(view.focusedPart == "confirmCancel", "confirmation focus stays within actions")
check(choices("pickerWidth")?.popup.isEnabled == false, "confirmation disables native settings")
view.cancelConfirmation()
check(choices("pickerWidth")?.popup.isEnabled == true, "cancel restores native settings")

// MARK: login source of truth; synthetic adapter never touches system registration
final class FakeLoginService: LoginItemService {
    var status: SMAppService.Status = .notRegistered
    var calls: [String] = []
    var failure: Error?
    var registrationResult: SMAppService.Status = .enabled
    func register() throws { calls.append("register"); if let failure { throw failure }; status = registrationResult }
    func unregister() throws { calls.append("unregister"); if let failure { throw failure }; status = .notRegistered }
    func openSettings() { calls.append("settings") }
}
let service = FakeLoginService()
let login = LoginItemController(service: service)
check(!login.isEnabled && service.calls.isEmpty && login.message == nil, "initial read does not register")
login.setEnabled(true)
check(login.isEnabled && service.calls == ["register"], "explicit opt-in registers")
service.status = .notRegistered
check(!login.isEnabled, "external status changes are authoritative")
service.registrationResult = .requiresApproval
login.setEnabled(true)
check(!login.isEnabled && login.message?.contains("approval") == true, "approval is not reported enabled")
login.setEnabled(true)
check(service.calls.last == "settings", "approval action opens system settings, not another registration")
login.setEnabled(false)
check(service.status == .notRegistered && service.calls.last == "unregister", "explicit opt-out unregisters")
service.failure = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Registration denied"])
login.setEnabled(true)
check(!login.isEnabled && login.message?.contains("Registration denied") == true, "registration failure shown honestly")
service.failure = nil
service.status = .notFound
check(!login.isEnabled, "missing service is not enabled")
let missingService = FakeLoginService()
missingService.status = .notFound
check(LoginItemController(service: missingService).message?.contains("signed app") == true, "missing service diagnostic")
var loginContent = content()
loginContent.loginEnabled = false
loginContent.loginMessage = "Login item needs approval in System Settings"
view.show(loginContent)
var loginRequests: [Bool] = []
view.actions.setLoginEnabled = { loginRequests.append($0) }
checkbox("login")?.toggle()
check(loginRequests == [true] && button("loginStatus") != nil, "login checkbox explicit action and status UI")

// MARK: production window sizing with synthetic content and isolated defaults
let defaultsDomain = "PanelTests.windowSizing.\(UUID().uuidString)"
let temporaryDefaults = UserDefaults(suiteName: defaultsDomain)!
temporaryDefaults.removePersistentDomain(forName: defaultsDomain)
let windowSettings = SettingsStore(defaults: temporaryDefaults)
let windowView = SettingsPanelView()
var visibleFrame = NSRect(x: 100, y: 80, width: 1280, height: 1000)
var anchor: NSRect? = NSRect(x: 1300, y: 1080, width: 26, height: 24)
let windowController = SettingsPanelWindowController(view: windowView) { (anchor, visibleFrame) }
var synthetic = SettingsPanelContent(settings: windowSettings.settings, statistics: statistics,
    clipboardLine: "not recorded: synthetic failure", frontmostApp: ("test.front", "Test App"),
    notices: [], appNames: [:], hotkeyLabel: nil)
windowView.actions.update = { change in
    windowSettings.update(change)
    synthetic.settings = windowSettings.settings
    windowController.show(synthetic)
}
windowView.actions.keepHistory = { limit in
    windowSettings.update { $0.historyLimit = limit }
    synthetic.settings = windowSettings.settings
    windowController.show(synthetic)
}
windowController.show(synthetic)
let realPanel = windowController.panel
func windowFits(_ label: String) {
    check(visibleFrame.contains(realPanel.frame), "\(label): frame within anchor screen")
    check(realPanel.contentView?.bounds.size == windowView.frame.size
        && windowView.frame.height == realPanel.frame.height, "\(label): content and window sizes agree")
    check(realPanel.frame.maxY == min(anchor.map { $0.minY - 4 } ?? visibleFrame.maxY - 4, visibleFrame.maxY - 4),
          "\(label): top stays anchored")
}
func visibleControl(_ name: String) -> Bool {
    guard let control = windowView.control(named: name) else { return false }
    return windowView.bounds.contains(control.convert(control.bounds, to: windowView))
        && control.visibleRect.contains(control.bounds)
}
windowFits("initial")
check(realPanel.styleMask.contains(.nonactivatingPanel), "production window remains nonactivating")
let ordinaryHeight = realPanel.frame.height
(windowView.control(named: "clearHistory") as? PanelButton)?.press()
check(realPanel.frame.height == ordinaryHeight + 24 && windowView.preferredHeight == realPanel.frame.height,
      "clear confirmation immediately grows the owning window")
windowFits("confirmation")
(windowView.control(named: "confirmCancel") as? PanelButton)?.press()
check(realPanel.frame.height == ordinaryHeight, "cancel immediately shrinks the owning window")
(windowView.control(named: "keep") as? PanelDropdown)?.select(0)
check(windowView.confirmation == .keepHistory(limit: 100, deleting: 42)
    && realPanel.frame.height == ordinaryHeight + 24, "smaller-limit confirmation also resizes")
windowView.keyDown(with: key(53))
check(realPanel.frame.height == ordinaryHeight, "escape cancel shrinks without external refresh")
(windowView.control(named: "keep") as? PanelDropdown)?.select(0)
windowView.confirm()
check(windowSettings.settings.historyLimit == 100 && realPanel.frame.height == ordinaryHeight,
      "confirm applies through temporary defaults and restores ordinary height")

// A 720-point display with notices, login detail and many exclusions must scroll, not escape its screen.
visibleFrame = NSRect(x: -1280, y: -200, width: 1280, height: 696)
anchor = NSRect(x: -30, y: 496, width: 26, height: 24)
windowSettings.update { $0.ignoredApps = (0..<40).map { "test.ignored.\($0)" } }
synthetic.settings = windowSettings.settings
synthetic.notices = [.needsAccessibility, .hotkeyUnavailable(.shiftCommandV)]
synthetic.loginMessage = "Synthetic login item needs approval"
windowController.show(synthetic)
windowFits("overflow")
check(windowView.preferredHeight > realPanel.frame.height && realPanel.frame.height == visibleFrame.height - 8,
      "overflow is bounded to the anchor screen's available height")
check(windowView.scrollView.documentView!.frame.height > windowView.scrollView.contentView.bounds.height,
      "overflowing settings have a scroll document")
check(visibleControl("openPicker") && visibleControl("quit"), "fixed footer remains visible before scrolling")
windowView.resetInteraction()
var allFocusedControlsVisible = true
for _ in 0..<windowView.controls.filter({ $0.isEnabled }).count {
    windowView.moveFocus(by: 1)
    allFocusedControlsVisible = allFocusedControlsVisible && visibleControl(windowView.focusedPart)
}
check(allFocusedControlsVisible, "every enabled control is brought fully into view by Tab")
check(windowView.scrollView.contentView.bounds.minY > 0, "keyboard navigation scrolls overflowing settings")
check(visibleControl("openPicker") && visibleControl("quit"), "footer remains visible after scrolling")
_ = (windowView.control(named: "pause") as? PanelCheckbox)?.accessibilityPerformPress()
check(visibleControl("pause"), "accessibility action reveals and focuses an offscreen custom control")
let widthPopup = (windowView.control(named: "pickerWidth") as! PanelDropdown).popup
widthPopup.keyDown(with: key(48, "\t"))
check(windowView.focusedPart == "contentLines" && visibleControl("contentLines"),
      "native popup Tab routes through the panel even inside its scroll document")
(windowView.control(named: "clearHistory") as? PanelButton)?.press()
windowFits("bounded confirmation")
check(visibleControl("confirmDelete") && visibleControl("confirmCancel"), "bounded confirmation actions stay visible")
windowView.keyDown(with: key(53))
check(visibleControl("openPicker") && visibleControl("quit"), "bounded cancel restores reachable footer")
for _ in 0..<windowView.controls.count {
    windowView.moveFocus(by: 1)
    if windowView.focusedPart == "timestamps" { break }
}
visibleFrame = NSRect(x: -800, y: 0, width: 800, height: 360)
anchor = NSRect(x: -30, y: 360, width: 26, height: 24)
windowController.resizeToFit()
windowFits("smaller display")
check(visibleControl("timestamps"), "changing display bounds reveals the retained focused setting")
check(visibleControl("openPicker") && visibleControl("quit"), "footer stays reachable on a 360-point display")
(windowView.control(named: "clearHistory") as? PanelButton)?.press()
check(visibleControl("confirmDelete") && visibleControl("confirmCancel"), "confirmation stays reachable on a 360-point display")
windowView.cancelConfirmation()

// Shrinking content and moving between screens reuse the same production sizing path.
windowSettings.update { $0.ignoredApps = [] }
synthetic.settings = windowSettings.settings
synthetic.notices = []
synthetic.loginMessage = nil
visibleFrame = NSRect(x: 0, y: 0, width: 1440, height: 1000)
anchor = NSRect(x: 10, y: 1000, width: 26, height: 24)
windowController.show(synthetic)
windowFits("shorter refresh")
check(realPanel.frame.height == windowView.preferredHeight, "refresh removes unnecessary scrolling on a larger screen")
check(windowView.scrollView.contentView.bounds.minY == 0, "shorter refresh clamps stale scroll position")
anchor = nil
windowController.resizeToFit()
windowFits("missing anchor")

// Compact clipboard diagnostics retain the entire troubleshooting text for hover and accessibility.
for diagnostic in ["not recorded: synthetic failure", "not recorded: marked concealed",
                   "not recorded from Test: test.ignored is ignored",
                   "not recorded: larger than the limit (21 MB read)"] {
    synthetic.clipboardLine = diagnostic
    windowController.show(synthetic)
    let detail = windowView.scrollView.documentView!.subviews.compactMap { $0 as? NSTextField }
        .first { $0.accessibilityIdentifier() == "clipboardStatus" }
    check(detail?.stringValue == "Clipboard: " + diagnostic && detail?.toolTip == "Clipboard: " + diagnostic
        && detail?.accessibilityLabel() == "Clipboard: " + diagnostic, "diagnostic visible, hoverable and accessible: \(diagnostic)")
}
temporaryDefaults.removePersistentDomain(forName: defaultsDomain)
realPanel.close()

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
