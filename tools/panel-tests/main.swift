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
func iconChoices() -> PanelIconStyleChoices? { view.control(named: "iconStyle") as? PanelIconStyleChoices }
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

// MARK: original main page
check(view.page == .main, "opening starts on main")
check(view.controls.map(\.partName) == ["pause", "login", "paste", "plainText", "pasteSpecial", "keep", "largest", "historySize", "pickerWidth", "contentLines", "density", "visibleItems", "typeIcons", "timestamps", "settings", "openPicker", "quit"],
      "Main retains capture, paste, limits and picker controls, followed by the three footer actions")
check(view.preferredHeight == 519, "Main shrinks by the removed ignored-app row and extra footer row")
check(view.control(named: "iconStyle") == nil && view.control(named: "paste") != nil && view.control(named: "pickerWidth") != nil, "only new icon style is absent from Main")
check(button("settings")?.isEnabled == true, "Settings enabled")
check(checkbox("pause")?.accessibilityLabel() == "Keep clipboard history", "main history toggle accessible")
let mainPreferredHeight = view.preferredHeight
let panelDocument = view.scrollView.documentView!
let shortcutHint = panelDocument.subviews.compactMap { $0 as? NSTextField }
    .first { $0.accessibilityIdentifier() == "pickerShortcutHint" }
check(shortcutHint?.stringValue == "\u{21E7}\u{2318}V" && shortcutHint?.alignment == .right
    && shortcutHint!.frame.maxX <= SettingsPanelView.width - 16
    && checkbox("pause")!.frame.maxX <= shortcutHint!.frame.minX - 8,
      "History row displays the current picker shortcut as a right-aligned inset hint with a clear gap")
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

if let directory = ProcessInfo.processInfo.environment["PANEL_SNAPSHOT_DIRECTORY"] {
    try! FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
}

// Navigation links have no normal border. Mouse navigation does not synthesize keyboard focus;
// Tab and accessibility navigation retain a visible system-colored focus indicator.
let mouse = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
    windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
for appearance in [NSAppearance.Name.aqua, .darkAqua] {
    view.appearance = NSAppearance(named: appearance)
    view.resetInteraction()
    let navigation = button("settings")!
    check(navigation.isLink && navigation.isNavigation && !navigation.isFocused, "normal Settings is a quiet unfocused link in \(appearance.rawValue)")
    func navigationPixels(_ button: PanelButton) -> Data {
        let bitmap = button.bitmapImageRepForCachingDisplay(in: button.bounds)!
        button.cacheDisplay(in: button.bounds, to: bitmap)
        return bitmap.representation(using: .png, properties: [:])!
    }
    func snapshotNavigation(_ button: PanelButton, _ state: String) {
        guard let directory = ProcessInfo.processInfo.environment["PANEL_SNAPSHOT_DIRECTORY"] else { return }
        try! navigationPixels(button).write(to: URL(fileURLWithPath: directory)
            .appendingPathComponent("navigation-\(button.partName)-\(state)-\(appearance.rawValue).png"))
    }
    func checkUnderline(_ button: PanelButton) {
        button.isFocused = false
        let borderless = navigationPixels(button)
        button.isNavigation = false
        check(navigationPixels(button) == borderless,
              "\(button.partName) normal state matches a borderless link without any outline")
        button.isNavigation = true
        let normal = button.bitmapImageRepForCachingDisplay(in: button.bounds)!
        button.cacheDisplay(in: button.bounds, to: normal)
        button.isFocused = true
        let focused = button.bitmapImageRepForCachingDisplay(in: button.bounds)!
        button.cacheDisplay(in: button.bounds, to: focused)
        let underline = button.navigationUnderlineRect
        check(button.bounds.contains(underline) && underline.height == 2
            && underline.width == InterfaceStyle.width(of: button.title, font: InterfaceStyle.controlFont)
            && underline.minX == (button.symbolName == nil ? 3 : 21)
            && underline.maxX < button.bounds.maxX && underline.minY > button.bounds.midY,
              "\(button.partName) underline follows only the native-size label in \(appearance.rawValue)")
        let scale = CGFloat(focused.pixelsWide) / button.bounds.width
        var changed = 0
        var outsideUnderline = 0
        for y in 0..<focused.pixelsHigh {
            for x in 0..<focused.pixelsWide {
                if normal.colorAt(x: x, y: y) != focused.colorAt(x: x, y: y) {
                    changed += 1
                    let point = NSPoint(x: (CGFloat(x) + 0.5) / scale, y: (CGFloat(y) + 0.5) / scale)
                    if !underline.insetBy(dx: -0.5, dy: -0.5).contains(point) { outsideUnderline += 1 }
                }
            }
        }
        check(changed >= Int(underline.width * scale) && outsideUnderline == 0,
              "\(button.partName) keyboard/accessibility paints a visible underline and no rectangular outline in \(appearance.rawValue)")
    }
    snapshotNavigation(navigation, "normal")
    let ordinary = navigationPixels(navigation)
    navigation.isNavigation = false
    check(navigationPixels(navigation) == ordinary, "normal navigation matches existing borderless footer links in \(appearance.rawValue)")
    navigation.isNavigation = true
    navigation.onFocusRequest?(navigation)
    check(navigation.isFocused && navigationPixels(navigation) != ordinary, "keyboard navigation focus is visibly distinct in \(appearance.rawValue)")
    checkUnderline(navigation)
    snapshotNavigation(navigation, "keyboard")
    navigation.mouseDown(with: mouse)
    check(!navigation.isFocused && navigationPixels(navigation) == ordinary,
          "mouse Settings has no underline or outline")
    snapshotNavigation(navigation, "mouse")
    check(view.page == .settings && view.focusedPart == "back" && button("back")?.isFocused == false, "mouse Settings opens without a keyboard outline")
    let back = button("back")!
    check(back.isLink && back.isNavigation, "Back uses the same quiet navigation treatment")
    let plainBack = navigationPixels(back)
    snapshotNavigation(back, "normal")
    check(back.symbolName == nil && back.title == "Main" && back.bounds.height >= 20,
          "Main breadcrumb has no chevron and retains native mouse target")
    checkUnderline(back)
    back.isFocused = false
    view.moveFocus(by: 1)
    view.moveFocus(by: -1)
    check(back.isFocused && navigationPixels(back) != plainBack, "Tab draws discernible Back focus in \(appearance.rawValue)")
    snapshotNavigation(back, "keyboard")
    if let directory = ProcessInfo.processInfo.environment["PANEL_SNAPSHOT_DIRECTORY"] {
        try! render().representation(using: .png, properties: [:])!.write(to:
            URL(fileURLWithPath: directory).appendingPathComponent("panel-settings-focused-\(appearance.rawValue).png"))
    }
    view.keyDown(with: key(36, "\r"))
    check(view.page == .main && button("settings")?.isFocused == true, "keyboard Back retains Settings focus")
    if let directory = ProcessInfo.processInfo.environment["PANEL_SNAPSHOT_DIRECTORY"] {
        try! render().representation(using: .png, properties: [:])!.write(to:
            URL(fileURLWithPath: directory).appendingPathComponent("panel-main-focused-\(appearance.rawValue).png"))
    }
    button("settings")?.mouseDown(with: mouse)
    let mouseBack = button("back")!
    mouseBack.mouseDown(with: mouse)
    check(!mouseBack.isFocused && navigationPixels(mouseBack) == plainBack, "mouse Back has no underline or outline")
    snapshotNavigation(mouseBack, "mouse")
    check(view.page == .main && view.focusedPart == "settings" && button("settings")?.isFocused == false, "mouse Back returns without a keyboard outline")
    _ = button("settings")?.accessibilityPerformPress()
    check(button("back")?.isFocused == true, "accessibility navigation retains discernible focus")
    checkUnderline(button("back")!)
    _ = button("back")?.accessibilityPerformPress()
    check(view.page == .main && button("settings")?.isFocused == true,
          "accessible Back preserves action and Settings focus routing")
    checkUnderline(button("settings")!)
    view.keyDown(with: key(49, " "))
    check(view.page == .settings && button("back")?.isFocused == true, "Space still activates Settings")
    view.keyDown(with: key(76, "\r"))
    check(view.page == .main && button("settings")?.isFocused == true, "keypad Return still activates Back")
}
view.appearance = nil
view.resetInteraction()

