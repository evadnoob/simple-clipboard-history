// Picker model, key mapping, drawing, preview and hotkey settings checks. Run: bash tools/run-tests.sh
import AppKit
@testable import SimpleClipboardKit

var checks = 0
var failures = 0
func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    checks += 1
    if !condition() { failures += 1; print("FAIL: \(label)") }
}

let start = Date(timeIntervalSince1970: 1_800_000_000)
func clip(_ id: Int64, _ preview: String) -> ClipSummary {
    ClipSummary(id: id, kind: "text", preview: preview, byteSize: preview.utf8.count, firstCopiedAt: start,
                lastCopiedAt: start.addingTimeInterval(TimeInterval(-id * 60)), copyCount: 1, sourceAppName: "Safari")
}
/// 30 clips, ids 1...30, newest first. The search is a plain substring filter.
let all = (1...30).map { clip(Int64($0), $0 % 2 == 0 ? "even clip \($0)" : "odd clip \($0)") }
var searches: [String] = []
func search(_ query: String, _ limit: Int) -> [ClipSummary] {
    searches.append(query)
    let rows = query.isEmpty ? all : all.filter { $0.preview.localizedCaseInsensitiveContains(query) }
    return Array(rows.prefix(limit))
}

// MARK: model: open, move, scroll
let model = PickerModel(search: search)
model.visibleRowCount = 5
model.reset()
check(model.rows.count == 30 && model.selectedIndex == 0 && model.firstRow == 0, "reset loads newest clips, first selected")
check(model.handle(.up) == .none && model.selectedIndex == 0, "up at the top stays")
for _ in 0..<5 { _ = model.handle(.down) }
check(model.selectedIndex == 5 && model.firstRow == 1, "down past the last visible row scrolls")
_ = model.handle(.pageDown)
check(model.selectedIndex == 10 && model.firstRow == 6, "page down moves a page")
_ = model.handle(.end)
check(model.selectedIndex == 29 && model.firstRow == 25, "end selects the last row")
_ = model.handle(.home)
check(model.selectedIndex == 0 && model.firstRow == 0, "home selects the first row")
model.scroll(by: 100)
check(model.firstRow == 25 && model.selectedIndex == 0, "scroll wheel stops at the last page and keeps the selection")
model.scroll(by: -100)
check(model.firstRow == 0, "scroll wheel stops at the top")

// MARK: model: recall
check(model.handle(.enter) == .recall(1), "return recalls the selected clip")
check(model.handle(.recallNumber(3)) == .recall(3), "cmd-3 recalls the third visible row")
check(model.handle(.recallNumber(6)) == .none, "cmd-6 with five visible rows does nothing")
_ = model.handle(.pageDown)
check(model.handle(.recallNumber(1)) == .recall(Int64(model.firstRow + 1)), "numbers count from the first visible row")

// MARK: model: query
model.reset()
_ = model.handle(.text("od"))
_ = model.handle(.text("d"))
check(model.query == "odd", "typing builds the query")
check(model.rows.count == 15 && model.rows.allSatisfy { $0.preview.hasPrefix("odd") }, "query filters rows")
check(model.selectedIndex == 0 && model.firstRow == 0, "query change selects the first match")
_ = model.handle(.text("\r"))
_ = model.handle(.text("\u{7f}"))
check(model.query == "odd", "control characters are not typed")
_ = model.handle(.deleteBackward)
check(model.query == "od", "backspace deletes one character")
_ = model.handle(.text(" clip 1"))
_ = model.handle(.deleteWordBackward)
check(model.query == "od clip ", "option-backspace deletes the last word")
_ = model.handle(.clearQuery)
check(model.query == "" && model.rows.count == 30, "clear query shows every clip")
_ = model.handle(.text("nothing like this"))
check(model.rows.isEmpty && model.selectedIndex == nil, "no matches, no selection")
check(model.handle(.enter) == .none, "return with no matches does nothing")
check(model.handle(.down) == .none && model.selectedIndex == nil, "moving with no rows is safe")
searches.removeAll()
_ = model.handle(.deleteBackward)
_ = model.handle(.clearQuery)
_ = model.handle(.clearQuery)
check(searches.count == 2, "search runs only when the query changes")

