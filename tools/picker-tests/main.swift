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
check(model.handle(.enter) == .recall(1, .original), "return recalls the selected clip with formatting")
check(model.handle(.recallNumber(3)) == .recall(3, .original), "cmd-3 recalls the third visible row")
check(model.handle(.recallNumber(6)) == .none, "cmd-6 with five visible rows does nothing")
_ = model.handle(.pageDown)
check(model.handle(.recallNumber(1)) == .recall(Int64(model.firstRow + 1), .original), "numbers count from the first visible row")

// MARK: model: plain text
model.reset()
check(model.handle(.enterAlternate) == .recall(1, .plainText), "shift-return recalls plain text")
model.alwaysPastePlainText = true
check(model.handle(.enter) == .recall(1, .plainText), "always plain: return recalls plain text")
check(model.handle(.enterAlternate) == .recall(1, .original), "always plain: shift-return keeps formatting")
check(model.handle(.recallNumber(2)) == .recall(2, .plainText), "always plain: numbers recall plain text")
model.alwaysPastePlainText = false

// MARK: model: filter step
model.reset()
_ = model.handle(.text("odd"))
_ = model.handle(.down)
let filterClip = model.selectedClip!.id
check(model.handle(.enterFilter) == .none && model.step == .filters(clipID: filterClip), "cmd-return opens the filters for the clip")
check(model.filterRows.first == .heading(.textAndWriting), "filters start with a group heading")
check(model.selectedFilter?.id == "plain-text", "first filter selected, not the heading")
check(model.filterRows.filter { if case .heading = $0 { return true } else { return false } }.count == 3, "three group headings")
_ = model.handle(.up)
check(model.selectedFilter?.id == "plain-text", "up from the first filter stays on it")
_ = model.handle(.down)
check(model.selectedFilter?.id == "single-line", "down moves to the next filter")
_ = model.handle(.end)
check(model.selectedFilter?.id == TextFilter.all.last?.id, "end selects the last filter")
_ = model.handle(.home)
check(model.selectedFilter?.id == "plain-text", "home selects the first filter")
_ = model.handle(.text("base64"))
check(model.filterQuery == "base64" && model.query == "odd", "typing in the filter step searches filters only")
check(model.filterRows == [.heading(.developer), .filter(TextFilter.named("base64-encode")!), .filter(TextFilter.named("base64-decode")!)],
      "matching filters under their heading")
_ = model.handle(.down)
check(model.handle(.enter) == .recall(filterClip, .filter("base64-decode")), "return recalls the clip through the filter")
check(model.handle(.enterAlternate) == .recall(filterClip, .filter("base64-decode")), "shift-return in the filter step is the same")
_ = model.handle(.text("zzz"))
check(model.filterRows.isEmpty && model.selectedFilter == nil && model.handle(.enter) == .none, "no matching filters, nothing to recall")
check(model.handle(.escape) == .none && model.step == .clips, "escape goes back to the clips")
check(model.query == "odd" && model.selectedClip?.id == filterClip, "clip query and selection kept")
check(model.handle(.escape) == .close, "escape again closes")
model.visibleRowCount = 4
_ = model.handle(.enterFilter)
for _ in 0..<12 { _ = model.handle(.down) }
let selectedFilterRow = model.selectedFilterIndex!
check(selectedFilterRow >= model.firstFilterRow && selectedFilterRow < model.firstFilterRow + 4, "filter list scrolls to the selection")
model.reset()
check(model.step == .clips, "reopening starts at the clips")
model.visibleRowCount = 5

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
check(key(36, "\r", .shift) == .enterAlternate, "shift-return")
check(key(36, "\r", .command) == .enterFilter, "command-return")
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
let expectedRows = Int(floor(view.chrome.listRect.height / InterfaceStyle.rowHeight))
check(viewModel.visibleRowCount == expectedRows && expectedRows >= 10, "row count follows the list height (\(expectedRows))")
func render(_ view: NSView) -> NSBitmapImageRep {
    let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: bitmap)
    return bitmap
}
check(render(view).pixelsWide > 0, "picker draws")
let secondRow = NSPoint(x: 100, y: view.chrome.listRect.minY + InterfaceStyle.rowHeight * 1.5)
check(view.rowIndex(at: secondRow) == 1, "click point maps to a row")
check(view.rowIndex(at: NSPoint(x: 100, y: 2)) == nil, "title row is not a clip row")
var actions: [PickerAction] = []
view.onAction = { actions.append($0) }
view.perform(.recallNumber(2))
check(actions == [.recall(2, .original)], "view passes the model's action on")
view.loadItems = { _ in [[Representation(type: NSPasteboard.PasteboardType.string.rawValue, data: Data("full text".utf8))]] }
view.perform(.tab)
check(viewModel.visibleRowCount < expectedRows, "preview makes the list shorter")
check(render(view).pixelsWide > 0, "picker draws with the preview open")
viewModel.reset()
_ = viewModel.handle(.text("nothing like this"))
check(render(view).pixelsWide > 0, "picker draws with no matches")
check(PickerView.rowDetail(clip(3, "x"), now: start) == "3m  Safari", "row detail is age and app")
viewModel.reset()
check(view.barHints.contains("\u{21E7}\u{21A9} plain") && view.barHints.contains("\u{2318}\u{21A9} filter"), "hints show plain and filter keys")
viewModel.alwaysPastePlainText = true
check(view.barHints.contains("\u{21E7}\u{21A9} formatted"), "always plain: hints swap")
viewModel.alwaysPastePlainText = false
view.perform(.enterFilter)
check(render(view).pixelsWide > 0, "filter step draws")
check(view.barHints.contains("esc back"), "filter step hints")
let firstFilterPoint = NSPoint(x: 100, y: view.chrome.listRect.minY + InterfaceStyle.rowHeight * 1.5)
check(view.rowIndex(at: firstFilterPoint) == 1, "filter row hit")
check(view.rowIndex(at: NSPoint(x: 100, y: view.chrome.listRect.minY + 2)) == nil, "heading is not clickable")
actions.removeAll()
view.perform(.enter)
check(actions == [.recall(1, .filter("plain-text"))], "view recalls through the filter")
check(PickerView.tail(of: "abcdef", fitting: InterfaceStyle.width(of: "\u{2026}def")) == "\u{2026}def", "long text shows its end")
check(PickerView.tail(of: "abc", fitting: 1000) == "abc", "short text unchanged")
viewModel.reset()
check(view.barStatus == "30 clips", "bar shows the clip count")
view.perform(.text("odd"))
check(view.barStatus == "15 matching \"odd\"", "bar shows matches and the typed text")
view.perform(.enterFilter)
check(view.barStatus == "\(TextFilter.all.count) filters", "filter step shows the filter count")
view.perform(.text("base64"))
check(view.barStatus == "2 filters matching \"base64\"", "filter step shows matches and the typed text")
view.perform(.escape)
view.perform(.clearQuery)

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
let frame = PickerController.frame(for: InterfaceStyle.pickerSize, on: NSScreen.main)
if let visible = NSScreen.main?.visibleFrame {
    check(visible.contains(frame), "picker frame is on the screen")
    check(abs(frame.midX - visible.midX) <= 1, "picker is centered horizontally")
    check(frame.midY >= visible.midY, "picker sits at or above the middle")
}