// MARK: in-panel navigation and native controls
view.show(content())
button("settings")?.press()
check(view.page == .settings && view.focusedPart == "back", "Settings opens in place with Back as the next keyboard navigation anchor")
check(view.preferredHeight == 509, "settings uses content-driven preferred size")
check(view.control(named: "pause") == nil && view.activityChart == nil, "main-only content hidden in settings")
check(button("back")?.accessibilityLabel() == "Return to Main" && button("back")?.accessibilityRole() == .button,
      "Back exposes accessible navigation action")
check(view.controls.map(\.partName) == ["back", "ignoreFrontmost", "iconStyle", "clearHistory"], "Settings contains breadcrumb Main, ignored apps, Icon style and separate Clear history")
let document = view.scrollView.documentView as! PanelSectionView
check(document.sectionHeaders.isEmpty, "Settings heading has no full-width section strip")
check(iconChoices()?.titles == ClipIconStyle.allCases.map(\.title) && iconChoices()?.selectedIndex == 0,
      "single family selector defaults to Current")
check(iconChoices()?.accessibilityLabel() == "Icon style", "visual family selector accessible")
iconChoices()?.select(2)
check(settings.iconStyle == .compactSilhouettes && view.page == .settings && view.focusedPart == "back", "family applies without navigating away")
for style in ClipIconStyle.allCases {
    iconChoices()?.select(ClipIconStyle.allCases.firstIndex(of: style)!)
    check(settings.iconStyle == style, "family binding: \(style.rawValue)")
}
for control in view.controls {
    check(view.bounds.contains(control.convert(control.bounds, to: view)), "settings contains \(control.partName)")
}
for (index, control) in view.controls.enumerated() {
    for other in view.controls.dropFirst(index + 1) {
        check(!control.convert(control.bounds, to: view).intersects(other.convert(other.bounds, to: view)),
              "controls do not overlap: \(control.partName), \(other.partName)")
    }
}
check(render().pixelsWide > 0, "settings renders offscreen")
view.navigate(to: .main)
let numeric = integerField("keep")!
for invalid in ["", "0", "-1", "1.5", "9223372036854775808"] {
    numeric.field.stringValue = invalid
    numeric.commit()
    check(settings.historyLimit == 1000, "invalid limit rejected: \(invalid)")
}
checkbox("paste")?.toggle()
check(settings.recallMode == .clipboard, "paste toggle binding preserved")
choices("plainText")?.select(1)
check(settings.alwaysPastePlainText, "plain text binding preserved")
choices("pickerWidth")?.select(0)
choices("contentLines")?.select(3)
choices("density")?.select(1)
choices("visibleItems")?.select(3)
check(settings.pickerWidth == 360 && settings.pickerContentLines == 5 && settings.pickerDensity == 7 && settings.maximumVisibleItems == 15,
      "independent appearance controls bind")
checkbox("typeIcons")?.toggle()
checkbox("timestamps")?.toggle()
checkbox("pasteSpecial")?.toggle()
check(!settings.showTypeIcons && settings.showTimestamps && !settings.showPasteSpecial, "picker toggles preserved")
view.navigate(to: .settings)
button("ignoreFrontmost")?.press()
check(settings.ignoredApps == ["net.kovidgoyal.kitty"], "ignore action preserved")
checkbox("ignored:net.kovidgoyal.kitty")?.toggle()
check(settings.ignoredApps.isEmpty, "unignore action preserved")
view.navigate(to: .main)
for name in ["import", "export"] {
    check(button(name) == nil, "unimplemented action is removed entirely")
}
view.navigate(to: .settings)
var visited: [String] = []
for _ in 0..<view.controls.filter({ $0.isEnabled }).count { view.moveFocus(by: 1); visited.append(view.focusedPart) }
check(visited.contains("iconStyle") && visited.contains("back") && !visited.contains("import"), "Tab reaches navigation and selector, skips disabled controls")
view.keyDown(with: key(53))
check(view.page == .main && view.focusedPart == "settings" && view.preferredHeight == mainPreferredHeight,
      "Escape returns to main and restores navigation focus and height")
checkbox("pause")?.toggle()
check(settings.capturePaused, "main history toggle still applies")
button("settings")?.accessibilityPerformPress()
check(view.page == .settings, "Settings accessible press navigates")
button("back")?.accessibilityPerformPress()
check(view.page == .main, "Back accessible press navigates")
view.navigate(to: .settings)
view.resetInteraction()
check(view.page == .main && view.focusedPart.isEmpty, "reopening resets navigation to main")

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

// MARK: synthetic light previews
if let directory = ProcessInfo.processInfo.environment["PANEL_SNAPSHOT_DIRECTORY"] {
    try! FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    let preview = SettingsPanelView()
    preview.appearance = NSAppearance(named: .aqua)
    var fixture = content()
    fixture.settings = Settings()
    preview.show(fixture)
    for (name, page) in [("main", SettingsPanelView.Page.main), ("settings", .settings)] {
        preview.navigate(to: page)
        let bitmap = preview.bitmapImageRepForCachingDisplay(in: preview.bounds)!
        preview.cacheDisplay(in: preview.bounds, to: bitmap)
        try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: directory).appendingPathComponent("panel-\(name).png"))
    }
}

view.navigate(to: .main)
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
let mainHeight = windowController.panel.frame.height
windowView.navigate(to: .settings)
check(windowController.panel.frame.height < mainHeight, "navigation resizes same owning panel to settings")
windowView.navigate(to: .main)
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
windowView.navigate(to: .main)
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
(windowView.control(named: "confirmCancel") as? PanelButton)?.press()
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
(windowView.control(named: "confirmDelete") as? PanelButton)?.press()
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
windowView.navigate(to: .settings)
let settingsHeight = realPanel.frame.height
windowView.navigate(to: .settings)
(windowView.control(named: "clearHistory") as? PanelButton)?.press()
check(realPanel.frame.height == settingsHeight + 40 && windowView.preferredHeight == realPanel.frame.height,
      "Settings clear confirmation expands the measured document")
check(windowView.control(named: "iconStyle")?.isEnabled == false && windowView.control(named: "keep") == nil,
      "clear confirmation disables Settings previews, with no Main numeric editor present")
windowFits("confirmation")
(windowView.control(named: "confirmCancel") as? PanelButton)?.press()
check(realPanel.frame.height == settingsHeight, "cancel immediately shrinks the owning Settings window")
var windowClearCalls = 0
windowView.actions.clearHistory = {
    windowClearCalls += 1
    check(windowView.confirmation == nil && windowView.focusedPart.isEmpty, "clear resets interaction BEFORE production callback")
    synthetic.statistics?.clipCount = 0
    windowController.show(synthetic)
}
(windowView.control(named: "clearHistory") as? PanelButton)?.press()
windowController.show(synthetic)
check(windowView.focusedPart == "confirmCancel", "statistics refresh preserves Cancel default")
(windowView.control(named: "confirmDelete") as? PanelButton)?.press()
windowView.confirm()
check(windowClearCalls == 1 && windowView.page == .settings && windowView.confirmation == nil
      && windowView.control(named: "clearHistory")?.isEnabled == false && windowView.focusedPart.isEmpty,
      "production callback refresh clears once, stays Settings and cannot rearm destructive selection")