// MARK: model: preview and escape
model.reset()
check(model.handle(.tab) == .none && model.previewOpen, "tab opens the preview")
check(model.handle(.escape) == .none && !model.previewOpen, "escape closes the preview first")
check(model.handle(.escape) == .close, "escape closes the picker")
_ = model.handle(.tab)
model.reset()
check(!model.previewOpen && model.query.isEmpty, "reopening starts clean")

// MARK: key mapping
func key(_ code: UInt16, _ characters: String, _ flags: NSEvent.ModifierFlags = []) -> PickerKey? {
    let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                                 context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                 isARepeat: false, keyCode: code)!
    return PickerView.pickerKey(for: event)
}
check(key(126, "") == .up && key(125, "") == .down, "arrows")
check(key(116, "") == .pageUp && key(121, "") == .pageDown && key(115, "") == .home && key(119, "") == .end, "page keys")
check(key(36, "\r") == .enter && key(76, "\u{3}") == .enter, "return and keypad enter")
check(key(53, "\u{1b}") == .escape && key(48, "\t") == .tab, "escape and tab")
check(key(51, "\u{7f}") == .deleteBackward, "backspace")
check(key(51, "\u{7f}", .option) == .deleteWordBackward, "option-backspace")
check(key(51, "\u{7f}", .command) == .clearQuery, "command-backspace")
check(key(18, "1", .command) == .recallNumber(1) && key(25, "9", .command) == .recallNumber(9), "command-digits")
check(key(29, "0", .command) == nil, "command-0 is not a recall")
check(key(13, "w", .command) == .escape, "command-w closes")
check(key(9, "v", .command) == nil, "other command keys are ignored")
check(key(45, "n", .control) == .down && key(35, "p", .control) == .up, "control-n and control-p")
check(key(5, "g", .control) == .escape && key(32, "u", .control) == .clearQuery, "control-g and control-u")
check(key(0, "a") == .text("a") && key(0, "A", .shift) == .text("A"), "letters type")

// MARK: view: drawing offscreen and hit testing
let viewModel = PickerModel(search: search)
let view = PickerView(model: viewModel)
view.now = { start }
viewModel.reset()
view.layout()
let expectedRows = Int(floor(view.chrome.listRect.height / PickerStyle.rowHeight))
check(viewModel.visibleRowCount == expectedRows && expectedRows >= 10, "row count follows the list height (\(expectedRows))")
func render(_ view: NSView) -> NSBitmapImageRep {
    let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: bitmap)
    return bitmap
}
check(render(view).pixelsWide > 0, "picker draws")
let secondRow = NSPoint(x: 100, y: view.chrome.listRect.minY + PickerStyle.rowHeight * 1.5)
check(view.rowIndex(at: secondRow) == 1, "click point maps to a row")
check(view.rowIndex(at: NSPoint(x: 100, y: 2)) == nil, "title row is not a clip row")
var actions: [PickerAction] = []
view.onAction = { actions.append($0) }
view.perform(.recallNumber(2))
check(actions == [.recall(2)], "view passes the model's action on")
view.loadItems = { _ in [[Representation(type: NSPasteboard.PasteboardType.string.rawValue, data: Data("full text".utf8))]] }
view.perform(.tab)
check(viewModel.visibleRowCount < expectedRows, "preview makes the list shorter")
check(render(view).pixelsWide > 0, "picker draws with the preview open")
viewModel.reset()
_ = viewModel.handle(.text("nothing like this"))
check(render(view).pixelsWide > 0, "picker draws with no matches")
check(PickerView.rowDetail(clip(3, "x"), now: start) == "3m  Safari", "row detail is age and app")
check(PickerView.tail(of: "abcdef", fitting: PickerStyle.width(of: "def")) == "def", "long query shows its end")