// MARK: resizing
let dragFrame = NSRect(x: 100, y: 100, width: 600, height: 400)
let limits = (minimum: NSSize(width: 420, height: 200), maximum: NSSize(width: 2000, height: 1000))
check(WindowFrame.dragged(dragFrame, corner: .bottomRight, dx: 50, dy: -30, minimum: limits.minimum, maximum: limits.maximum)
      == NSRect(x: 100, y: 70, width: 650, height: 430), "bottom-right drag keeps the top left")
check(WindowFrame.dragged(dragFrame, corner: .topLeft, dx: -20, dy: 10, minimum: limits.minimum, maximum: limits.maximum)
      == NSRect(x: 80, y: 100, width: 620, height: 410), "top-left drag keeps the bottom right")
check(WindowFrame.dragged(dragFrame, corner: .bottomLeft, dx: 500, dy: 500, minimum: limits.minimum, maximum: limits.maximum)
      == NSRect(x: 280, y: 300, width: 420, height: 200), "drag stops at the minimum size, opposite corner fixed")
let resizedModel = PickerModel(search: search)
let resizedView = PickerView(model: resizedModel)
resizedModel.reset()
resizedView.setFrameSize(NSSize(width: 640, height: 420))
let rowsAtDefault = resizedModel.visibleRowCount
resizedView.setFrameSize(NSSize(width: 640, height: 220))
check(resizedModel.visibleRowCount < rowsAtDefault && resizedModel.visibleRowCount >= 3, "a smaller picker shows fewer rows")
check(render(resizedView).pixelsWide > 0, "small picker draws")
let sizeSuite = "simple-clipboard-picker-size-\(UUID().uuidString)"
let sizeDefaults = UserDefaults(suiteName: sizeSuite)!
let sizeStoreDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("picker-size-\(UUID().uuidString)")
let sizeStore = try! ClipStore(directory: sizeStoreDirectory)
let sizeMonitor = ClipboardMonitor(pasteboard: NSPasteboard(name: NSPasteboard.Name("picker-size-\(UUID().uuidString)")),
                                   store: sizeStore, settings: { Settings() })
let sizeController = PickerController(store: sizeStore, settingsStore: SettingsStore(defaults: sizeDefaults), monitor: sizeMonitor,
                                      defaults: sizeDefaults)
check(sizeController.savedSize == InterfaceStyle.pickerSize, "default picker size")
sizeController.saveSize(NSSize(width: 800, height: 600))
check(sizeController.savedSize == NSSize(width: 800, height: 600), "picker size is remembered")
sizeController.saveSize(NSSize(width: 10, height: 10))
check(sizeController.savedSize == InterfaceStyle.pickerSize, "a size below the minimum falls back to the default")
sizeDefaults.removePersistentDomain(forName: sizeSuite)

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
        for (name, keys) in [("list", [PickerKey]()), ("preview", [.down, .tab]), ("search", [.text("test")]), ("filters", [.enterFilter])] {
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