synthetic.statistics = statistics
windowController.show(synthetic)
windowView.navigate(to: .main)
let reductionField = windowView.control(named: "keep") as! PanelIntegerField
check(realPanel.makeFirstResponder(reductionField.field), "maximum items field re-enters native edit mode")
let reductionEditor = realPanel.fieldEditor(true, for: reductionField.field) as! NSTextView
reductionEditor.selectAll(nil)
reductionEditor.insertText("100", replacementRange: NSRange(location: NSNotFound, length: 0))
reductionField.field.textDidChange(Notification(name: NSText.didChangeNotification, object: reductionEditor))
reductionEditor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
check(windowView.confirmation == .keepHistory(limit: 100, deleting: 42)
    && realPanel.frame.height == ordinaryHeight + 24, "smaller-limit confirmation fits the reserved footer layout")
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
(windowView.control(named: "confirmDelete") as? PanelButton)?.press()
check(windowSettings.settings.historyLimit == 100 && realPanel.frame.height == ordinaryHeight,
      "confirm applies through temporary defaults and restores ordinary height")

// Many exclusions overflow Settings; Main independently scrolls on a smaller display.
visibleFrame = NSRect(x: -1280, y: -200, width: 1280, height: 696)
anchor = NSRect(x: -30, y: 496, width: 26, height: 24)
windowSettings.update { $0.ignoredApps = (0..<40).map { "test.ignored.\($0)" } }
synthetic.settings = windowSettings.settings
synthetic.notices = [.needsAccessibility, .hotkeyUnavailable(.shiftCommandV)]
synthetic.loginMessage = "Synthetic login item needs approval"
windowController.show(synthetic)
windowView.navigate(to: .settings)
windowFits("overflow")
check(windowView.preferredHeight > realPanel.frame.height && realPanel.frame.height == visibleFrame.height - 8,
      "overflow is bounded to the anchor screen's available height")
check(windowView.scrollView.documentView!.frame.height > windowView.scrollView.contentView.bounds.height,
      "overflowing settings have a scroll document")
check(windowView.control(named: "openPicker") == nil && windowView.control(named: "ignored:test.ignored.39") != nil, "overflowing exclusions belong only to Settings")
windowView.resetInteraction()
windowView.navigate(to: .main)
visibleFrame.size.height = 480
windowController.resizeToFit()
var allFocusedControlsVisible = true
for _ in 0..<windowView.controls.filter({ $0.isEnabled }).count {
    windowView.moveFocus(by: 1)
    allFocusedControlsVisible = allFocusedControlsVisible && visibleControl(windowView.focusedPart)
}
check(allFocusedControlsVisible, "every enabled control is brought fully into view by Tab")
while windowView.focusedPart != "timestamps" { windowView.moveFocus(by: 1) }
check(windowView.scrollView.contentView.bounds.minY > 0, "keyboard navigation scrolls overflowing settings")
check(visibleControl("openPicker") && visibleControl("quit"), "footer remains visible after scrolling")
_ = (windowView.control(named: "login") as? PanelCheckbox)?.accessibilityPerformPress()
check(visibleControl("login"), "accessibility action reveals and focuses an offscreen custom control")
let widthPopup = (windowView.control(named: "pickerWidth") as! PanelDropdown).popup
widthPopup.keyDown(with: key(48, "\t"))
check(windowView.focusedPart == "contentLines" && visibleControl("contentLines"),
      "native popup Tab routes through the panel even inside its scroll document")
windowView.navigate(to: .settings)
(windowView.control(named: "clearHistory") as? PanelButton)?.press()
windowFits("bounded confirmation")
check(visibleControl("confirmDelete") && visibleControl("confirmCancel"), "bounded confirmation actions stay visible")
windowView.keyDown(with: key(53))
windowView.navigate(to: .main)
check(visibleControl("openPicker") && visibleControl("quit"), "bounded cancel then Main restores reachable footer")
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
windowView.navigate(to: .settings)
(windowView.control(named: "clearHistory") as? PanelButton)?.press()
check(visibleControl("confirmDelete") && visibleControl("confirmCancel"), "confirmation stays reachable on a 360-point display")
(windowView.control(named: "confirmCancel") as? PanelButton)?.press()

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

