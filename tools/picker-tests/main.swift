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
                lastCopiedAt: start.addingTimeInterval(TimeInterval(-id * 60)), copyCount: 1, sourceAppName: "Safari", contentPreview: preview)
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
check(model.handle(.escape) == .none && model.query.isEmpty, "escape clears the restored clip query")
check(model.handle(.escape) == .close, "next escape closes")
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
let expectedRows = min(view.settings.maximumVisibleItems, Int(floor(view.chrome.listRect.height / view.rowHeight(at: 0))))
check(viewModel.visibleRowCount == expectedRows && expectedRows == 8, "row count follows the list height (\(expectedRows))")
func render(_ view: NSView) -> NSBitmapImageRep {
    let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: bitmap)
    return bitmap
}
check(render(view).pixelsWide > 0, "picker draws")
let secondRow = NSPoint(x: 100, y: view.chrome.listRect.minY + view.rowHeight(at: 0) * 1.5)
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
check(view.barStatus.isEmpty, "empty query has no count or stats")
view.perform(.text("odd"))
check(view.barStatus == "15 matching \"odd\"", "bar shows matches and the typed text")
view.perform(.enterFilter)
check(view.barStatus.isEmpty, "filter step shows the filter count")
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
check(sizeController.savedSize == NSSize(width: 460, height: 10_000), "default width and uncapped saved height")
sizeController.saveSize(NSSize(width: 800, height: 600))
check(sizeController.savedSize == NSSize(width: 800, height: 600), "picker size is remembered")
sizeController.saveSize(NSSize(width: 10, height: 10))
check(sizeController.savedSize == NSSize(width: 800, height: 600), "invalid size does not overwrite saved cap")
sizeDefaults.removePersistentDomain(forName: sizeSuite)

// MARK: integrated typography and selected-row contrast
check(InterfaceStyle.font == NSFont.systemFont(ofSize: 13, weight: .regular)
    && InterfaceStyle.smallFont == NSFont.systemFont(ofSize: 11, weight: .regular), "shared typography uses system fonts")
func luminance(_ color: NSColor) -> Double {
    let rgb = color.usingColorSpace(.sRGB)!
    func linear(_ value: CGFloat) -> Double {
        let value = Double(value)
        return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
}
for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
    NSAppearance(named: appearanceName)!.performAsCurrentDrawingAppearance {
        let foreground = luminance(PickerView.rowForeground(selected: true))
        let background = luminance(.selectedContentBackgroundColor)
        let contrast = (max(foreground, background) + 0.05) / (min(foreground, background) + 0.05)
        print("Selected production foreground contrast in \(appearanceName.rawValue): \(contrast):1")
        check(contrast >= 4.5, "selected 13pt row text meets 4.5:1 contrast in \(appearanceName.rawValue): \(contrast)")

        // Exercise the production renderer, including symbols and the filter step, at readable 2x.
        let renderedModel = PickerModel(search: { _, _ in [clip(901, "Selected production text")] })
        let renderedView = PickerView(model: renderedModel)
        renderedView.appearance = NSAppearance(named: appearanceName)
        renderedView.settings.showTimestamps = true
        renderedView.now = { start }
        renderedModel.reset()
        renderedView.setFrameSize(NSSize(width: 560, height: 300))
        renderedView.layout()
        func bitmap() -> NSBitmapImageRep {
            let result = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1120, pixelsHigh: 600,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            result.size = renderedView.bounds.size
            renderedView.cacheDisplay(in: renderedView.bounds, to: result)
            return result
        }
        func assertForeground(_ image: NSBitmapImageRep, in region: NSRect, label: String) {
            let expected = PickerView.rowForeground(selected: true).usingColorSpace(.sRGB)!
            var matchingPixels = 0
            var bestContrast = 0.0
            for y in Int(region.minY * 2)..<Int(region.maxY * 2) {
                for x in Int(region.minX * 2)..<Int(region.maxX * 2) {
                    let pixel = image.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                    let difference = max(abs(pixel.redComponent - expected.redComponent),
                        abs(pixel.greenComponent - expected.greenComponent), abs(pixel.blueComponent - expected.blueComponent))
                    if difference < 0.06 {
                        matchingPixels += 1
                        let value = luminance(pixel)
                        bestContrast = max(bestContrast, (max(value, background) + 0.05) / (min(value, background) + 0.05))
                    }
                }
            }
            print("Rendered \(appearanceName.rawValue) \(label): \(matchingPixels) foreground pixels, \(bestContrast):1 contrast")
            check(matchingPixels >= 3 && bestContrast >= 4.5,
                "rendered selected \(label) uses contrasting production foreground in \(appearanceName.rawValue)")
        }
        let row = renderedView.visibleRows.first!.rect
        let image = bitmap()
        assertForeground(image, in: NSRect(x: 8, y: row.minY, width: 10, height: row.height), label: "number")
        assertForeground(image, in: NSRect(x: 26, y: row.midY - 7, width: 14, height: 14), label: "symbol")
        assertForeground(image, in: NSRect(x: 48, y: row.minY, width: 180, height: row.height), label: "clip text")
        assertForeground(image, in: NSRect(x: 400, y: row.minY, width: 152, height: row.height), label: "timestamp")
        renderedView.perform(.enterFilter)
        let filterRow = renderedView.visibleRows.first { $0.index == renderedModel.selectedFilterIndex }!.rect
        let filterImage = bitmap()
        assertForeground(filterImage, in: NSRect(x: 16, y: filterRow.minY, width: 140, height: filterRow.height), label: "filter name")
        assertForeground(filterImage, in: NSRect(x: 280, y: filterRow.minY, width: 272, height: filterRow.height), label: "filter summary")
    }
}

