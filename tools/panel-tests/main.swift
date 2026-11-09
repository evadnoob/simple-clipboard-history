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
let activityHour = Int64(floor(now.timeIntervalSince1970 / 3600))

let view = SettingsPanelView()
var actions = SettingsPanelActions()
func content() -> SettingsPanelContent {
    SettingsPanelContent(settings: settings, statistics: statistics, clipboardLine: "text, 1.2 KB from Firefox",
                         frontmostApp: (identifier: "net.kovidgoyal.kitty", name: "kitty"), notices: [],
                         appNames: ["com.1password.1password": "1Password"], hotkeyLabel: "\u{21E7}\u{2318}V", now: now,
                         copyActivity: [(hour: activityHour, copies: 3)])
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
func integerField(_ name: String) -> PanelIntegerField? { view.control(named: name) as? PanelIntegerField }
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
check(view.preferredHeight > 300 && view.preferredHeight < 760, "height is reasonable (\(view.preferredHeight))")
check(view.controls.map(\.partName) == ["pause", "login", "ignoreFrontmost", "paste", "plainText", "pasteSpecial",
    "keep", "largest", "historySize", "pickerWidth", "contentLines", "density",
    "visibleItems", "typeIcons", "timestamps", "clearHistory", "export", "import", "settings", "openPicker", "quit"], "panel controls follow settings sections and footer actions")
check(view.controls.allSatisfy { view.bounds.contains($0.convert($0.bounds, to: view)) }, "every control inside the panel")
for (index, control) in view.controls.enumerated() {
    for other in view.controls[(index + 1)...] where control.convert(control.bounds, to: view).intersects(other.convert(other.bounds, to: view)) {
        check(false, "\(control.partName) overlaps \(other.partName)")
    }
}
check(checkbox("paste")?.isOn == true && choices("plainText")?.selectedIndex == 0 && checkbox("pause")?.isOn == true, "checkbox states")
check(choices("hotkey") == nil, "shortcut editing is deferred from the panel")
check(choices("plainText")?.titles == ["Preserve original formatting", "Paste as plain text"], "exact paste representation labels")
check(!view.controls.contains { $0.partName == "retention" }, "legacy retention setting is not shown")
check(NSImage(systemSymbolName: "clipboard", accessibilityDescription: nil) != nil, "empty clipboard outline symbol is available")
check(NSImage(systemSymbolName: "checkmark.square.fill", accessibilityDescription: nil) != nil, "Active uses a square status symbol")
check(integerField("keep")?.field.stringValue == "1000", "maximum items freeform input starts at saved value")
let numericControl = integerField("keep")!
for invalid in ["", "0", "-1", "1.5", "9223372036854775808"] {
    numericControl.field.stringValue = invalid
    numericControl.commit()
    check(settings.historyLimit == 1000 && numericControl.field.stringValue == "1000", "invalid maximum items rejected: \\(invalid)")
}
check(numericControl.field.frame.width > 0 && numericControl.field.frame.height >= 20,
      "native numeric editor has usable geometry")
let plainTextControl = choices("plainText")!
check(plainTextControl.frame.minX > 0 && plainTextControl.frame.maxX <= view.bounds.width,
      "long paste dropdown stays within the panel width")
check(choices("largest")?.titles == ["5", "20", "50", "100"] && choices("largest")?.selectedIndex == 1, "largest clip choices")
check(button("openPicker")?.title == "Open Picker  \u{21E7}\u{2318}V", "open picker shows the hotkey")
check(button("ignoreFrontmost")?.title == "+ Ignore kitty", "ignore the frontmost app")
check(render().pixelsWide > 0, "panel draws")
let panelDocument = view.scrollView.documentView!
let shortcutHint = panelDocument.subviews.compactMap { $0 as? NSTextField }
    .first { $0.accessibilityIdentifier() == "pickerShortcutHint" }
check(shortcutHint?.stringValue == "\u{21E7}\u{2318}V" && shortcutHint?.alignment == .right
    && shortcutHint!.frame.maxX <= SettingsPanelView.width - 16
    && checkbox("pause")!.frame.maxX <= shortcutHint!.frame.minX - 8,
      "History row displays the current picker shortcut as a right-aligned inset hint with a clear gap")
let rowLabels = panelDocument.subviews.compactMap { $0 as? NSTextField }
check(rowLabels.contains { $0.frame.minX == 16 && ($0.stringValue.contains("Default paste") || $0.stringValue == "Ignored apps") },
      "setting labels share the 16-point content inset")
let titleLabel = panelDocument.subviews.compactMap { $0.subviews.compactMap { $0 as? NSTextField } }.flatMap { $0 }
    .first { $0.accessibilityIdentifier() == "panelTitle" }
let headerIcon = panelDocument.subviews.compactMap(\.subviews).flatMap { $0 }.compactMap { $0 as? NSImageView }
    .first { $0.accessibilityLabel() == "Clipboard" }
check(titleLabel?.stringValue == "Simple Clipboard History" && titleLabel?.font?.fontDescriptor.symbolicTraits.contains(.bold) == true,
      "bold accessible panel title is present")
let header = panelDocument.subviews.first { $0.subviews.contains { ($0 as? NSTextField)?.accessibilityIdentifier() == "panelTitle" } }!
let titleSize = (titleLabel!.stringValue as NSString).size(withAttributes: [.font: titleLabel!.font!])
let titleInDocument = titleLabel!.convert(titleLabel!.bounds, to: panelDocument)
let iconInDocument = headerIcon!.convert(headerIcon!.bounds, to: panelDocument)
let chartInDocument = view.activityChart!.convert(view.activityChart!.bounds, to: panelDocument)
let titleDocumentRect = titleInDocument
let topRow = titleDocumentRect.union(iconInDocument).union(chartInDocument)
check(titleSize.width <= titleLabel!.frame.width && titleLabel!.frame.width >= 270,
      "16-point bold title intrinsic width fits its allocated field")
check(headerIcon?.image != nil && headerIcon?.imageScaling == .scaleAxesIndependently
    && headerIcon?.frame.size == NSSize(width: 24, height: 26) && !iconInDocument.intersects(titleDocumentRect)
    && !titleDocumentRect.intersects(chartInDocument) && header.isFlipped,
      "flipped header places icon, full title, and graph in a non-overlapping top row")
check(view.activityChart?.frame.width == 54 && view.activityChart?.frame.height == 17
    && view.activityChart?.days == 5 && view.activityChart!.frame.maxX < SettingsPanelView.width,
      "compact fixed five-day graph fits at the upper right")
let compactChart = CopyActivityChartView(days: 5, now: now, buckets: [(hour: activityHour, copies: 3)])
compactChart.frame = NSRect(x: 0, y: 0, width: 54, height: 17)
check(compactChart.isFlipped && compactChart.intervalRects.count == 6 && compactChart.renderedBarRects.count == 1
    && compactChart.renderedBarRects.allSatisfy { compactChart.bounds.contains($0) },
      "compact five-day graph aggregates 120 hours into six visible bars")
check(compactChart.intervalRects.allSatisfy { $0.width >= 7 && compactChart.bounds.contains($0) },
      "54-point chart has broad bars within bounds")
let actualSizeChart = CopyActivityChartView(days: 5, now: now, buckets: [(hour: activityHour, copies: 3)])
actualSizeChart.frame = NSRect(x: 0, y: 0, width: 54, height: 17)
check(actualSizeChart.renderedBarRects.count == 1 && actualSizeChart.renderedBarRects[0].height == 17
    && actualSizeChart.bounds.contains(actualSizeChart.renderedBarRects[0]),
      "17-point production graph shows an in-bounds observed bar")
let twentyHourCases = CopyActivityChartView(days: 5, now: now, buckets: [
    (hour: activityHour - 119, copies: 4), (hour: activityHour - 118, copies: 6),
    (hour: activityHour - 100, copies: 10),
    (hour: activityHour - 99, copies: 20),
    (hour: activityHour - 79, copies: 5), (hour: activityHour - 78, copies: 5),
    (hour: activityHour, copies: 7)
])
twentyHourCases.frame = NSRect(x: 0, y: 0, width: 54, height: 31)
let groupedRects = twentyHourCases.renderedBarRects
check(groupedRects.count == 4 && abs(groupedRects[0].height - 31) < 0.01
    && abs(groupedRects[1].height - 31) < 0.01
    && abs(groupedRects[2].height - 15.5) < 0.01
    && abs(groupedRects[3].height - 10.85) < 0.01
    && groupedRects.map(\.minX) == [0, 9, 18, 45]
    && groupedRects.allSatisfy { $0.maxY == twentyHourCases.bounds.height },
      "hourly sums form 20:20:10:7 bars, with neighboring group boundaries separate")
let excludedChart = CopyActivityChartView(days: 5, now: now, buckets: [
    (hour: activityHour - 120, copies: 9), (hour: activityHour, copies: 2),
    (hour: activityHour + 1, copies: Int.max)
])
excludedChart.frame = NSRect(x: 0, y: 0, width: 54, height: 31)
check(excludedChart.renderedBarRects.count == 1 && excludedChart.renderedBarRects[0].height == 31
    && excludedChart.renderedBarRects[0].minX == excludedChart.intervalRects[5].minX,
      "out-of-window and future counts cannot affect included activity or its scale")
for width: CGFloat in [54, 72, 96, 160] {
    let resized = CopyActivityChartView(days: 5, now: now, buckets: [(hour: activityHour, copies: 1)])
    resized.frame = NSRect(x: 0, y: 0, width: width, height: 31)
    check(resized.intervalRects.count == 6 && resized.intervalRects.allSatisfy {
        $0.width >= 7 && $0.minX >= 0 && $0.maxX <= width
    } && resized.renderedBarRects.allSatisfy { resized.bounds.contains($0) },
          "20-hour bar geometry remains valid at width \\(Int(width))")
}
check(!compactChart.showsRangeCaptions && compactChart.renderedBarRects[0].height == compactChart.bounds.height,
      "compact chart omits colliding captions and uses full height for observed bars")
let compactBitmap = compactChart.bitmapImageRepForCachingDisplay(in: compactChart.bounds)!
compactChart.cacheDisplay(in: compactChart.bounds, to: compactBitmap)
let compactBluePixels = (0..<compactBitmap.pixelsHigh).contains { y in
    (max(0, compactBitmap.pixelsWide - 3)..<compactBitmap.pixelsWide).contains { x in
        guard let color = compactBitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
        return color.blueComponent > color.redComponent + 0.1
    }
}
check(compactBitmap.pixelsWide > 0 && compactBluePixels,
      "compact current-hour graph paints an observed blue bar at the actual header size")
let compactEmpty = CopyActivityChartView(days: 5, now: now, buckets: [])
compactEmpty.frame = NSRect(x: 0, y: 0, width: 54, height: 31)
let compactEmptyBitmap = compactEmpty.bitmapImageRepForCachingDisplay(in: compactEmpty.bounds)!
compactEmpty.cacheDisplay(in: compactEmpty.bounds, to: compactEmptyBitmap)
let compactEmptyBlue = (0..<compactEmptyBitmap.pixelsHigh).contains { y in
    (max(0, compactEmptyBitmap.pixelsWide - 3)..<compactEmptyBitmap.pixelsWide).contains { x in
        guard let color = compactEmptyBitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
        return color.blueComponent > color.redComponent + 0.1
    }
}
check(!compactEmptyBlue && compactEmpty.renderedBarRects.isEmpty,
      "compact empty graph renders without fabricated blue bars")
let headerLabels = panelDocument.subviews.compactMap(\.subviews).flatMap { $0 }.compactMap { $0 as? NSTextField }
check(headerLabels.filter { $0.accessibilityIdentifier().hasPrefix("headerStat:") }.count == 3,
      "header exposes three distinct accessible statistic groups")
let statLabels = headerLabels.filter { $0.accessibilityIdentifier().hasPrefix("headerStat:") }
let statRects = statLabels.map { $0.convert($0.bounds, to: panelDocument) }
let dividerRects = header.subviews.filter { $0.frame.width == 1 && $0.frame.height == 18 }.map {
    $0.convert($0.bounds, to: panelDocument)
}
check(statRects.allSatisfy { topRow.maxY <= $0.minY && $0.minX >= 8 && $0.maxX <= SettingsPanelView.width - 8 }
    && statRects.allSatisfy { rect in
        guard let label = statLabels.first(where: { $0.convert($0.bounds, to: panelDocument) == rect }), let font = label.font else { return false }
        return (label.stringValue as NSString).size(withAttributes: [.font: font]).width <= label.frame.width
    }, "stat row is below title/chart and every label fits its actual font frame")
check(dividerRects.count == 2 && dividerRects.allSatisfy { divider in statRects.allSatisfy { !$0.intersects(divider) } }
    && statRects[1].maxX < dividerRects[1].minX && dividerRects[1].maxX < statRects[2].minX,
      "both vertical separators have gaps and do not overlap adjacent statistic text")
check(headerLabels.contains { $0.stringValue == "Active" } && headerLabels.contains { $0.stringValue.contains("142 items") }
    && headerLabels.contains { $0.stringValue.contains("/") && $0.stringValue.contains("%") },
      "header groups show active state, count, and used/max percentage")
let headerDividers = panelDocument.subviews.compactMap(\.subviews).flatMap { $0 }.filter {
    $0.frame.width == 1 && $0.frame.height == 18 && $0.wantsLayer
}
check(headerDividers.count >= 2, "header statistic groups have vertical dividers")
check(!view.controls.contains { $0.partName == "copyActivityDays" }
    && !panelDocument.subviews.contains { ($0 as? NSTextField)?.stringValue.hasPrefix("Clipboard:") == true },
      "no activity range selector or clipboard status row")
check(view.activityChart?.days == 5 && view.activityChart?.buckets.first?.hour == activityHour
      && view.activityChart?.buckets.first?.copies == 3, "production activity chart receives stored hourly data with fixed range")
var zeroStatsContent = content()
zeroStatsContent.statistics = StoreStatistics(clipCount: 0, clipBytes: 0, diskBytes: 0, oldestCopiedAt: nil, latest: nil)
view.show(zeroStatsContent)
let zeroStatLabels = (view.scrollView.documentView!.subviews.compactMap(\.subviews).flatMap { $0 }).compactMap { $0 as? NSTextField }
check(zeroStatLabels.contains { $0.stringValue == "0 items" } && zeroStatLabels.contains { $0.stringValue.contains("(0%)") },
      "empty history displays zero items and safe zero percentage")
var largeStatsContent = content()
largeStatsContent.statistics = StoreStatistics(clipCount: 12_345_678, clipBytes: 400_000_000, diskBytes: 0, oldestCopiedAt: nil, latest: nil)
view.show(largeStatsContent)
let largeLabels = view.scrollView.documentView!.subviews.compactMap(\.subviews).flatMap { $0 }.compactMap { $0 as? NSTextField }
check(largeLabels.contains { $0.stringValue == "12.3M items" }, "large valid history counts use a compact readable label")
let largeCount = largeLabels.first { $0.accessibilityIdentifier() == "headerStat:1" }!
check((largeCount.stringValue as NSString).size(withAttributes: [.font: largeCount.font!]).width <= largeCount.frame.width,
      "large count text fits its statistic group")
var unavailableStatsContent = content()
unavailableStatsContent.statistics = nil
view.show(unavailableStatsContent)
let unavailableStatLabels = view.scrollView.documentView!.subviews.compactMap(\.subviews).flatMap { $0 }.compactMap { $0 as? NSTextField }
check(unavailableStatLabels.contains { $0.stringValue == "Unavailable items" }
    && unavailableStatLabels.contains { $0.stringValue == "Unavailable" }, "unavailable statistics are explicit and safe")
var pausedStatsContent = content()
pausedStatsContent.settings.capturePaused = true
view.show(pausedStatsContent)
let pausedLabels = (view.scrollView.documentView!.subviews.compactMap(\.subviews).flatMap { $0 }).compactMap { $0 as? NSTextField }
check(pausedLabels.contains { $0.stringValue == "Paused" }, "paused capture remains meaningful in header")
view.show(content())
for days in Settings.copyActivityDayChoices {
    let chart = CopyActivityChartView(days: days, now: now, buckets: [])
    chart.frame = NSRect(x: 0, y: 0, width: SettingsPanelView.width - 16, height: 43)
    let slots = chart.intervalRects
    check(slots.count == (days * 24 + 19) / 20, "\(days)-day chart keeps one slot per 20-hour group")
    check(slots.allSatisfy { $0.minX.isFinite && $0.width.isFinite && $0.width >= 0
        && $0.minX >= 0 && $0.maxX <= chart.bounds.width }, "\(days)-day slot geometry stays finite and inside panel")
}
let currentHourChart = CopyActivityChartView(days: 10, now: now, buckets: [(hour: activityHour, copies: Int.max)])
currentHourChart.frame = NSRect(x: 0, y: 0, width: SettingsPanelView.width - 16, height: 43)
let currentBars = currentHourChart.renderedBarRects
check(currentBars.count == 1 && currentBars[0].maxX <= currentHourChart.bounds.width, "ten-day production geometry includes current activity in newest 20-hour group")
let currentBitmap = currentHourChart.bitmapImageRepForCachingDisplay(in: currentHourChart.bounds)!
currentHourChart.cacheDisplay(in: currentHourChart.bounds, to: currentBitmap)
let currentRect = currentBars[0]
let blueCurrentPixels = (0..<currentBitmap.pixelsHigh).contains { y in
    (max(0, currentBitmap.pixelsWide - 3)..<currentBitmap.pixelsWide).contains { x in
        guard let color = currentBitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
        return color.blueComponent > color.redComponent + 0.1
    }
}
check(blueCurrentPixels, "offscreen rendering paints populated current-hour bar blue")
check(currentBars.allSatisfy { $0.minX.isFinite && $0.minY.isFinite && $0.width.isFinite && $0.height.isFinite
    && currentHourChart.bounds.contains($0) }, "maximum aggregate count produces finite contained geometry")
let adversarialChart = CopyActivityChartView(days: Int.max, now: now,
    buckets: [(hour: activityHour - 1, copies: Int.min), (hour: activityHour, copies: Int.max)])
adversarialChart.frame = currentHourChart.frame
check(adversarialChart.intervalRects.count == 12 && adversarialChart.renderedBarRects.count == 1
    && adversarialChart.renderedBarRects.allSatisfy { $0.minX.isFinite && $0.minY.isFinite
        && $0.width.isFinite && $0.height.isFinite && adversarialChart.bounds.contains($0) },
      "extreme range and negative count do not overflow or draw invalid geometry")
let zeroWidthChart = CopyActivityChartView(days: 10, now: now, buckets: [(hour: activityHour, copies: 1)])
zeroWidthChart.frame = NSRect(x: 0, y: 0, width: 0, height: 64)
check(zeroWidthChart.intervalRects.isEmpty && zeroWidthChart.renderedBarRects.isEmpty,
      "zero-width drawing has no non-finite geometry")
let emptyHourChart = CopyActivityChartView(days: 10, now: now, buckets: [])
emptyHourChart.frame = currentHourChart.frame
check(emptyHourChart.renderedBarRects.isEmpty, "missing hourly activity is not fabricated")
let emptyBitmap = emptyHourChart.bitmapImageRepForCachingDisplay(in: emptyHourChart.bounds)!
emptyHourChart.cacheDisplay(in: emptyHourChart.bounds, to: emptyBitmap)
let emptyPixel = emptyBitmap.colorAt(x: Int(currentRect.midX), y: Int(currentRect.midY))?.usingColorSpace(.deviceRGB)
check(emptyPixel.map { $0.blueComponent > $0.redComponent } != true, "offscreen empty hour remains unpainted")
check(!view.controls.contains { $0.partName == "copyActivityDays" }, "fixed activity chart has no range selector")
check(view.activityChart?.days == 5 && view.activityChart?.frame.width == 54 && view.activityChart?.frame.height == 17, "production chart is compact fixed five-day header graph")
check(view.activityChart?.accessibilityLabel() == "Copy activity over the last 5 days, in 20-hour groups", "fixed five-day graph describes 20-hour groups for accessibility")
check(!view.scrollView.documentView!.subviews.contains { ($0 as? NSTextField)?.stringValue.hasPrefix("Clipboard:") == true }, "clipboard status line is absent")
let emptyChart = CopyActivityChartView(days: 5, now: now, buckets: [])
emptyChart.frame = NSRect(x: 0, y: 0, width: 440, height: 64)
emptyChart.draw(emptyChart.bounds)
check(emptyChart.buckets.isEmpty && emptyChart.days == 5, "empty activity remains empty in production chart")
let zeroChart = CopyActivityChartView(days: 3, now: now, buckets: [(hour: activityHour, copies: 0)])
zeroChart.frame = NSRect(x: 0, y: 0, width: 440, height: 64)
zeroChart.draw(zeroChart.bounds)
check(zeroChart.buckets.first?.copies == 0 && zeroChart.bounds.width.isFinite && zeroChart.bounds.height.isFinite,
      "zero activity draws through finite production chart geometry")
var refreshed = content()
refreshed.copyActivity = [(hour: activityHour - 1, copies: 0), (hour: activityHour, copies: 7)]
refreshed.settings.copyActivityDays = 10
view.show(refreshed)
check(view.activityChart?.days == 5 && view.activityChart?.buckets.map(\.copies) == [0, 7],
      "synthetic refresh replaces observed chart data while retaining fixed five-day range")
check(view.activityChart?.accessibilityLabel() == "Copy activity over the last 5 days, in 20-hour groups",
      "refreshed chart accessibility remains fixed five-day")
let longLabel = choices("plainText")!
check(longLabel.frame.width > 0 && longLabel.frame.maxX <= view.bounds.width && longLabel.popup.itemArray.count == 2,
      "long approved paste labels remain inside the production panel")
view.show(content())
let document = view.scrollView.documentView as! PanelSectionView
check(document.sectionHeaders.count == 4 && document.sectionHeaders.allSatisfy {
    $0.minX == 0 && $0.width == SettingsPanelView.width && $0.height == 20
}, "all four section strips span the full panel width")
let sectionLabels = document.subviews.compactMap { $0 as? NSTextField }
    .filter { $0.accessibilityIdentifier().hasPrefix("section:") }
check(sectionLabels.map(\.stringValue) == ["History", "Paste", "Limits", "Look and feel"], "strips label the four direct sections")
check(zip(sectionLabels, document.sectionHeaders).allSatisfy { $1.contains($0.frame) }, "section labels fit inside shaded strips")
let dropdowns = view.controls.compactMap { $0 as? PanelDropdown }
check(Set(dropdowns.map { $0.frame.minX }).count == 1 && Set(dropdowns.map { $0.frame.width }).count == 1,
      "native dropdowns share a compact value column")
check(dropdowns.allSatisfy { $0.frame.height == 24 && $0.popup.controlSize == .small && $0.popup.font == InterfaceStyle.controlFont },
      "native dropdown geometry and typography stay compact")
check(document.separators.isEmpty, "settings rows have no intra-section separators")
check(document.sectionHeaders.count == 4, "section boundary strips remain rendered")
check(dropdowns.allSatisfy { $0.frame.width > 0 && $0.frame.height == 24 }, "dropdown control borders retain production geometry")
check(checkbox("pause")?.button.cell is NSButtonCell && checkbox("pause")?.button.state == .on,
      "checkbox uses a native checked cell")
check(checkbox("pause")?.button.controlSize == .small && checkbox("pause")?.button.font == InterfaceStyle.controlFont,
      "native checkbox typography and size are compact")
check(button("clearHistory")?.symbolName == "trash" && button("openPicker")?.symbolName == "list.clipboard"
      && button("import")?.symbolName == "square.and.arrow.down" && button("export")?.symbolName == "square.and.arrow.up",
      "restrained action symbols use their actual meaning")
check(checkbox("pause")?.hitTest(NSPoint(x: checkbox("pause")!.frame.midX, y: checkbox("pause")!.frame.midY)) === checkbox("pause"),
      "native checkbox drawing leaves mouse handling with the panel control")
for appearance in [NSAppearance.Name.aqua, .darkAqua] {
    view.appearance = NSAppearance(named: appearance)
    let bitmap = render()
    let scale = CGFloat(bitmap.pixelsWide) / view.bounds.width
    func luminance(_ point: NSPoint) -> CGFloat {
        let color = bitmap.colorAt(x: Int(point.x * scale), y: Int(point.y * scale))!.usingColorSpace(.deviceRGB)!
        return (color.redComponent + color.greenComponent + color.blueComponent) / 3
    }
    let header = document.sectionHeaders[0]
    let headerTone = luminance(NSPoint(x: 4, y: header.midY))
    let bodyTone = luminance(NSPoint(x: 4, y: checkbox("pause")!.frame.midY))
    check(abs(headerTone - bodyTone) > 0.04, "section strip visibly differs from body in \(appearance.rawValue)")
}
view.appearance = nil
// MARK: checkboxes and choices apply at once
checkbox("paste")?.toggle()
check(settings.recallMode == .clipboard && checkbox("paste")?.isOn == false, "unchecking paste switches to clipboard")
choices("plainText")?.select(1)
check(settings.alwaysPastePlainText && choices("plainText")?.selectedIndex == 1, "always plain text")
checkbox("pause")?.toggle()
check(settings.capturePaused, "pause")
check(settings.pickerHotkey == .shiftCommandV, "stored picker shortcut is preserved")
choices("largest")?.select(3)
check(settings.maximumClipMegabytes == 100, "largest clip choice")
integerField("keep")?.onCommit?(Int.max)
check(settings.historyLimit == Int.max && view.confirmation == nil, "Int.max applies without allocating or loading clip rows")
integerField("keep")?.onCommit?(10_000)
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
integerField("keep")?.onCommit?(100)
check(view.confirmation == .keepHistory(limit: 100, deleting: 42) && settings.historyLimit == 10_000, "a smaller limit asks first")
check(button("confirmDelete")?.isFocused == true && button("openPicker") == nil, "confirmation replaces the buttons, delete focused")
check(render().pixelsWide > 0, "confirmation draws")
view.keyDown(with: key(53, "\u{1b}"))
check(view.confirmation == nil && settings.historyLimit == 10_000 && calls.isEmpty, "escape cancels")
integerField("keep")?.onCommit?(100)
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
check(view.focusedPart == "pause", "tab focuses first setting, not removed chart selector")
view.keyDown(with: key(48, "\t", .shift))
check(view.focusedPart == "quit", "shift-tab wraps to the last control")
for _ in 0..<3 { view.keyDown(with: key(48, "\t")) }
check(view.focusedPart != "hotkey", "shortcut hint is not an editable focus target")
check(settings.pickerHotkey == .shiftCommandV, "read-only panel hint preserves the configured picker shortcut")
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
check(StatusItemController.icon.isTemplate && StatusItemController.icon.size == NSSize(width: 16, height: 17.33), "menu bar icon is a broad template clipboard")
let renderedClipboard = ClipboardIcon.image(size: NSSize(width: 24, height: 26), accessibilityDescription: nil)
check(ClipboardIcon.aspectRatio == 24.0 / 26.0 && renderedClipboard.size == NSSize(width: 24, height: 26), "panel and menu icons share clipboard proportions")
check(abs(ClipboardIcon.strokeWidth(for: NSRect(x: 0, y: 0, width: 16, height: 17.33)) - 1.28) < 0.001
    && abs(ClipboardIcon.strokeWidth(for: NSRect(x: 0, y: 0, width: 24, height: 26)) - 1.92) < 0.001,
      "shared clipboard stroke is 1.28 points at menu size and 1.92 at panel size")
let clipboardPixels = NSBitmapImageRep(data: renderedClipboard.tiffRepresentation!)!
func ink(_ x: Int, _ y: Int) -> Bool { (clipboardPixels.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 }
check(ink(12, 2) && !ink(12, 12) && ink(3, 12), "offscreen clipboard has a top tab and open board interior")

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
        integerField("keep")?.onCommit?(100)
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
check(settings.copyActivityDays == 5 && view.activityChart?.days == 5, "saved range does not alter fixed production chart")
choices("visibleItems")?.select(3)
check(settings.maximumVisibleItems == 15 && settings.pickerDensity == 7, "visible cap binding")
checkbox("typeIcons")?.toggle()
checkbox("timestamps")?.toggle()
checkbox("pasteSpecial")?.toggle()
check(!settings.showTypeIcons && settings.showTimestamps && !settings.showPasteSpecial, "picker toggles bind")
choices("historySize")?.select(3)
choices("retention")?.select(0)
check(settings.maximumHistoryMegabytes == 1000 && !view.controls.contains { $0.partName == "retention" }, "history size binds and retention is hidden")
settings.capturePaused = false
view.show(content())
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
for name in ["import", "export", "settings"] {
    let control = button(name)!
    check(!control.isEnabled && control.title == name.capitalized,
        "\(name) action is disabled")
    if name == "import" || name == "export" {
        check(control.toolTip == "\(name.capitalized): Not implemented"
              && control.accessibilityLabel() == "\(name.capitalized), Not implemented",
              "\(name) exposes its unavailable state in tooltip and accessibility")
        check(InterfaceStyle.width(of: "Not implemented", font: .systemFont(ofSize: 9)) <= control.frame.width,
              "\(name) unavailable caption fits its footer group")
        check(view.subviews.contains { subview in
            subview.subviews.contains { ($0 as? NSTextField)?.stringValue == "Not implemented"
                && $0.frame.width >= 78 && $0.frame.height >= 16 }
        }, "\(name) has a visible unavailable caption")
    }
    var invoked = false
    control.onPress = { invoked = true }
    control.press()
    _ = control.handleKey(key(49, " "))
    check(!control.accessibilityPerformPress() && !invoked, "\(name) cannot activate by mouse/key/accessibility")
    check(control.accessibilityRole() == .button && control.isAccessibilityEnabled() == false, "\(name) accessibility disabled button")
}
check(checkbox("pause")?.accessibilityRole() == .checkBox, "custom checkbox accessibility role")
check(checkbox("pause")?.accessibilityLabel() == "Keep clipboard history", "checkbox accessible label")
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
var windowKeepHistoryCalls = 0
windowView.actions.keepHistory = { limit in
    windowKeepHistoryCalls += 1
    windowSettings.update { $0.historyLimit = limit }
    synthetic.settings = windowSettings.settings
    windowController.show(synthetic)
}
windowController.show(synthetic)
let realPanel = windowController.panel
let productionIntegerField = windowView.control(named: "keep") as! PanelIntegerField
check(realPanel.makeFirstResponder(productionIntegerField.field), "native maximum items field receives keyboard focus")
let editor = realPanel.fieldEditor(true, for: productionIntegerField.field) as! NSTextView
editor.string = "1234"
productionIntegerField.field.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
check(windowSettings.settings.historyLimit == 1234, "field editor Return commits entered maximum items")
windowSettings.update { $0.historyLimit = 1000 }
synthetic.settings = windowSettings.settings
windowController.show(synthetic)
windowView.resetInteraction()
while windowView.focusedPart != "keep" { windowView.moveFocus(by: 1) }
let tabField = windowView.control(named: "keep") as! PanelIntegerField
check(realPanel.fieldEditor(false, for: tabField.field) === realPanel.firstResponder, "Tab navigation gives native field-editor focus")
let tabEditor = realPanel.fieldEditor(false, for: tabField.field) as! NSTextView
tabEditor.selectAll(nil)
tabEditor.insertText("2000", replacementRange: NSRange(location: NSNotFound, length: 0))
tabEditor.doCommand(by: #selector(NSResponder.insertTab(_:)))
check(windowView.focusedPart != "keep" && windowSettings.settings.historyLimit == 2000,
      "Tab away commits native edit exactly once")
windowSettings.update { $0.historyLimit = 1000 }
synthetic.settings = windowSettings.settings
windowController.show(synthetic)
let refreshField = windowView.control(named: "keep") as! PanelIntegerField
check(realPanel.makeFirstResponder(refreshField.field), "rebuilt field can receive focus")
let refreshEditor = realPanel.fieldEditor(true, for: refreshField.field) as! NSTextView
refreshEditor.string = "4321"
refreshField.field.textDidChange(Notification(name: NSText.didChangeNotification, object: refreshEditor))
windowController.show(synthetic)
let refreshedFieldValue = (windowView.control(named: "keep") as? PanelIntegerField)?.field.stringValue ?? "nil"
check(refreshedFieldValue == "4321" && windowSettings.settings.historyLimit == 4321,
      "unrelated panel refresh commits native field-editor draft (field=\(refreshedFieldValue), saved=\(windowSettings.settings.historyLimit))")
var numericCommitCount = 0
windowSettings.onChange = { if $0.historyLimit == 9876 { numericCommitCount += 1 } }
let blurField = windowView.control(named: "keep") as! PanelIntegerField
var fieldCommitCount = 0
let originalBlurCommit = blurField.onCommit
blurField.onCommit = { value in fieldCommitCount += 1; originalBlurCommit?(value) }
check(realPanel.makeFirstResponder(blurField.field), "field supports mouse-focus editing")
let blurEditor = realPanel.fieldEditor(true, for: blurField.field) as! NSTextView
blurEditor.selectAll(nil)
blurEditor.insertText("9876", replacementRange: NSRange(location: NSNotFound, length: 0))
blurField.field.textDidChange(Notification(name: NSText.didChangeNotification, object: blurEditor))
check(realPanel.makeFirstResponder(windowView), "moving focus away ends native field editing")
check(windowSettings.settings.historyLimit == 9876 && numericCommitCount == 1 && fieldCommitCount == 1,
      "blur commits native field callback and setting exactly once")
windowSettings.onChange = nil
windowSettings.update { $0.historyLimit = 1000 }
synthetic.settings = windowSettings.settings
windowController.show(synthetic)
let pendingField = windowView.control(named: "keep") as! PanelIntegerField
check(realPanel.makeFirstResponder(pendingField.field), "maximum items field accepts pending-reduction edit")
let pendingEditor = realPanel.fieldEditor(true, for: pendingField.field) as! NSTextView
pendingEditor.selectAll(nil)
pendingEditor.insertText("100", replacementRange: NSRange(location: NSNotFound, length: 0))
pendingField.field.textDidChange(Notification(name: NSText.didChangeNotification, object: pendingEditor))
var freshPanelContent = synthetic
freshPanelContent.clipboardLine = "fresh clipboard status"
freshPanelContent.statistics = StoreStatistics(clipCount: 142, clipBytes: 4_000_000, diskBytes: 3_000_000,
    oldestCopiedAt: now.addingTimeInterval(-2 * 86_400), latest: latest)
windowController.show(freshPanelContent)
check(windowView.confirmation == .keepHistory(limit: 100, deleting: 42)
    && windowView.content?.settings.historyLimit == 1000 && windowSettings.settings.historyLimit == 1000,
      "refresh with pending reduction keeps accepted limit in content and storage")
check(windowView.content?.clipboardLine == "fresh clipboard status"
    && windowView.content?.statistics?.clipBytes == 4_000_000,
      "refresh retains incoming clipboard and statistics while edit commits")
windowView.cancelConfirmation()
check(windowSettings.settings.historyLimit == 1000
    && (windowView.control(named: "keep") as? PanelIntegerField)?.field.stringValue == "1000",
      "cancelling pending reduction restores accepted input value")
let repeatPendingField = windowView.control(named: "keep") as! PanelIntegerField
check(realPanel.makeFirstResponder(repeatPendingField.field), "cancelled value can be re-edited natively")
let repeatEditor = realPanel.fieldEditor(true, for: repeatPendingField.field) as! NSTextView
repeatEditor.selectAll(nil)
repeatEditor.insertText("100", replacementRange: NSRange(location: NSNotFound, length: 0))
repeatPendingField.field.textDidChange(Notification(name: NSText.didChangeNotification, object: repeatEditor))
repeatEditor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
check(windowView.confirmation == .keepHistory(limit: 100, deleting: 42),
      "re-entering cancelled candidate asks for confirmation again")
let keepCallsBeforeConfirm = windowKeepHistoryCalls
windowView.confirm()
check(windowKeepHistoryCalls == keepCallsBeforeConfirm + 1 && windowSettings.settings.historyLimit == 100,
      "confirmed reduction invokes history-limit action exactly once")
windowSettings.update { $0.historyLimit = 4321 }
synthetic.settings = windowSettings.settings
windowController.show(synthetic)
let unchangedField = windowView.control(named: "keep") as! PanelIntegerField
check(realPanel.makeFirstResponder(unchangedField.field), "unchanged numeric value can be edited")
var unchangedRefresh = synthetic
unchangedRefresh.clipboardLine = "new clip, unchanged numeric draft"
unchangedRefresh.statistics?.clipBytes = 4_500_000
windowController.show(unchangedRefresh)
check(windowView.content?.clipboardLine == "new clip, unchanged numeric draft"
    && windowView.content?.statistics?.clipBytes == 4_500_000,
      "unchanged field blur retains fresh clipboard and statistics")
let invalidField = windowView.control(named: "keep") as! PanelIntegerField
check(realPanel.makeFirstResponder(invalidField.field), "invalid numeric value can be edited")
let invalidEditor = realPanel.fieldEditor(true, for: invalidField.field) as! NSTextView
invalidEditor.selectAll(nil)
invalidEditor.insertText("0", replacementRange: NSRange(location: NSNotFound, length: 0))
invalidField.field.textDidChange(Notification(name: NSText.didChangeNotification, object: invalidEditor))
var invalidRefresh = synthetic
invalidRefresh.clipboardLine = "new clip, invalid numeric draft"
invalidRefresh.statistics?.clipBytes = 4_600_000
windowController.show(invalidRefresh)
check(windowView.content?.clipboardLine == "new clip, invalid numeric draft"
    && windowView.content?.statistics?.clipBytes == 4_600_000
    && windowSettings.settings.historyLimit == 4321,
      "invalid field blur rejects draft but retains fresh panel content")
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
check(realPanel.frame.height == ordinaryHeight - 24 && windowView.preferredHeight == realPanel.frame.height,
      "clear confirmation fits the reserved footer layout")
let clearLockedField = windowView.control(named: "keep") as! PanelIntegerField
check(!clearLockedField.isEnabled && !clearLockedField.field.isEnabled, "clear confirmation disables native numeric editor")
clearLockedField.field.stringValue = "77"
clearLockedField.commit()
check(windowSettings.settings.historyLimit == 4321, "disabled numeric editor cannot modify history during clear confirmation")
windowFits("confirmation")
(windowView.control(named: "confirmCancel") as? PanelButton)?.press()
check(realPanel.frame.height == ordinaryHeight, "cancel immediately shrinks the owning window")
let reductionField = windowView.control(named: "keep") as! PanelIntegerField
check(realPanel.makeFirstResponder(reductionField.field), "maximum items field re-enters native edit mode")
let reductionEditor = realPanel.fieldEditor(true, for: reductionField.field) as! NSTextView
reductionEditor.selectAll(nil)
reductionEditor.insertText("100", replacementRange: NSRange(location: NSNotFound, length: 0))
reductionField.field.textDidChange(Notification(name: NSText.didChangeNotification, object: reductionEditor))
reductionEditor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
check(windowView.confirmation == .keepHistory(limit: 100, deleting: 42)
    && realPanel.frame.height == ordinaryHeight - 24, "smaller-limit confirmation fits the reserved footer layout")
let reductionLockedField = windowView.control(named: "keep") as! PanelIntegerField
check(!reductionLockedField.isEnabled && !reductionLockedField.field.isEnabled, "reduction confirmation disables native numeric editor")
reductionLockedField.field.stringValue = "200"
reductionLockedField.commit()
check(windowView.confirmation == .keepHistory(limit: 100, deleting: 42) && windowSettings.settings.historyLimit == 4321,
      "disabled editor cannot replace pending reduction")
windowView.keyDown(with: key(53))
check(realPanel.frame.height == ordinaryHeight && windowSettings.settings.historyLimit == 4321,
      "escape cancels reduction and preserves saved limit")
let confirmedField = windowView.control(named: "keep") as! PanelIntegerField
check(realPanel.makeFirstResponder(confirmedField.field), "field re-enters native edit after cancel")
let confirmedEditor = realPanel.fieldEditor(true, for: confirmedField.field) as! NSTextView
confirmedEditor.selectAll(nil)
confirmedEditor.insertText("100", replacementRange: NSRange(location: NSNotFound, length: 0))
confirmedField.field.textDidChange(Notification(name: NSText.didChangeNotification, object: confirmedEditor))
confirmedEditor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
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

// Clipboard diagnostics are intentionally not displayed in the panel header or settings body.
synthetic.clipboardLine = "not recorded: synthetic failure"
windowController.show(synthetic)
check(!windowView.scrollView.documentView!.subviews.contains {
    ($0 as? NSTextField)?.accessibilityIdentifier() == "clipboardStatus"
}, "clipboard diagnostic line is omitted")
temporaryDefaults.removePersistentDomain(forName: defaultsDomain)
realPanel.close()

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