// MARK: restored pre-split safety, interaction and appearance regressions
// Keep the original behavioral assertions alongside the new navigation tests, on their owning page.
do {
    settings = Settings()
    statistics.clipCount = 142
    calls.removeAll()
    view.actions = actions
    view.show(content())
    view.resetInteraction()
    check(checkbox("pause")?.isOn == true, "Main history checkbox starts checked")
    func enterLimit(_ value: Int) {
        let control = integerField("keep")!
        control.field.stringValue = String(value)
        check(control.field.sendAction(control.field.action, to: control.field.target), "native limit field dispatches its action")
    }
    // MARK: layout
    check(view.frame.width == SettingsPanelView.width && view.frame.height == view.preferredHeight, "view sized to its content")
    check(view.preferredHeight > 300 && view.preferredHeight < 760, "height is reasonable (\(view.preferredHeight))")
    check(view.controls.map(\.partName) == ["pause", "login", "paste", "plainText", "pasteSpecial", "keep", "largest", "historySize", "pickerWidth", "contentLines", "density", "visibleItems", "typeIcons", "timestamps", "settings", "openPicker", "quit"], "panel controls follow retained sections and the simplified footer")
    check(view.controls.allSatisfy { view.bounds.contains($0.convert($0.bounds, to: view)) }, "every control inside the panel")
    for (index, control) in view.controls.enumerated() {
        for other in view.controls[(index + 1)...] where control.convert(control.bounds, to: view).intersects(other.convert(other.bounds, to: view)) {
            check(false, "\(control.partName) overlaps \(other.partName)")
        }
    }
    check(checkbox("paste")?.isOn == true && choices("plainText")?.selectedIndex == 0 && checkbox("login")?.isOn == false, "checkbox states")
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
        check(settings.historyLimit == 1000 && numericControl.field.stringValue == "1000", "invalid maximum items rejected: \(invalid)")
    }
    check(numericControl.field.frame.width > 0 && numericControl.field.frame.height >= 20,
          "native numeric editor has usable geometry")
    let plainTextControl = choices("plainText")!
    check(plainTextControl.frame.minX > 0 && plainTextControl.frame.maxX <= view.bounds.width,
          "long paste dropdown stays within the panel width")
    check(choices("largest")?.titles == ["5", "20", "50", "100"] && choices("largest")?.selectedIndex == 1, "largest clip choices")
    check(button("openPicker")?.title == "Open Picker  \u{21E7}\u{2318}V", "open picker shows the hotkey")
    check(button("ignoreFrontmost") == nil, "ignored apps is absent from Main")
    check(render().pixelsWide > 0, "panel draws")
    let panelDocument = view.scrollView.documentView!
    let rowLabels = panelDocument.subviews.compactMap { $0 as? NSTextField }
    check(rowLabels.contains { $0.frame.minX == 16 && ($0.stringValue == "When pasting") },
          "setting labels share the 16-point content inset")
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
    view.navigate(to: .main)
    check(checkbox("pause")?.button.cell is NSButtonCell && checkbox("pause")?.button.state == .on,
          "checkbox uses a native checked cell")
    check(checkbox("pause")?.button.controlSize == .small && checkbox("pause")?.button.font == InterfaceStyle.controlFont,
          "native checkbox typography and size are compact")
    check(button("clearHistory") == nil && button("openPicker")?.symbolName == "list.clipboard"
          && button("import") == nil && button("export") == nil,
          "restrained action symbols use their actual meaning")
    check(checkbox("pause")?.hitTest(NSPoint(x: checkbox("pause")!.frame.midX, y: checkbox("pause")!.frame.midY)) === checkbox("pause"),
          "native checkbox drawing leaves mouse handling with the panel control")
    for page in [SettingsPanelView.Page.main, .settings] {
        view.navigate(to: page)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            view.appearance = NSAppearance(named: appearance)
            let bitmap = render()
            let scale = CGFloat(bitmap.pixelsWide) / view.bounds.width
            func luminance(_ point: NSPoint) -> CGFloat {
                let color = bitmap.colorAt(x: Int(point.x * scale), y: Int(point.y * scale))!.usingColorSpace(.deviceRGB)!
                return (color.redComponent + color.greenComponent + color.blueComponent) / 3
            }
            let header = document.sectionHeaders.first ?? NSRect(x: 0, y: 16, width: 390, height: 24)
            let headerTone = luminance(NSPoint(x: 4, y: header.midY))
            let bodyTone = luminance(NSPoint(x: 4, y: view.control(named: page == .main ? "pause" : "iconStyle")!.frame.midY))
            check(page == .settings ? abs(headerTone - bodyTone) < 0.04 : abs(headerTone - bodyTone) > 0.04, "\(page) section strip visibly differs from body in \(appearance.rawValue)")
        }
    }
    view.navigate(to: .main)
    view.appearance = nil
    // MARK: checkboxes and choices apply at once
    checkbox("paste")?.toggle()
    check(settings.recallMode == .clipboard && checkbox("paste")?.isOn == false, "unchecking paste switches to clipboard")
    choices("plainText")?.select(1)
    check(settings.alwaysPastePlainText && choices("plainText")?.selectedIndex == 1, "always plain text")
    view.navigate(to: .main)
    checkbox("pause")?.toggle()
    check(settings.capturePaused, "pause")
    view.navigate(to: .main)
    check(settings.pickerHotkey == .shiftCommandV, "stored picker shortcut is preserved")
    choices("largest")?.select(3)
    check(settings.maximumClipMegabytes == 100, "largest clip choice")
    enterLimit(Int.max)
    check(settings.historyLimit == Int.max && view.confirmation == nil, "Int.max applies without allocating or loading clip rows")
    enterLimit(10_000)
    check(settings.historyLimit == 10_000 && view.confirmation == nil, "a larger limit applies without asking")

    // MARK: ignored apps
    view.navigate(to: .settings)
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
    view.navigate(to: .main)

    // MARK: confirmation inside the panel
    calls.removeAll()
    enterLimit(100)
    check(view.confirmation == .keepHistory(limit: 100, deleting: 42) && settings.historyLimit == 10_000, "a smaller limit asks first")
    check(button("confirmDelete")?.isFocused == true && button("openPicker") == nil, "confirmation replaces the buttons, delete focused")
    check(render().pixelsWide > 0, "confirmation draws")
    view.keyDown(with: key(53, "\u{1b}"))
    check(view.confirmation == nil && settings.historyLimit == 10_000 && calls.isEmpty, "escape cancels")
    enterLimit(100)
    view.keyDown(with: key(36, "\r"))
    check(calls == ["keep 100"] && view.confirmation == nil && settings.historyLimit == 100, "return confirms")
    calls.removeAll()
    view.navigate(to: .settings)
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
    view.navigate(to: .main)
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
    notices[1].press()
    check(calls == ["notice needsAccessibility", "notice \(PanelNotice.hotkeyUnavailable(.shiftCommandV))"],
          "hotkey notice opens its retry action")
    check(!PanelNotice.hotkeyUnavailable(.shiftCommandV).title.contains("\u{2014}"), "no em dash in notices")

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
        var snapshotContent = withNotices
        snapshotContent.settings.historyLimit = 1000
        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            view.navigate(to: .main)
            view.appearance = NSAppearance(named: appearanceName)
            view.show(snapshotContent)
            try! render().representation(using: .png, properties: [:])!.write(
                to: URL(fileURLWithPath: directory).appendingPathComponent("panel-\(appearanceName.rawValue).png"))
            enterLimit(100)
            check(view.confirmation != nil, "confirmation snapshot exercises real numeric commit")
            try! render().representation(using: .png, properties: [:])!.write(
                to: URL(fileURLWithPath: directory).appendingPathComponent("panel-confirm-\(appearanceName.rawValue).png"))
            button("confirmCancel")?.press()
            for (name, page) in [("main", SettingsPanelView.Page.main), ("settings", .settings)] {
                view.navigate(to: page)
                try! render().representation(using: .png, properties: [:])!.write(
                    to: URL(fileURLWithPath: directory).appendingPathComponent("panel-\(name)-\(appearanceName.rawValue).png"))
            }
        }
    }

    view.appearance = nil
    view.navigate(to: .main)
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
    view.navigate(to: .main)
    check(settings.copyActivityDays == 5 && view.activityChart?.days == 5, "saved range does not alter fixed production chart")
    view.navigate(to: .main)
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
    view.navigate(to: .main)
    checkbox("pause")?.toggle()
    check(view.statusLine.hasPrefix("Paused"), "paused status")
    var missingStats = content()
    missingStats.statistics = nil
    view.show(missingStats)
    check(view.statusLine.contains("unavailable"), "unknown history does not claim zero")
    view.show(content())

    // MARK: removed operations, accessibility, keyboard focus
    for name in ["import", "export"] {
        check(button(name) == nil, "removed action has no control, hit target, or accessibility element")
    }
    check(checkbox("pause")?.accessibilityRole() == .checkBox, "custom checkbox accessibility role")
    check(checkbox("pause")?.accessibilityLabel() == "Keep clipboard history", "checkbox accessible label")
    view.navigate(to: .main)
    check(choices("pickerWidth")?.popup.accessibilityLabel() == "Width", "native popup accessible label")
    check(choices("pickerWidth")?.popup.itemTitles == ["Narrow (360 pt)", "Standard (460 pt)", "Wide (560 pt)"], "native popup choices")
    view.resetInteraction()
    view.navigate(to: .settings)
    view.keyDown(with: key(48, "\t", .shift))
    check(view.focusedPart == "clearHistory", "Settings reverse Tab wraps from breadcrumb to Clear")
    var visited: [String] = []
    for _ in 0..<view.controls.filter({ $0.isEnabled }).count {
        view.moveFocus(by: 1)
        visited.append(view.focusedPart)
    }
    check(!visited.contains("import") && !visited.contains("export") && visited.contains("iconStyle"), "tab skips disabled controls and reaches Icon style")
    view.moveFocus(by: 1)
    check(view.focusedPart == "back", "Settings tab wraps to Back")
    check(view.control(named: "clearHistory") != nil && view.control(named: "settings") == nil,
          "Settings owns Clear and omits Main navigation action")
    view.navigate(to: .main)
    (view.control(named: "keep") as? PanelIntegerField)?.onCommit?(10)
    check(choices("pickerWidth")?.popup.isEnabled == false, "confirmation disables original Main settings")
    button("confirmCancel")?.press()
    check(choices("pickerWidth")?.popup.isEnabled == true, "cancel restores original Main settings")


    // Clear history belongs only to Settings and retain confirmation/empty-history guards.
    for page in [SettingsPanelView.Page.settings] {
        view.navigate(to: page)
        calls.removeAll()
        button("clearHistory")?.press()
        check(view.confirmation == .clearHistory(clipCount: 142) && calls.isEmpty,
              "\(page) Clear asks before invoking an action")
        for _ in 0..<6 {
            view.keyDown(with: key(48, "\t"))
            check(["confirmDelete", "confirmCancel"].contains(view.focusedPart), "\(page) confirmation confines keyboard focus")
        }
        button("confirmCancel")?.press()
        check(view.confirmation == nil && calls.isEmpty, "\(page) Clear cancellation does not dispatch")
        button("clearHistory")?.press()
        button("confirmDelete")?.press()
        check(view.confirmation == nil && calls == ["clear"], "\(page) Delete dispatches clearHistory exactly once")
        statistics.clipCount = 0
        view.show(content())
        calls.removeAll()
        button("clearHistory")?.press()
        check(view.confirmation == nil && calls.isEmpty && button("clearHistory")?.isEnabled == false,
              "\(page) empty history suppresses Clear")
        statistics.clipCount = 142
        view.show(content())
    }

}