// MARK: redesign regressions: real lines, independent geometry, viewport and accessibility
var multiline = clip(101, "flattened title must not render")
multiline.contentPreview = "first\n\nthird\nfourth\nfifth"
var imageSummary = clip(102, "Image · 640 × 480")
imageSummary.kind = "image"
imageSummary.contentPreview = ""
let geometryModel = PickerModel(search: { query, _ in query == "none" ? [] : [multiline, imageSummary, clip(103, "last")] })
let geometryView = PickerView(model: geometryModel)
geometryModel.reset()
for lines in Settings.pickerContentLineChoices {
    geometryView.settings.pickerContentLines = lines
    check(geometryView.contentLines(for: multiline) == Array(["first", "", "third", "fourth", "fifth"].prefix(lines)),
          "\(lines)-line setting displays actual consecutive content lines")
    check(geometryView.rowHeight(at: 0) == CGFloat(lines) * InterfaceStyle.lineHeight + 8,
          "\(lines)-line setting has matching row geometry")
}
geometryView.settings.pickerContentLines = 3
check(geometryView.contentLines(for: multiline) == ["first", "", "third"], "content lines preserve consecutive blank lines, not summary title")
check(geometryView.contentLines(for: imageSummary) == [imageSummary.preview], "nontext is one metadata row")
let threeLineHeight = geometryView.rowHeight(at: 0)
let singleLineHeight = geometryView.rowHeight(at: 1)
check(threeLineHeight - singleLineHeight == InterfaceStyle.lineHeight * 2, "variable height follows actual lines")
geometryView.settings.pickerDensity = 10
check(geometryView.rowHeight(at: 0) == threeLineHeight + 12, "density changes padding independently of lines")
geometryView.settings.pickerDensity = 4
geometryView.setFrameSize(NSSize(width: 460, height: threeLineHeight + singleLineHeight + geometryView.chrome.barHeight + InterfaceStyle.gap))
check(geometryView.visibleRows.count == 2, "mixed-height viewport fits two complete rows")
check(geometryView.rowIndex(at: NSPoint(x: 100, y: geometryView.chrome.listRect.minY + threeLineHeight + 1)) == 1, "variable-row hit testing uses actual boundaries")
geometryView.perform(.pageDown)
check(geometryModel.selectedClip?.id == 103 && geometryView.visibleRows.contains { $0.index == 2 }, "page navigation keeps variable-height selection visible")
geometryView.perform(.home)
let accessibleRows = geometryView.accessibilityChildren() as! [NSAccessibilityElement]
check(accessibleRows.first?.accessibilityLabel()?.contains("first\n\nthird") == true, "accessible row describes displayed content")
check(accessibleRows.first?.isAccessibilitySelected() == true, "accessible row exposes selection")
var accessibleActions: [PickerAction] = []
geometryView.onAction = { accessibleActions.append($0) }
check(accessibleRows.first?.accessibilityPerformPress() == true && accessibleActions == [.recall(101, .original)], "accessible press recalls the correct row")
geometryView.settings.showPasteSpecial = false
geometryView.perform(.enterAlternate)
check(accessibleActions.count == 1 && !geometryView.barHints.contains("⇧↩"), "Paste Special off disables alternate route and hint")
geometryView.perform(.enterFilter)
check(geometryModel.step == .filters(clipID: 101), "Paste Special off preserves actual text filters")
geometryView.perform(.escape)
geometryView.perform(.text("none"))
let emptyHeight = geometryView.desiredHeight(cap: 600, screenHeight: 800)
check(emptyHeight < 100, "empty results shrink to compact empty state")
geometryView.perform(.escape)
check(geometryModel.query.isEmpty && geometryView.desiredHeight(cap: 600, screenHeight: 800) > emptyHeight, "Esc query-clear restores content-driven height")
check(geometryView.desiredHeight(cap: 100, screenHeight: 800) == 100, "manual height is a cap")
check(geometryView.desiredHeight(cap: 600, screenHeight: 110) == 110, "display height caps content")
geometryModel.select(1)
geometryView.perform(.text("x"))
check(geometryModel.selectedClip?.id == 102, "filtering preserves selected clip identity when still present")
geometryModel.reset()
check(geometryModel.selectedClip?.id == 101, "reopen resets to newest rather than preserving prior selection")
geometryView.settings.pickerContentLines = 5
geometryView.perform(.tab)
let previewHeight = geometryView.desiredHeight(cap: 80, screenHeight: 800)
geometryView.setFrameSize(NSSize(width: 360, height: previewHeight))
check(geometryView.visibleRows.contains { $0.index == 0 }, "five-line row remains visible in preview even with a tiny saved height cap")
geometryView.perform(.escape)
geometryView.setFrameSize(NSSize(width: 360, height: geometryView.desiredHeight(cap: 80, screenHeight: 800)))
check(geometryView.visibleRows.contains { $0.index == 0 }, "minimum viable height prevents clipping all rows after resize")
sizeDefaults.removePersistentDomain(forName: sizeSuite)
let presetStore = SettingsStore(defaults: sizeDefaults)
let presetController = PickerController(store: sizeStore, settingsStore: presetStore, monitor: sizeMonitor, defaults: sizeDefaults)
presetController.saveSize(NSSize(width: 513, height: 300))
check(presetController.savedSize == NSSize(width: 513, height: 300), "arbitrary manual width persists separately from presets")
presetStore.update { $0.pickerWidth = 360 }
check(presetController.savedSize == NSSize(width: 360, height: 300), "new width preset overrides manual width without losing height cap")
sizeDefaults.removePersistentDomain(forName: sizeSuite)