// MARK: preview content
let text = Data("hello".utf8)
if case .text(let value) = ClipPreview.make(from: [[Representation(type: NSPasteboard.PasteboardType.string.rawValue, data: text)]]) {
    check(value == "hello", "text preview")
} else { check(false, "text preview kind") }
let fileItems = [[Representation(type: NSPasteboard.PasteboardType.fileURL.rawValue, data: Data("file:///tmp/a%20b.txt".utf8)),
                  Representation(type: NSPasteboard.PasteboardType.string.rawValue, data: Data("a b.txt".utf8))]]
if case .files(let paths) = ClipPreview.make(from: fileItems) { check(paths == ["/tmp/a b.txt"], "file preview paths") } else {
    check(false, "file preview kind")
}
let image = NSImage(size: NSSize(width: 4, height: 4))
image.lockFocus(); NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 4, height: 4).fill(); image.unlockFocus()
let tiff = image.tiffRepresentation!
if case .image(let decoded) = ClipPreview.make(from: [[Representation(type: NSPasteboard.PasteboardType.tiff.rawValue, data: tiff)]]) {
    check(decoded.size.width == 4, "image preview")
} else { check(false, "image preview kind") }
if case .other(let types) = ClipPreview.make(from: [[Representation(type: "com.example.private", data: Data([1]))]]) {
    check(types == "com.example.private", "unknown types listed")
} else { check(false, "other preview kind") }

// MARK: panel placement
let frame = PickerController.frame(for: PickerStyle.boxSize, on: NSScreen.main)
if let visible = NSScreen.main?.visibleFrame {
    check(visible.contains(frame), "picker frame is on the screen")
    check(abs(frame.midX - visible.midX) <= 1, "picker is centered horizontally")
    check(frame.midY >= visible.midY, "picker sits at or above the middle")
}

// MARK: hotkey setting
let suite = "simple-clipboard-picker-tests-\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
let settingsStore = SettingsStore(defaults: defaults)
check(settingsStore.settings.pickerHotkey == .shiftCommandV, "default hotkey is shift-command-v")
settingsStore.update { $0.pickerHotkey = .controlCommandV }
check(SettingsStore(defaults: defaults).settings.pickerHotkey == .controlCommandV, "hotkey choice persists")
defaults.set("hyper-v", forKey: "pickerHotkey")
check(SettingsStore(defaults: defaults).settings.pickerHotkey == .shiftCommandV, "unknown hotkey reads as the default")
defaults.removePersistentDomain(forName: suite)
check(HotkeyChoice.none.carbonModifiers == 0 && HotkeyChoice.allCases.filter { $0 != .none }.allSatisfy { $0.carbonModifiers != 0 },
      "every hotkey except none has modifiers")
let hotkey = GlobalHotkey {}
hotkey.register(.none)
check(hotkey.status == .off, "none registers nothing")

// MARK: snapshots for a visual check (only with PICKER_SNAPSHOT_DIRECTORY set)
if let directory = ProcessInfo.processInfo.environment["PICKER_SNAPSHOT_DIRECTORY"],
   let dataDirectory = ProcessInfo.processInfo.environment["PICKER_SNAPSHOT_DATA"] {
    let realStore = try! ClipStore(directory: URL(fileURLWithPath: dataDirectory))
    let snapshotModel = PickerModel(search: { (try? realStore.search($0, limit: $1)) ?? [] })
    let snapshotView = PickerView(model: snapshotModel)
    snapshotView.loadItems = { (try? realStore.items(for: $0)) ?? [] }
    for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
        snapshotView.appearance = NSAppearance(named: appearanceName)
        snapshotModel.reset()
        snapshotView.layout()
        for (name, keys) in [("list", [PickerKey]()), ("preview", [.down, .tab]), ("search", [.text("test")])] {
            snapshotModel.reset()
            keys.forEach { snapshotView.perform($0) }
            let bitmap = render(snapshotView)
            let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name)-\(appearanceName.rawValue).png")
            try! bitmap.representation(using: .png, properties: [:])!.write(to: url)
        }
    }
}

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