/// Draws only the expected production artwork, for pixel comparisons with Settings samples.
final class PreviewArtworkProbe: NSView {
    let style: ClipIconStyle
    var selected = false
    var enabled = true
    init(style: ClipIconStyle) {
        self.style = style
        super.init(frame: NSRect(x: 0, y: 0, width: 358, height: 62))
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        InterfaceStyle.panelBackground.setFill(); bounds.fill()
        if selected {
            let tint: NSColor = enabled ? .systemBlue : .secondaryLabelColor
            tint.withAlphaComponent(enabled ? 0.10 : 0.06).setFill(); bounds.fill()
            (enabled ? NSColor.systemBlue : .disabledControlTextColor).setFill()
            NSRect(x: 0, y: 0, width: 2, height: 62).fill()
        }
        let color: NSColor = enabled ? .labelColor : .disabledControlTextColor
        InterfaceStyle.draw(style.title, in: NSRect(x: 24, y: 2, width: 330, height: 22),
            font: selected ? .systemFont(ofSize: 12, weight: .semibold) : InterfaceStyle.controlFont, color: color)
        for (index, category) in [ClipIconCategory.text, .formatted, .link, .file].enumerated() {
            let rect = NSRect(x: 2 + CGFloat(index) * 89.5, y: 31, width: 22, height: 22)
            if style == .current {
                InterfaceStyle.drawSymbol(ClipTypeIcon.symbolName(category: category, style: .current), in: rect, color: color)
            } else {
                ClipTypeIcon.draw(category: category, style: style, in: rect, color: color)
            }
        }
    }
}

// MARK: visual icon family rows use fixed production artwork and one accessible tab stop.
do {
    let suite = "PanelVisualIconTests-\(UUID().uuidString)"
    let isolated = UserDefaults(suiteName: suite)!
    defer { isolated.removePersistentDomain(forName: suite) }
    let store = SettingsStore(defaults: isolated)
    store.update { $0.iconStyle = .editorialContentMarks }
    let preview = SettingsPanelView()
    var synthetic = SettingsPanelContent(settings: store.settings, statistics: statistics, clipboardLine: "Synthetic fixture",
        frontmostApp: nil, notices: [], appNames: [:], hotkeyLabel: nil)
    var updates = 0
    preview.actions.update = { change in
        updates += 1
        store.update(change)
        synthetic.settings = store.settings
        preview.show(synthetic)
    }
    preview.show(synthetic)
    let originalMainFrames = preview.controls.map { ($0.partName, $0.frame) }
    let originalMainHeight = preview.preferredHeight
    preview.navigate(to: .settings)
    func styles() -> PanelIconStyleChoices { preview.control(named: "iconStyle") as! PanelIconStyleChoices }
    check(styles().rows.count == 5 && styles().frame.height == 310 && styles().frame.width == 358,
          "five flat preview rows use62pt height within358pt content width")
    check(styles().accessibilityRole() == .radioGroup && styles().accessibilityLabel() == "Icon style"
          && styles().accessibilityValue() as? String == "Editorial content marks", "preview group exposes accessible name and selected value")
    check(styles().accessibilityChildren()?.count == 5, "all style rows are accessibility children")
    check(PanelIconStyleRow.samples.map { $0.0 } == [.text, .formatted, .link, .file], "fixed synthetic examples represent four reliable types")
    let before = store.settings
    preview.keyDown(with: key(48, "\t"))
    check(preview.focusedPart == "iconStyle" && styles().focusedIndex == 4, "Tab enters style group at selected Editorial")
    preview.keyDown(with: key(126))
    check(styles().focusedIndex == 3 && styles().selectedIndex == 4 && updates == 0 && store.settings == before,
          "Up moves focus only without changing density or persisted style")
    check(styles().rows[3].isFocused && !styles().rows[3].isSelected && styles().rows[4].isSelected
          && !styles().rows[4].isFocused, "focused underline and selected checkmark are distinct")
    let focusMark = styles().rows[3].focusUnderlineRect
    check(focusMark.height == 2 && focusMark.minX == 24 && focusMark.width < styles().rows[3].bounds.width - 48,
          "preview keyboard focus is a title underline, not a row rectangle")
    preview.keyDown(with: key(49, " "))
    check(store.settings.iconStyle == .framedSymbols && updates == 1 && styles().focusedIndex == 3
          && preview.focusedPart == "iconStyle", "Space selects once and synchronous rebuild preserves row focus")
    check(SettingsStore(defaults: isolated).settings.iconStyle == .framedSymbols, "visual selection persists using existing raw value")
    preview.keyDown(with: key(49, " "))
    check(updates == 1, "selecting current row does not invoke redundant callback")
    preview.keyDown(with: key(48, "\t"))
    check(preview.focusedPart == "clearHistory", "Tab exits style group to Settings Clear history")
    preview.keyDown(with: key(48, "\t", .shift))
    check(preview.focusedPart == "iconStyle", "reverse Tab enters group from footer")
    preview.keyDown(with: key(48, "\t", .shift))
    check(preview.focusedPart == "back", "reverse Tab exits group to Back")
    for (index, style) in ClipIconStyle.allCases.enumerated() {
        let row = styles().rows[index]
        check(row.accessibilityRole() == .radioButton && row.accessibilityLabel() == style.title,
              "style row has selectable accessible role/name: \(style.rawValue)")
        check(row.accessibilityPerformPress(), "accessible press selects \(style.rawValue)")
        check(store.settings.iconStyle == style && styles().selectedIndex == index
              && styles().rows[index].accessibilityValue() as? Int == 1, "accessible press immediate binding/value: \(style.rawValue)")
    }
    let click = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
    let mouseRow = styles().rows[0]
    let mousePoint = mouseRow.convert(NSPoint(x: mouseRow.bounds.midX, y: mouseRow.bounds.midY), to: styles().superview)
    check(styles().hitTest(mousePoint) === mouseRow, "production group hit testing routes sample and title area to selectable row")
    mouseRow.mouseDown(with: click)
    check(store.settings.iconStyle == .current && preview.focusedPart == "iconStyle" && styles().focusedIndex == 0,
          "production mouse handler selects clicked style and anchors keyboard focus")
    preview.keyDown(with: key(126))
    check(styles().focusedIndex == 0, "Up is bounded at first row")
    for _ in 0..<8 { preview.keyDown(with: key(125)) }
    check(styles().focusedIndex == 4 && styles().selectedIndex == 0, "Down bounded at last row without selection")
    styles().isEnabled = false
    let disabledUpdates = updates
    check(styles().rows.allSatisfy { !$0.isEnabled && !$0.accessibilityPerformPress() }, "disabled group prevents all accessible presses")
    check(!styles().handleKey(key(49, " ")) && updates == disabledUpdates, "disabled preview group prevents keyboard selection")
    styles().isEnabled = true

    func capture(_ filename: String) {
        guard let directory = ProcessInfo.processInfo.environment["PANEL_SNAPSHOT_DIRECTORY"] else { return }
        let bitmap = preview.bitmapImageRepForCachingDisplay(in: preview.bounds)!
        preview.cacheDisplay(in: preview.bounds, to: bitmap)
        try! FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: directory).appendingPathComponent(filename))
    }
    for appearance in [NSAppearance.Name.aqua, .darkAqua] {
        preview.appearance = NSAppearance(named: appearance)
        if preview.focusedPart != "iconStyle" { preview.moveFocus(by: 1) }
        let actual = preview.bitmapImageRepForCachingDisplay(in: preview.bounds)!
        preview.cacheDisplay(in: preview.bounds, to: actual)
        let scale = CGFloat(actual.pixelsWide) / preview.bounds.width
        func cropPixels(_ bitmap: NSBitmapImageRep, _ rect: NSRect) -> Data {
            NSBitmapImageRep(cgImage: bitmap.cgImage!.cropping(to: NSRect(x: rect.minX * scale, y: rect.minY * scale,
                width: rect.width * scale, height: rect.height * scale))!).representation(using: .png, properties: [:])!
        }
        for row in styles().rows {
            let probe = PreviewArtworkProbe(style: row.style)
            probe.appearance = preview.appearance
            probe.selected = row.isSelected
            let expected = probe.bitmapImageRepForCachingDisplay(in: probe.bounds)!
            probe.cacheDisplay(in: probe.bounds, to: expected)
            let titleRect = NSRect(x: 24, y: 2, width: 330, height: 20)
            check(cropPixels(actual, row.convert(titleRect, to: preview)) == cropPixels(expected, titleRect),
                  "production style title weight matches selected semibold or unselected regular: \(row.style)/\(appearance.rawValue)")
            for index in 0..<4 {
                let iconRect = NSRect(x: 2 + CGFloat(index) * 89.5, y: 31, width: 22, height: 22)
                check(cropPixels(actual, row.convert(iconRect, to: preview)) == cropPixels(expected, iconRect),
                      "visual sample uses exact production22pt artwork: \(row.style)/\(index)/\(appearance.rawValue)")
            }
        }
        for selected in [ClipIconStyle.editorialContentMarks, .openOutlines] {
            styles().select(ClipIconStyle.allCases.firstIndex(of: selected)!)
            styles().focusRow((styles().selectedIndex + 1) % 5)
            check(styles().rows.filter(\.isSelected).count == 1 && styles().rows.filter(\.isFocused).count == 1,
                  "one selected and one focused row in \(appearance.rawValue)")
            capture("settings-visual-\(appearance.rawValue)-\(selected.rawValue).png")
        }
        preview.maximumHeight = 280
        styles().select(4)
        styles().focusRow(4)
        let row = styles().rows[4]
        let visible = row.convert(row.bounds, to: preview.scrollView.documentView)
        check(preview.frame.height == 280 && preview.scrollView.contentView.bounds.contains(visible),
              "constrained280pt panel fully reveals focused/selected last row")
        check(preview.scrollView.documentView!.frame.height > preview.scrollView.contentView.bounds.height
              && styles().subviews.allSatisfy { !($0 is NSScrollView) }, "one native scroll container; no nested wheel interception")
        check(preview.control(named: "quit") == nil && preview.scrollView.frame.height == 280,
              "Settings has no footer or reserved footer space at constrained height")
        capture("settings-visual-\(appearance.rawValue)-constrained.png")
        styles().focusRow(0)
        check(preview.scrollView.contentView.bounds.contains(styles().rows[0].convert(styles().rows[0].bounds, to: preview.scrollView.documentView)),
              "arrow focus scrolls first row fully into view")
        preview.navigate(to: .main)
        preview.navigate(to: .settings)
        check(preview.scrollView.contentView.bounds.contains(styles().rows[4].convert(styles().rows[4].bounds, to: preview.scrollView.documentView)),
              "Settings entry reveals saved selected style even while Back anchors navigation")
        preview.maximumHeight = .greatestFiniteMagnitude
    }
    preview.navigate(to: .main)
    check(preview.preferredHeight == originalMainHeight && zip(originalMainFrames, preview.controls).allSatisfy {
        $0.0.0 == $0.1.partName && $0.0.1 == $0.1.frame
    }, "round-trip navigation restores every Main frame and height")
}