// MARK: controller + real offscreen panel resize sequences (no ordering front or clipboard recall)
// Native edge drags are represented by the actual delegate lifecycle around an NSWindow frame change.
// Corner and wheel paths below deliver synthetic NSEvents directly to production view methods.
func nativeResize(_ controller: PickerController, width: CGFloat, height: CGFloat) {
    let window = controller.view.window!
    window.delegate?.windowWillStartLiveResize?(Notification(name: NSWindow.willStartLiveResizeNotification, object: window))
    var frame = window.frame
    frame.origin.y = frame.maxY - height
    frame.size = NSSize(width: width, height: height)
    window.setFrame(frame, display: true)
    window.delegate?.windowDidEndLiveResize?(Notification(name: NSWindow.didEndLiveResizeNotification, object: window))
}
func cornerResize(_ controller: PickerController, dx: CGFloat, dy: CGFloat) {
    let window = controller.view.window!
    let corner = window.contentView!.subviews.compactMap { $0 as? WindowCornerView }.first { $0.corner == .bottomRight }!
    let start = NSPoint(x: window.frame.maxX - 5, y: window.frame.minY + 5)
    func event(_ type: NSEvent.EventType, at point: NSPoint) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: window.convertPoint(fromScreen: point), modifierFlags: [], timestamp: 0,
                          windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }
    corner.mouseDown(with: event(.leftMouseDown, at: start))
    let end = NSPoint(x: start.x + dx, y: start.y + dy)
    corner.mouseDragged(with: event(.leftMouseDragged, at: end))
    corner.mouseUp(with: event(.leftMouseUp, at: end))
}
func wheel(_ view: PickerView, down: Bool) {
    let cgEvent = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1,
                          wheel1: down ? -100 : 100, wheel2: 0, wheel3: 0)!
    view.scrollWheel(with: NSEvent(cgEvent: cgEvent)!)
}
var syntheticScreen = NSRect(x: 100, y: 50, width: 1440, height: 900)
let sequenceSettings = SettingsStore(defaults: sizeDefaults)
let sequenceModel = PickerModel(search: search)
let sequenceController = PickerController(store: sizeStore, settingsStore: sequenceSettings, monitor: sizeMonitor,
    defaults: sizeDefaults, model: sequenceModel, screenFrame: { syntheticScreen })