// MARK: stronger selected treatment remains distinct from keyboard focus.
do {
    for appearance in [NSAppearance.Name.aqua, .darkAqua] {
        let host = SettingsPanelView()
        var fixture = SettingsPanelContent(settings: .defaults, statistics: statistics, clipboardLine: "Synthetic", frontmostApp: nil,
            notices: [.needsAccessibility], appNames: [:], hotkeyLabel: nil)
        fixture.settings.iconStyle = .editorialContentMarks
        host.show(fixture)
        let mainHeight = host.preferredHeight
        let mainFrames = host.controls.map { ($0.partName, $0.frame) }
        host.navigate(to: .settings)
        host.appearance = NSAppearance(named: appearance)
        let group = host.control(named: "iconStyle") as! PanelIconStyleChoices
        host.moveFocus(by: 1)
        group.focusRow(0)
        let selected = group.rows[4]
        let unselected = group.rows[0]
        check(selected.isSelected && !selected.isFocused && unselected.isFocused && !unselected.isSelected,
              "Editorial selected blue treatment independent of focused Current in \(appearance.rawValue)")
        check(selected.titleFont == .systemFont(ofSize: 12, weight: .semibold)
              && unselected.titleFont == InterfaceStyle.controlFont, "selected title alone uses semibold12pt")
        check(host.controls.map(\.partName) == ["back", "iconStyle", "clearHistory"] && host.preferredHeight > 400
              && host.scrollView.frame.height == host.preferredHeight, "Settings owns breadcrumb/previews/Clear with no footer blank area or Main notices")
        let body = host.scrollView.documentView!
        let labels = body.subviews.compactMap { $0 as? NSTextField }
        check(labels.filter { $0.stringValue == "Settings" }.count == 1
              && labels.filter { $0.stringValue == "/" }.isEmpty
              && !labels.contains { $0.stringValue == "Back" }, "single Main / Settings breadcrumb without duplicate heading or Back label")
        check((host.control(named: "back") as? PanelButton)?.title == "Main"
              && host.control(named: "back")?.accessibilityLabel() == "Return to Main", "Main breadcrumb exposes explicit accessible return action")
        for enabled in [true, false] {
            group.isEnabled = enabled
            let actual = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: actual)
            let scale = CGFloat(actual.pixelsWide) / host.bounds.width
            let probe = PreviewArtworkProbe(style: .editorialContentMarks)
            probe.selected = true; probe.enabled = enabled; probe.appearance = host.appearance
            let expected = probe.bitmapImageRepForCachingDisplay(in: probe.bounds)!
            probe.cacheDisplay(in: probe.bounds, to: expected)
            func color(_ bitmap: NSBitmapImageRep, _ point: NSPoint) -> NSColor {
                bitmap.colorAt(x: Int(point.x * scale), y: Int(point.y * scale))!.usingColorSpace(.deviceRGB)!
            }
            for point in [NSPoint(x: 200, y: 27), NSPoint(x: 0.5, y: 27)] {
                check(color(actual, selected.convert(point, to: host)) == color(expected, point),
                      "production selected tint/leading stripe matches restrained \(enabled ? "blue" : "disabled neutral") in \(appearance.rawValue)")
            }
            let fill = color(actual, selected.convert(NSPoint(x: 200, y: 27), to: host))
            let plain = color(actual, unselected.convert(NSPoint(x: 200, y: 27), to: host))
            check(fill != plain, "selected background remains distinguishable enabled=\(enabled) \(appearance.rawValue)")
            let stripe = color(actual, selected.convert(NSPoint(x: 0.5, y: 27), to: host))
            if !enabled {
                check(abs(stripe.redComponent - stripe.blueComponent) < 0.08,
                      "disabled selected stripe is neutral, not active saturated blue")
                check(!selected.accessibilityPerformPress(), "disabled selection cannot press")
            }
            // Compare complete sample rectangles, including antialiasing over the selected fill.
            for index in 0..<4 {
                let rect = NSRect(x: 2 + CGFloat(index) * 89.5, y: 31, width: 22, height: 22)
                func pixels(_ bitmap: NSBitmapImageRep, _ rect: NSRect) -> Data {
                    NSBitmapImageRep(cgImage: bitmap.cgImage!.cropping(to: NSRect(x: rect.minX * scale, y: rect.minY * scale,
                        width: rect.width * scale, height: rect.height * scale))!).representation(using: .png, properties: [:])!
                }
                check(pixels(actual, selected.convert(rect, to: host)) == pixels(expected, rect),
                      "selected/disabled fill preserves production22pt sample colors and geometry: \(index)/\(enabled)/\(appearance.rawValue)")
            }
        }
        group.isEnabled = true
        if let directory = ProcessInfo.processInfo.environment["PANEL_SNAPSHOT_DIRECTORY"] {
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: directory)
                .appendingPathComponent("settings-visual-\(appearance.rawValue)-editorial-unselected-focus.png"))
        }
        var visited: [String] = []
        for _ in 0..<6 { host.keyDown(with: key(48)); visited.append(host.focusedPart) }
        check(Set(visited) == ["back", "iconStyle", "clearHistory"], "Settings Tab has no hidden Main actions")
        for _ in 0..<6 { host.keyDown(with: key(48, "\t", .shift)); check(["back", "ignoreFrontmost", "iconStyle", "clearHistory"].contains(host.focusedPart), "Settings reverse Tab has no hidden Main actions") }
        _ = host.control(named: "back")?.accessibilityPerformPress()
        check(host.page == .main && host.preferredHeight == mainHeight && zip(mainFrames, host.controls).allSatisfy {
            $0.0.0 == $0.1.partName && $0.0.1 == $0.1.frame
        }, "breadcrumb restores every unchanged Main control/action/notice and geometry")
        (host.control(named: "settings") as? PanelButton)?.press()
        check(host.page == .settings, "Main still exposes working Settings footer link")
    }
}