sequenceController.saveSize(NSSize(width: 640, height: 600))
sequenceController.prepareToOpen()
let sequenceWindow = sequenceController.view.window!
let expandedHeight = sequenceWindow.frame.height
sequenceController.view.perform(.text("clip 30"))
let compactHeight = sequenceWindow.frame.height
check(compactHeight < 80 && compactHeight == sequenceWindow.minSize.height, "controller produces and permits a compact one-row window below 80pt")
nativeResize(sequenceController, width: 720, height: compactHeight)
check(sequenceController.savedSize == NSSize(width: 720, height: 600), "native horizontal resize of filtered compact window saves width without shrinking height cap")
sequenceController.view.perform(.escape)
check(sequenceWindow.frame.height == expandedHeight, "query clear restores expanded height after native horizontal resize")
sequenceController.view.perform(.text("clip 30"))
cornerResize(sequenceController, dx: 40, dy: 0)
check(sequenceController.savedSize == NSSize(width: 760, height: 600), "synthetic corner mouse drag widens compact window and retains height cap")
sequenceController.view.perform(.escape)
check(sequenceWindow.frame.height == expandedHeight, "query clear restores expanded height after corner horizontal resize")
sequenceController.view.perform(.text("clip 30"))
cornerResize(sequenceController, dx: 0, dy: -120)
let cornerCap = compactHeight + 120
check(sequenceController.savedSize == NSSize(width: 760, height: cornerCap), "synthetic vertical corner drag changes height cap without losing manual width")
check(sequenceWindow.frame.height == compactHeight, "content remains compact even after saving a taller cap")
sequenceController.view.perform(.escape)
check(sequenceWindow.frame.height == cornerCap, "clearing restores actual corner-set height cap")
nativeResize(sequenceController, width: 760, height: 160)
check(sequenceController.savedSize == NSSize(width: 760, height: 160), "native vertical resize saves height independently")
sequenceController.view.perform(.text("no matches"))
check(sequenceWindow.frame.height < 80, "empty controller results also use a compact window")
nativeResize(sequenceController, width: 800, height: sequenceWindow.frame.height)
check(sequenceController.savedSize == NSSize(width: 800, height: 160), "empty-result horizontal resize preserves prior cap")
sequenceController.view.perform(.escape)
check(sequenceWindow.frame.height == 160, "Esc from empty results restores saved cap")
sequenceController.saveSize(NSSize(width: 810, height: 10))
check(sequenceController.savedSize == NSSize(width: 810, height: 160), "invalid height never discards independently valid width")
sequenceController.saveSize(NSSize(width: 10, height: compactHeight))
check(sequenceController.savedSize == NSSize(width: 810, height: compactHeight), "valid compact height saves independently of invalid width")
sequenceSettings.update { $0.showTimestamps.toggle() }
check(sequenceController.savedSize == NSSize(width: 810, height: compactHeight), "unrelated settings update preserves custom dimensions")
sequenceController.prepareToOpen()
check(sequenceWindow.frame.height == compactHeight && sequenceWindow.frame.width == 810, "reopen reads compact cap and arbitrary manual width")