// MARK: Clear starts safe and cannot delete from repeated original clicks or keys.
do {
    let safety = SettingsPanelView()
    var fixture = SettingsPanelContent(settings: .defaults, statistics: statistics, clipboardLine: "Synthetic",
        frontmostApp: nil, notices: [], appNames: [:], hotkeyLabel: nil)
    fixture.statistics?.clipCount = 142
    var clears = 0
    safety.actions.clearHistory = { clears += 1 }
    safety.show(fixture)
    safety.navigate(to: .settings)
    func button(_ name: String) -> PanelButton? { safety.control(named: name) as? PanelButton }
    let originalHeight = safety.preferredHeight
    let original = button("clearHistory")!
    let originalPoint = original.convert(NSPoint(x: original.bounds.midX, y: original.bounds.midY), to: safety)
    original.mouseDown(with: mouse)
    check(clears == 0 && safety.confirmation == .clearHistory(clipCount: 142), "first Clear click never dispatches deletion")
    check(safety.focusedPart == "confirmCancel" && button("confirmCancel")?.isDefault == true
          && button("confirmDelete")?.isDefault == false && button("confirmDelete")?.title == "Clear history", "Clear defaults/focus to Cancel, destructive action explicit")
    let destructive = button("confirmDelete")!
    check(!destructive.convert(destructive.bounds, to: safety).contains(originalPoint), "Clear history action never occupies original Clear hit point")
    let repeatedTarget = safety.hitTest(originalPoint)
    check(repeatedTarget !== destructive && !(repeatedTarget?.isDescendant(of: destructive) ?? false),
          "second pointer click at original coordinates cannot hit destructive action")
    original.mouseDown(with: mouse)
    check(clears == 0 && safety.focusedPart == "confirmCancel", "double click on original Clear cannot delete")
    safety.keyDown(with: key(36, "\r"))
    check(clears == 0 && safety.confirmation == nil, "Return after original Clear safely cancels")
    button("clearHistory")?.press()
    safety.keyDown(with: key(49, " "))
    check(clears == 0 && safety.confirmation == nil, "Space after original Clear safely cancels")
    button("clearHistory")?.press()
    safety.keyDown(with: key(53))
    check(clears == 0 && safety.confirmation == nil && safety.preferredHeight == originalHeight, "Escape cancels without deletion and restores normal geometry")
    button("clearHistory")?.press()
    if let directory = ProcessInfo.processInfo.environment["PANEL_SNAPSHOT_DIRECTORY"] {
        let bitmap = safety.bitmapImageRepForCachingDisplay(in: safety.bounds)!
        safety.cacheDisplay(in: safety.bounds, to: bitmap)
        try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: directory)
            .appendingPathComponent("panel-clear-safe-confirmation.png"))
    }
    safety.keyDown(with: key(48))
    check(safety.focusedPart == "confirmDelete", "Tab explicitly moves from safe Cancel to Clear history")
    safety.keyDown(with: key(36, "\r"))
    safety.confirm()
    check(clears == 1 && safety.confirmation == nil, "explicit focused Clear history dispatches exactly once")
    button("clearHistory")?.press()
    safety.navigate(to: .settings)
    check(clears == 1 && safety.confirmation == nil && safety.controls.map(\.partName) == ["back", "iconStyle", "clearHistory"], "navigation cancels Clear confirmation and omits all Main action targets")
    _ = safety.control(named: "back")?.accessibilityPerformPress()
    check(safety.control(named: "clearHistory") == nil, "Main has no destructive hit or accessibility target")
    safety.navigate(to: .settings)
    button("clearHistory")?.press()
    safety.resetInteraction() // Same reset called by production closePanel and openPanel.
    check(clears == 1 && safety.confirmation == nil && safety.page == .main, "panel close/reopen reset clears pending destructive state")
    safety.navigate(to: .settings)
    button("clearHistory")?.press()
    fixture.statistics?.clipCount = 0
    safety.show(fixture)
    button("confirmDelete")?.press()
    check(clears == 1 && safety.confirmation == nil && safety.page == .settings,
          "history becoming empty during confirmation cannot dispatch deletion or navigate")
    safety.show(fixture)
    safety.navigate(to: .settings)
    button("clearHistory")?.press()
    check(button("clearHistory")?.isEnabled == false && safety.confirmation == nil && clears == 1, "empty history cannot start or dispatch Clear")
}