// Every content resize rechecks the display, including position; clamping never rewrites saved dimensions.
sequenceController.saveSize(NSSize(width: 1100, height: 600))
syntheticScreen = NSRect(x: -600, y: 100, width: 520, height: 220)
sequenceController.prepareToOpen()
let insetScreen = syntheticScreen.insetBy(dx: 20, dy: 20)
check(insetScreen.contains(sequenceWindow.frame), "opening on small display clamps width and height")
for key in [PickerKey.text("clip 30"), .escape, .tab, .escape, .down] {
    sequenceWindow.setFrameOrigin(NSPoint(x: -2000, y: 2000))
    sequenceController.view.perform(key)
    check(insetScreen.contains(sequenceWindow.frame), "content update \(key) constrains size AND position to small display")
    check(sequenceWindow.minSize.width <= insetScreen.width && sequenceWindow.minSize.height <= insetScreen.height,
          "content-driven native minimum remains compatible with display bounds")
}
check(sequenceController.savedSize == NSSize(width: 1100, height: 600), "screen clamps do not replace saved manual dimensions")
sequenceController.view.perform(.text("clip 30"))
nativeResize(sequenceController, width: sequenceWindow.frame.width, height: 100)
check(sequenceController.savedSize == NSSize(width: 1100, height: 100), "vertical-only resize on narrow display retains unclamped saved width")
syntheticScreen = NSRect(x: 0, y: 0, width: 1440, height: 900)
sequenceController.prepareToOpen()
check(sequenceWindow.frame.width == 1100, "returning to a large display restores original manual width")

// Production wheel path must stop at the final fitting page rather than the final row.
sequenceController.saveSize(NSSize(width: 640, height: 600))
sequenceController.prepareToOpen()
wheel(sequenceController.view, down: true)
check(sequenceModel.firstRow == 22 && sequenceController.view.visibleRows.count == 8,
      "synthetic wheel stops at a full eight-item final page")
wheel(sequenceController.view, down: false)
check(sequenceModel.firstRow == 0, "synthetic wheel clamps at first page")
var variableRows = (0..<12).map { clip(Int64(200 + $0), "row \($0)") }
for index in variableRows.indices where index % 3 == 0 { variableRows[index].contentPreview = "one\ntwo\nthree\nfour\nfive" }
let variableModel = PickerModel(search: { _, _ in variableRows })
let variableController = PickerController(store: sizeStore, settingsStore: sequenceSettings, monitor: sizeMonitor,
    defaults: sizeDefaults, model: variableModel, screenFrame: { syntheticScreen })
sequenceSettings.update { $0.pickerContentLines = 5; $0.maximumVisibleItems = 5 }
variableController.saveSize(NSSize(width: 640, height: 230))
variableController.prepareToOpen()
wheel(variableController.view, down: true)
let finalRows = variableController.view.visibleRows
check(finalRows.last?.index == variableRows.count - 1 && finalRows.count > 1, "variable-height wheel final page includes the last clip without an empty trailing page")
let finalFirst = variableModel.firstRow
let usedHeight = finalRows.reduce(CGFloat(0)) { $0 + $1.rect.height }
check(finalRows.count == 5 || usedHeight + variableController.view.rowHeight(at: finalFirst - 1) > variableController.view.chrome.listRect.height,
      "variable-height final page fills available pixels or the item cap")
wheel(variableController.view, down: true)
check(variableModel.firstRow == finalFirst, "repeated wheel-down cannot overscroll variable-height final page")
variableController.view.perform(.enterFilter)
wheel(variableController.view, down: true)
check(variableController.view.visibleRows.last?.index == variableModel.filterRows.count - 1,
      "production wheel also clamps filter rows to their final fitting page")

// Legacy widths remain valid settings; a legacy height is independent, not grounds to reset the width.
for legacyWidth in [280, 640, 1200] {
    for legacyHeight in [0, Int(compactHeight), 300] {
        sizeDefaults.removePersistentDomain(forName: sizeSuite)
        sizeDefaults.set(legacyWidth, forKey: "pickerWidth")
        if legacyHeight > 0 { sizeDefaults.set(legacyHeight, forKey: "pickerHeight") }
        let legacySettings = SettingsStore(defaults: sizeDefaults)
        let legacyController = PickerController(store: sizeStore, settingsStore: legacySettings, monitor: sizeMonitor,
            defaults: sizeDefaults, model: PickerModel(search: search), screenFrame: { syntheticScreen })
        let expected = NSSize(width: legacyWidth, height: legacyHeight > 0 ? legacyHeight : 10_000)
        check(legacyController.savedSize == expected, "legacy width \(legacyWidth) / height \(legacyHeight) combination is retained")
        legacySettings.update { $0.showTypeIcons.toggle() }
        check(legacyController.savedSize == expected && SettingsStore(defaults: sizeDefaults).settings.pickerWidth == legacyWidth,
              "unrelated settings update preserves legacy width \(legacyWidth) / height \(legacyHeight)")
        legacyController.prepareToOpen()
        check(legacyController.view.window!.frame.width == CGFloat(legacyWidth), "production reopen retains legacy manual width \(legacyWidth)")
    }
}
sizeDefaults.removePersistentDomain(forName: sizeSuite)
try? FileManager.default.removeItem(at: sizeStoreDirectory)

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
if let directory = ProcessInfo.processInfo.environment["PICKER_SNAPSHOT_DIRECTORY"] {
    // Synthetic only: screenshot generation must never expose clipboard history.
    try! FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    let fixtures = [
        clip(201, "Design review notes\nKeep the menu bar simple."),
        clip(202, "https://developer.apple.com/documentation/appkit"),
        clip(203, "Meeting agenda\nReview keyboard shortcuts\nConfirm release checklist"),
        clip(204, "swift build -c release --product SimpleClipboard"),
        clip(205, "Thanks for the update. I will review the changes today."),
        clip(206, "Shopping list\nCoffee\nBread\nApples"),
        clip(207, "# Release checklist\nRun tests\nReview settings\nVerify paste"),
        clip(208, "A small clipboard history, one shortcut away.")
    ]
    let snapshotModel = PickerModel(search: { query, limit in
        Array(fixtures.filter { query.isEmpty || $0.contentPreview.localizedCaseInsensitiveContains(query) }.prefix(limit))
    })
    let snapshotView = PickerView(model: snapshotModel)
    snapshotView.now = { start }
    snapshotView.setFrameSize(NSSize(width: 460, height: snapshotView.desiredHeight(cap: 600, screenHeight: 800)))
    snapshotView.loadItems = { id in
        let content = fixtures.first { $0.id == id }?.contentPreview ?? ""
        return [[Representation(type: NSPasteboard.PasteboardType.string.rawValue, data: Data(content.utf8))]]
    }
    for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
        snapshotView.appearance = NSAppearance(named: appearanceName)
        snapshotView.settings = Settings()
        snapshotModel.reset()
        snapshotView.setFrameSize(NSSize(width: 460, height: snapshotView.desiredHeight(cap: 600, screenHeight: 800)))
        snapshotView.layout()
        if appearanceName == .aqua {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(snapshotView.bounds.width * 2),
                pixelsHigh: Int(snapshotView.bounds.height * 2), bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            bitmap.size = snapshotView.bounds.size
            snapshotView.cacheDisplay(in: snapshotView.bounds, to: bitmap)
            check(bitmap.pixelsWide == Int(snapshotView.bounds.width * 2), "README picker snapshot renders at 2x")
            try! bitmap.representation(using: .png, properties: [:])!.write(
                to: URL(fileURLWithPath: directory).appendingPathComponent("picker.png"))
        }
        for (name, keys) in [("list", [PickerKey]()), ("preview", [.down, .tab]), ("search", [.text("test")]), ("filters", [.enterFilter])] {
            snapshotModel.reset()
            keys.forEach { snapshotView.perform($0) }
            snapshotView.setFrameSize(NSSize(width: 460, height: snapshotView.desiredHeight(cap: 600, screenHeight: 800)))
            let bitmap = render(snapshotView)
            let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name)-\(appearanceName.rawValue).png")
            try! bitmap.representation(using: .png, properties: [:])!.write(to: url)
        }
        for lines in Settings.pickerContentLineChoices {
            snapshotModel.reset()
            snapshotView.settings.pickerContentLines = lines
            snapshotView.settings.pickerDensity = 10
            snapshotView.settings.showTypeIcons = true
            snapshotView.settings.showTimestamps = true
            snapshotView.setFrameSize(NSSize(width: 360, height: snapshotView.desiredHeight(cap: 600, screenHeight: 350)))
            let bitmap = render(snapshotView)
            let url = URL(fileURLWithPath: directory).appendingPathComponent("lines-\(lines)-\(appearanceName.rawValue).png")
            try! bitmap.representation(using: .png, properties: [:])!.write(to: url)
        }
    }
}

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