// MARK: Settings-only gutters, measured heading, and constrained scrolling.
do {
    let host = SettingsPanelView()
    host.show(content())
    host.resetInteraction(page: .settings)
    let body = host.scrollView.documentView as! PanelSectionView
    let group = host.control(named: "iconStyle") as! PanelIconStyleChoices
    let back = host.control(named: "back") as! PanelButton
    let explanation = body.subviews.compactMap { $0 as? NSTextField }.first { $0.accessibilityIdentifier() == "iconStyleExplanation" }!
    check(back.frame.minY == 16 && back.frame.minX + 3 == 16, "Settings breadcrumb has16pt top and visible leading gutter")
    check(group.frame.minX == 16 && host.preferredHeight - host.control(named: "clearHistory")!.frame.maxY == 16
          && host.control(named: "clearHistory")!.frame.minY > group.frame.maxY + 16,
          "five62pt previews retain16pt sides; separated Clear section has16pt bottom gutter")
    check(group.rows.count == 5 && group.rows.allSatisfy { $0.frame.height == 62 && group.bounds.contains($0.frame) },
          "all five preview frames are contained at native row height")
    check(explanation.frame.minX == group.frame.minX && explanation.frame.maxX == group.frame.maxX
          && explanation.frame.height >= explanation.intrinsicContentSize.height,
          "explanation is naturally measured within aligned358pt gutters")
    check(body.sectionHeaders.isEmpty && back.isNavigation && back.isLink,
          "Settings has no gray strip and breadcrumb stays borderless underline navigation")
    check(body.subviews.contains { $0 is NSImageView && $0.accessibilityIdentifier() == "breadcrumbSeparator" },
          "breadcrumb uses native chevron geometry rather than slash text")
    host.maximumHeight = 230
    host.navigate(to: .settings)
    group.revealSelectedRow()
    check(host.frame.height == 230 && host.scrollView.documentVisibleRect.height == 230,
          "short screen constrains viewport rather than shrinking previews")
    for appearance in [NSAppearance.Name.aqua, .darkAqua] {
        host.appearance = NSAppearance(named: appearance)
        if let directory = ProcessInfo.processInfo.environment["PANEL_SNAPSHOT_DIRECTORY"] {
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: directory)
                .appendingPathComponent("settings-constrained-\(appearance.rawValue).png"))
        }
    }
}

// Production footer geometry and moved exclusion callbacks, without live services.
do {
    let host = SettingsPanelView()
    var fixture = content()
    fixture.settings.ignoredApps = ["test.ignored"]
    fixture.appNames["test.ignored"] = "Synthetic app"
    var updates = 0
    var opened = 0
    var quits = 0
    host.actions.update = { change in
        change(&fixture.settings)
        updates += 1
        host.show(fixture)
    }
    host.actions.openPicker = { opened += 1 }
    host.actions.quit = { quits += 1 }
    host.show(fixture)
    let shortcuts = SettingsPanelView.hotkeyTitles.filter { $0.0 != .none }.map { Optional($0.1) } + [nil]
    for shortcut in shortcuts {
        fixture.hotkeyLabel = shortcut
        host.show(fixture)
        let buttons = ["settings", "openPicker", "quit"].map { host.control(named: $0) as! PanelButton }
        let footer = buttons[0].superview as! PanelSectionView
        check(buttons.allSatisfy { $0.superview === footer && $0.frame.midY == buttons[0].frame.midY
              && $0.frame.width == $0.preferredWidth && footer.bounds.contains($0.frame) },
              "all three footer actions share a row and fit full intrinsic labels at390pt")
        check(abs(buttons[0].frame.minX - (390 - buttons[2].frame.maxX)) < 0.01,
              "footer action group is horizontally centered")
        let dividers = footer.separators.filter { $0.width == 1 }
        check(dividers.count == 2, "footer has exactly two thin vertical separators")
        for index in 0..<2 {
            check(buttons[index].frame.maxX < dividers[index].minX
                  && dividers[index].maxX < buttons[index + 1].frame.minX
                  && dividers[index].midY == buttons[index].frame.midY,
                  "divider separates nonoverlapping footer controls with centered18pt rule")
        }
        check(buttons[1].title == "Open Picker" + (shortcut.map { "  \($0)" } ?? ""),
              "Open Picker preserves visible shortcut without truncation")
        check(host.controls.allSatisfy { !$0.partName.hasPrefix("ignored:") && $0.partName != "ignoreFrontmost" },
              "Main has no ignored-app hit, accessibility or focus entries")
        func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
        let all = descendants(host)
        check(!all.contains { element in
            ["import", "export"].contains(element.accessibilityIdentifier() ?? "")
                || ["Import", "Export", "Not implemented"].contains((element as? NSTextField)?.stringValue ?? "")
                || ["Import, Not implemented", "Export, Not implemented"].contains(element.accessibilityLabel() ?? "")
        }, "removed Import/Export leave no labels or accessibility descendants")
        check(buttons[0].isNavigation && buttons[0].isLink,
              "Settings keeps borderless navigation underline focus")
        check(buttons[1].accessibilityPerformPress() && buttons[2].accessibilityPerformPress(),
              "Open Picker and Quit invoke real accessible callbacks")
        check(buttons[0].accessibilityPerformPress() && host.page == .settings,
              "Settings accessible callback opens Settings")
        check(host.controls.map(\.partName) == ["back", "ignored:test.ignored", "ignoreFrontmost", "iconStyle", "clearHistory"],
              "Settings focus order places exclusions above Icon style")
        host.keyDown(with: key(48))
        check(host.focusedPart == "ignored:test.ignored", "Tab reaches first ignored app from breadcrumb")
        host.keyDown(with: key(49, " "))
        check(fixture.settings.ignoredApps.isEmpty, "Space unignores via production checkbox callback")
        let candidate = host.control(named: "ignoreFrontmost") as! PanelButton
        check(candidate.accessibilityPerformPress(), "frontmost app candidate has accessible action")
        check(fixture.settings.ignoredApps == ["net.kovidgoyal.kitty"], "candidate invokes real settings update callback")
        host.maximumHeight = 230
        host.moveFocus(by: -1)
        check(host.focusedPart == "clearHistory" && host.scrollView.documentVisibleRect.contains(host.control(named: "clearHistory")!.frame),
              "constrained Settings keyboard navigation scrolls to bottom Clear")
        host.navigate(to: .main)
        check(host.preferredHeight == 519 && host.frame.height == 230,
              "Main height is independent of moved ignored-app count, with bounded viewport")
        fixture.settings.ignoredApps = ["test.ignored"]
        host.maximumHeight = .greatestFiniteMagnitude
    }
    check(updates == shortcuts.count * 2 && opened == shortcuts.count && quits == shortcuts.count, "synthetic actions dispatch exactly once per activation")
}

// Synthetic-only publication evidence for Main and each Settings clear state.
do {
    let host = SettingsPanelView()
    var fixture = content()
    fixture.statistics?.clipCount = 142
    host.show(fixture)
    func snapshot(_ name: String, _ appearance: NSAppearance.Name) {
        host.appearance = NSAppearance(named: appearance)
        guard let directory = ProcessInfo.processInfo.environment["PANEL_SNAPSHOT_DIRECTORY"] else { return }
        let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: directory)
            .appendingPathComponent("clear-in-settings-\(name)-\(appearance.rawValue).png"))
    }
    for appearance in [NSAppearance.Name.aqua, .darkAqua] {
        host.maximumHeight = .greatestFiniteMagnitude
        host.resetInteraction()
        check(host.control(named: "clearHistory") == nil && host.control(named: "confirmDelete") == nil
              && !host.controls.contains { $0.accessibilityLabel()?.contains("Clear") == true },
              "Main has no Clear control, hit target, confirmation or accessibility action")
        snapshot("main", appearance)
        host.maximumHeight = 230
        host.moveFocus(by: -1)
        snapshot("main-constrained", appearance)
        host.maximumHeight = .greatestFiniteMagnitude
        host.navigate(to: .settings)
        snapshot("normal", appearance)
        (host.control(named: "clearHistory") as? PanelButton)?.press()
        snapshot("confirm", appearance)
        host.maximumHeight = 230
        host.show(fixture)
        check(host.focusedPart == "confirmCancel" && host.scrollView.documentVisibleRect.contains(
            host.control(named: "confirmCancel")!.frame), "constrained confirmation scroll reveals safe Cancel")
        snapshot("confirm-constrained", appearance)
        host.cancelConfirmation()
        fixture.statistics?.clipCount = 0
        host.show(fixture)
        host.maximumHeight = .greatestFiniteMagnitude
        snapshot("empty", appearance)
        host.maximumHeight = 230
        host.moveFocus(by: -1)
        snapshot("empty-constrained", appearance)
        fixture.statistics?.clipCount = 142
        host.show(fixture)
    }
}

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
