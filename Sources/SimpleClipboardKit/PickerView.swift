import AppKit

/// Draws the picker and turns key and mouse events into `PickerKey`s for the model. It draws its own rows and
/// prompt instead of using NSTableView and NSTextField, like noteapp's /import popup: the view is the only first
/// responder and the model decides what each key does.
final class PickerView: NSView {
    let model: PickerModel
    /// Called with the model's answer to a key or a double-click.
    var onAction: ((PickerAction) -> Void)?
    /// Called with the stable ID captured when the context menu was opened.
    var onRemoveClip: ((Int64) -> Void)?
    var onContentChanged: (() -> Void)?
    /// Loads the stored items of a clip for the separate preview.
    var loadItems: ((Int64) -> [[Representation]])?
    /// Loads a downsampled image representation for a visible row only.
    var loadThumbnail: ((Int64, Int) -> NSImage?)?
    var loadImageMetadata: ((Int64) -> ClipStore.ImageMetadata?)?
    private enum CachedImageMetadata { case value(ClipStore.ImageMetadata), unavailable }
    private var imageMetadataCache: [Int64: CachedImageMetadata] = [:]
    private var imageMetadataUseOrder: [Int64] = []
    /// Shown in the bar: "paste" or "copy", what recall does with the clip.
    var recallVerb = "paste"
    var now: () -> Date = Date.init
    var settings = Settings()

    private var previewCache: (id: Int64, preview: ClipPreview)?
    private struct ThumbnailKey: Hashable { var clipID: Int64; var pixels: Int }
    private enum CachedThumbnail { case image(NSImage), unavailable }
    private var thumbnailCache: [ThumbnailKey: CachedThumbnail] = [:]
    private var thumbnailUseOrder: [ThumbnailKey] = []
    static let thumbnailCacheLimit = 32
    private var scrollRemainder: CGFloat = 0
    private var mouseDownPoint: NSPoint?
    private var mouseDownFrame: NSRect?
    private var dragBegan = false
    private var pendingDoubleClick = false

    init(model: PickerModel) {
        self.model = model
        super.init(frame: NSRect(origin: .zero, size: InterfaceStyle.pickerSize))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var chrome: PickerChrome { PickerChrome(box: bounds, previewOpen: model.previewOpen) }

    /// Actual consecutive lines, including blank lines; nontext stays one compact metadata row.
    func contentLines(for clip: ClipSummary) -> [String] {
        if clip.kind == "image", let metadata = imageMetadata(for: clip.id) {
            let lines = ["Image (\(metadata.format))", "\(metadata.width)×\(metadata.height) · \(Format.bytes(metadata.byteCount))"]
            return Array(lines.prefix(settings.pickerContentLines))
        }
        guard !clip.contentPreview.isEmpty else { return [clip.preview] }
        return Array(clip.contentPreview.components(separatedBy: "\n").prefix(settings.pickerContentLines))
    }

    func rowHeight(at index: Int) -> CGFloat {
        if case .filters = model.step { return InterfaceStyle.rowHeight }
        guard model.rows.indices.contains(index) else { return InterfaceStyle.rowHeight }
        let clip = model.rows[index]
        let lineCount = clip.kind == "image" ? min(settings.pickerContentLines, 2) : contentLines(for: clip).count
        let textHeight = CGFloat(lineCount) * InterfaceStyle.lineHeight + CGFloat(settings.pickerDensity * 2)
        return clip.kind == "image" ? max(textHeight, 40) : textHeight
    }

    /// Shared geometry for drawing, pointer hit testing, keyboard paging and accessibility.
    var visibleRows: [(index: Int, rect: NSRect)] {
        let first = model.step == .clips ? model.firstRow : model.firstFilterRow
        let count = model.step == .clips ? model.rows.count : model.filterRows.count
        var y = chrome.listRect.minY
        var result: [(Int, NSRect)] = []
        for index in first..<max(first, count) {
            let height = rowHeight(at: index)
            guard result.count < settings.maximumVisibleItems, y + height <= chrome.listRect.maxY else { break }
            result.append((index, NSRect(x: 1, y: y, width: bounds.width - 2, height: height)))
            y += height
        }
        return result
    }

    static var compactHeight: CGFloat {
        ceil(InterfaceStyle.lineHeight + CGFloat(Settings.pickerDensityChoices.min()! * 2)
             + PickerChrome(box: .zero).barHeight + InterfaceStyle.gap)
    }

    /// Content height is a cap, never a fixed empty window. Reserve preview space only when requested.
    func desiredHeight(cap: CGFloat, screenHeight: CGFloat) -> CGFloat {
        let count = model.step == .clips ? model.rows.count : model.filterRows.count
        let heights = (0..<count).map { rowHeight(at: $0) }
        // Use the tallest page so moving through variable rows does not resize the window.
        let body = heights.sorted(by: >).prefix(settings.maximumVisibleItems).reduce(0, +)
        let empty = InterfaceStyle.lineHeight + CGFloat(settings.pickerDensity * 2)
        let chromeHeight = chrome.barHeight + InterfaceStyle.gap
        let content = max(empty, body) + chromeHeight + (model.previewOpen ? 180 : 0)
        return min(max(content, minimumContentHeight), max(cap, minimumContentHeight), screenHeight)
    }

    var minimumContentHeight: CGFloat {
        let count = model.step == .clips ? model.rows.count : model.filterRows.count
        let tallest = (0..<count).map { rowHeight(at: $0) }.max()
            ?? (InterfaceStyle.lineHeight + CGFloat(settings.pickerDensity * 2))
        return ceil(tallest * (model.previewOpen ? 3 : 1) + chrome.barHeight + InterfaceStyle.gap + (model.previewOpen ? InterfaceStyle.rowHeight * 3 : 0))
    }

    func updateRowCount() {
        model.showPasteSpecial = settings.showPasteSpecial
        model.maximumVisibleItems = settings.maximumVisibleItems
        model.rowHeight = { [weak self] in Double(self?.rowHeight(at: $0) ?? 1) }
        model.viewportHeight = Double(chrome.listRect.height)
        model.updateViewport()
    }

    override func layout() {
        super.layout()
        updateRowCount()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateRowCount()
        needsDisplay = true
    }

    // MARK: drawing

    override func draw(_ dirtyRect: NSRect) {
        let chrome = self.chrome
        chrome.draw()
        if case .filters = model.step {
            drawFilterRows(in: chrome.listRect)
            drawBar(in: chrome.barRect)
            return
        }
        drawRows(in: chrome.listRect)
        if model.previewOpen { drawPreview(in: chrome.previewRect) }
        drawBar(in: chrome.barRect)
    }

    private func drawRows(in rect: NSRect) {
        let liveIDs = Set(model.rows.map(\.id))
        imageMetadataUseOrder.removeAll { id in
            if !liveIDs.contains(id) { imageMetadataCache.removeValue(forKey: id); return true }
            return false
        }
        thumbnailUseOrder.removeAll { key in
            if !liveIDs.contains(key.clipID) { thumbnailCache.removeValue(forKey: key); return true }
            return false
        }
        let gap = InterfaceStyle.gap
        let rowHeight = InterfaceStyle.rowHeight
        if model.rows.isEmpty {
            let message = model.query.isEmpty ? "No clips yet" : "No clips match"
            InterfaceStyle.draw(message, in: NSRect(x: rect.minX + gap, y: rect.minY, width: rect.width - gap * 2, height: rowHeight),
                             color: .secondaryLabelColor)
            return
        }
        for (position, entry) in visibleRows.enumerated() {
            let index = entry.index, row = entry.rect
            let clip = model.rows[index]
            let selected = index == model.selectedIndex
            let foreground = Self.rowForeground(selected: selected)
            if selected { InterfaceStyle.selectionFill(row) }
            else {
                NSColor.separatorColor.setFill()
                Self.rowDivider(in: row).fill()
            }
            var textX = row.minX + gap
            let numberWidth: CGFloat = 16
            if position < 9 {
                InterfaceStyle.draw("\(position + 1)", in: NSRect(x: row.maxX - gap - numberWidth, y: row.minY, width: numberWidth, height: row.height),
                                    font: InterfaceStyle.smallFont, color: selected ? foreground : .secondaryLabelColor, alignment: .right)
            }
            if clip.kind == "image", let thumbnail = thumbnail(for: clip.id, pixelSize: 36) {
                let imageRect = Self.aspectFitRect(for: thumbnail.size, in: NSRect(x: textX, y: row.midY - 16, width: 32, height: 32))
                thumbnail.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1,
                               respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
                textX += 42
            } else if settings.showTypeIcons {
                let symbolRect = Self.typeSymbolRect(in: row, x: textX, density: settings.pickerDensity)
                InterfaceStyle.drawSymbol(Self.symbolName(for: clip), in: symbolRect, color: foreground)
                textX += symbolRect.width + 10
            }
            let detail = settings.showTimestamps ? Self.rowDetail(clip, now: now()) : ""
            let detailWidth = min(row.width / 3, InterfaceStyle.width(of: detail, font: InterfaceStyle.smallFont))
            InterfaceStyle.draw(detail, in: NSRect(x: row.maxX - gap * 2 - numberWidth - detailWidth, y: row.minY,
                                width: detailWidth, height: row.height), font: InterfaceStyle.smallFont,
                                color: selected ? foreground : .secondaryLabelColor, alignment: .right)
            for (line, text) in contentLines(for: clip).enumerated() {
                let textRect = NSRect(x: textX, y: row.minY + CGFloat(settings.pickerDensity) + CGFloat(line) * InterfaceStyle.lineHeight,
                                      width: max(0, row.maxX - gap * 3 - numberWidth - detailWidth - textX), height: InterfaceStyle.lineHeight)
                if line == 0 {
                    InterfaceStyle.draw(text, in: textRect, font: .systemFont(ofSize: InterfaceStyle.font.pointSize, weight: .semibold), color: foreground)
                } else {
                    InterfaceStyle.draw(text, in: textRect, font: InterfaceStyle.smallFont, color: selected ? foreground : .secondaryLabelColor)
                }
            }
        }
    }

    /// Type symbols scale with picker density while retaining vertical insets in compact rows.
    static func typeSymbolRect(in row: NSRect, x: CGFloat, density: Int) -> NSRect {
        let requestedSize: CGFloat
        switch density {
        case 4: requestedSize = 22
        case 7: requestedSize = 26
        case 10: requestedSize = 30
        default: requestedSize = 26
        }
        let size = min(requestedSize, max(0, row.height - 2))
        return NSRect(x: x, y: row.midY - size / 2, width: size, height: size)
    }

    private func drawFilterRows(in rect: NSRect) {
        let gap = InterfaceStyle.gap
        let rowHeight = InterfaceStyle.rowHeight
        if model.filterRows.isEmpty {
            InterfaceStyle.draw("No filters match", in: NSRect(x: rect.minX + gap, y: rect.minY, width: rect.width - gap * 2,
                                                               height: rowHeight), color: .secondaryLabelColor)
            return
        }
        for entry in visibleRows {
            let index = entry.index
            let row = entry.rect
            switch model.filterRows[index] {
            case .heading(let group):
                InterfaceStyle.draw(group.rawValue, in: row.insetBy(dx: gap, dy: 0), font: InterfaceStyle.smallFont,
                                    color: .secondaryLabelColor)
            case .filter(let filter):
                let selected = index == model.selectedFilterIndex
                let foreground = Self.rowForeground(selected: selected)
                if selected { InterfaceStyle.selectionFill(row) }
                let summaryWidth = min(InterfaceStyle.width(of: filter.summary, font: InterfaceStyle.smallFont), row.width / 2)
                InterfaceStyle.draw(filter.summary, in: NSRect(x: row.maxX - gap - summaryWidth, y: row.minY, width: summaryWidth,
                                                               height: rowHeight),
                                    font: InterfaceStyle.smallFont, color: selected ? foreground : .tertiaryLabelColor, alignment: .right)
                let textX = row.minX + gap * 2
                InterfaceStyle.draw(filter.name, highlighting: model.filterQuery, in: NSRect(x: textX, y: row.minY,
                                                            width: max(0, row.maxX - gap * 2 - summaryWidth - textX), height: rowHeight),
                                    color: foreground)
            }
        }
    }

    private func imageMetadata(for clipID: Int64) -> ClipStore.ImageMetadata? {
        if let cached = imageMetadataCache[clipID] {
            touchImageMetadata(clipID)
            if case .value(let metadata) = cached { return metadata }
            return nil
        }
        let cached = loadImageMetadata?(clipID).map(CachedImageMetadata.value) ?? .unavailable
        imageMetadataCache[clipID] = cached
        touchImageMetadata(clipID)
        while imageMetadataUseOrder.count > Self.thumbnailCacheLimit {
            imageMetadataCache.removeValue(forKey: imageMetadataUseOrder.removeFirst())
        }
        if case .value(let metadata) = cached { return metadata }
        return nil
    }

    private func touchImageMetadata(_ clipID: Int64) {
        imageMetadataUseOrder.removeAll { $0 == clipID }
        imageMetadataUseOrder.append(clipID)
    }

    /// Visible-row thumbnail lookup with a strict per-view LRU bound.
    func thumbnail(for clipID: Int64, pixelSize: Int) -> NSImage? {
        let key = ThumbnailKey(clipID: clipID, pixels: pixelSize)
        if let cached = thumbnailCache[key] {
            touchThumbnail(key)
            if case .image(let image) = cached { return image }
            return nil
        }
        let loaded = loadThumbnail?(clipID, pixelSize).map(CachedThumbnail.image) ?? .unavailable
        thumbnailCache[key] = loaded
        touchThumbnail(key)
        while thumbnailUseOrder.count > Self.thumbnailCacheLimit {
            thumbnailCache.removeValue(forKey: thumbnailUseOrder.removeFirst())
        }
        if case .image(let image) = loaded { return image }
        return nil
    }

    private func touchThumbnail(_ key: ThumbnailKey) {
        thumbnailUseOrder.removeAll { $0 == key }
        thumbnailUseOrder.append(key)
    }

    func resetThumbnailCache() {
        thumbnailCache.removeAll(keepingCapacity: true)
        thumbnailUseOrder.removeAll(keepingCapacity: true)
        imageMetadataCache.removeAll(keepingCapacity: true)
        imageMetadataUseOrder.removeAll(keepingCapacity: true)
    }

    static func aspectFitRect(for imageSize: NSSize, in slot: NSRect) -> NSRect {
        guard imageSize.width > 0, imageSize.height > 0, slot.width > 0, slot.height > 0 else { return .zero }
        let scale = min(slot.width / imageSize.width, slot.height / imageSize.height)
        let size = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return NSRect(x: slot.midX - size.width / 2, y: slot.midY - size.height / 2, width: size.width, height: size.height)
    }

    var cachedThumbnailCount: Int { thumbnailCache.count }

    static func rowDivider(in row: NSRect) -> NSRect {
        NSRect(x: row.minX + InterfaceStyle.gap, y: row.maxY - 1, width: row.width - InterfaceStyle.gap * 2, height: 1)
    }

    /// Symbols use only the bounded summary, never loading stored representations while drawing rows.
    static func symbolName(for clip: ClipSummary) -> String {
        if clip.kind == "image" { return "photo" }
        if clip.kind == "files" { return "doc.on.doc" }
        let firstLine = (clip.contentPreview.isEmpty ? clip.preview : clip.contentPreview).prefix(2048)
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        if let url = URL(string: firstLine.trimmingCharacters(in: .whitespaces)),
           ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil { return "link" }
        return "doc.text"
    }

    /// Custom-drawn rows must explicitly use the system's selected foreground over blue selection.
    static func rowForeground(selected: Bool) -> NSColor {
        selected ? .alternateSelectedControlTextColor : .labelColor
    }

    /// The right-hand detail of a row: age, and the source app when known.
    static func rowDetail(_ clip: ClipSummary, now: Date) -> String {
        var detail = Format.age(from: clip.lastCopiedAt, to: now)
        if let app = clip.sourceAppName { detail += "  " + String(app.prefix(16)) }
        return detail
    }

    private func drawPreview(in rect: NSRect) {
        guard let clip = model.selectedClip else { return }
        let preview: ClipPreview
        if let cache = previewCache, cache.id == clip.id {
            preview = cache.preview
        } else {
            preview = ClipPreview.make(from: loadItems?(clip.id) ?? [])
            previewCache = (clip.id, preview)
        }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        switch preview {
        case .text(let text):
            drawText(text, in: rect)
        case .files(let paths):
            drawText(paths.joined(separator: "\n"), in: rect)
        case .other(let types):
            drawText("No preview. Types:\n" + types, in: rect, color: .secondaryLabelColor)
        case .image(let image):
            let size = image.size
            guard size.width > 0, size.height > 0 else { break }
            let scale = min(1, rect.width / size.width, rect.height / size.height)
            let drawn = NSSize(width: floor(size.width * scale), height: floor(size.height * scale))
            image.draw(in: NSRect(x: rect.minX, y: rect.minY, width: drawn.width, height: drawn.height),
                       from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawText(_ text: String, in rect: NSRect, color: NSColor = .labelColor) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byCharWrapping
        (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                attributes: [.font: InterfaceStyle.font, .foregroundColor: color, .paragraphStyle: style])
    }

    private func drawBar(in rect: NSRect) {
        let gap = InterfaceStyle.gap
        let hints = barHints
        let hintsWidth = min(InterfaceStyle.width(of: hints, font: InterfaceStyle.smallFont), rect.width)
        InterfaceStyle.draw(hints, in: NSRect(x: rect.maxX - hintsWidth, y: rect.minY, width: hintsWidth, height: rect.height),
                            font: InterfaceStyle.smallFont, color: .secondaryLabelColor, alignment: .right)
        let statusWidth = max(0, rect.width - hintsWidth - gap)
        let status = Self.tail(of: barStatus, fitting: statusWidth, font: InterfaceStyle.smallFont)
        InterfaceStyle.draw(status, in: NSRect(x: rect.minX, y: rect.minY, width: statusWidth, height: rect.height),
                            font: InterfaceStyle.smallFont, color: .secondaryLabelColor)
    }

    /// The left of the bar: the count, and the typed text when there is some. There is no input field.
    var barStatus: String {
        switch model.step {
        case .clips:
            let count = model.rows.count
            let shown = count >= PickerModel.resultLimit ? "\(count.formatted())+" : count.formatted()
            if model.query.isEmpty { return "" }
            return "\(shown) matching \"\(model.query)\""
        case .filters:
            let count = model.filterRows.filter { if case .filter = $0 { return true } else { return false } }.count
            if model.filterQuery.isEmpty { return "" }
            return "\(count) filters matching \"\(model.filterQuery)\""
        }
    }

    /// The key hints at the right of the bar. "plain" and "formatted" swap with Always Paste Plain Text.
    var barHints: String {
        if case .filters = model.step { return "\u{21A9} \(recallVerb)  esc back" }
        let main = "\u{21A9} \(recallVerb)\(model.alwaysPastePlainText ? " plain" : "")"
        let special = settings.showPasteSpecial ? "  \u{21E7}\u{21A9} \(model.alwaysPastePlainText ? "formatted" : "plain")" : ""
        let escape = model.previewOpen ? "back" : model.query.isEmpty ? "close" : "clear"
        let extras = bounds.width >= 560 ? "  ⌘↩ filter  tab preview" : ""
        return "\(main)\(special)\(extras)  esc \(escape)"
    }

    /// The end of the text that fits the width, so the end of a long query stays visible.
    static func tail(of text: String, fitting width: CGFloat, font: NSFont = InterfaceStyle.font) -> String {
        guard InterfaceStyle.width(of: text, font: font) > width else { return text }
        var shown = Substring(text)
        while !shown.isEmpty && InterfaceStyle.width(of: "\u{2026}" + shown, font: font) > width { shown = shown.dropFirst() }
        return "\u{2026}" + shown
    }

    // MARK: keys and mouse

    override func keyDown(with event: NSEvent) {
        guard let key = Self.pickerKey(for: event) else { super.keyDown(with: event); return }
        perform(key)
    }

    /// Key equivalents (Cmd-digit) reach the view here before keyDown.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, let key = Self.pickerKey(for: event) else { return false }
        perform(key)
        return true
    }

    func perform(_ key: PickerKey) {
        model.showPasteSpecial = settings.showPasteSpecial
        let action = model.handle(key)
        onContentChanged?()
        updateRowCount()
        NSAccessibility.post(element: self, notification: .selectedChildrenChanged)
        needsDisplay = true
        if action != .none { onAction?(action) }
    }

    static func pickerKey(for event: NSEvent) -> PickerKey? {
        guard event.type == .keyDown else { return nil }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch event.keyCode {
        case 126: return .up
        case 125: return .down
        case 116: return .pageUp
        case 121: return .pageDown
        case 115: return .home
        case 119: return .end
        case 36, 76:
            if flags == .command { return .enterFilter }
            if flags == .shift { return .enterAlternate }
            return .enter
        case 53: return .escape
        case 48: return .tab
        case 51:
            if flags.contains(.command) { return .clearQuery }
            if flags.contains(.option) { return .deleteWordBackward }
            return .deleteBackward
        default: break
        }
        let plain = event.charactersIgnoringModifiers ?? ""
        if flags == .command {
            if let digit = Int(plain), (1...9).contains(digit) { return .recallNumber(digit) }
            if plain == "w" { return .escape }
            return nil
        }
        if flags == .control {
            switch plain {
            case "n": return .down
            case "p": return .up
            case "g": return .escape
            case "u": return .clearQuery
            default: return nil
            }
        }
        if flags.contains(.command) || flags.contains(.control) { return nil }
        guard let characters = event.characters, !characters.isEmpty else { return nil }
        return .text(characters)
    }

    /// The clip row (or in the filter step, the filter list row) under a point.
    func rowIndex(at point: NSPoint) -> Int? {
        guard let entry = visibleRows.first(where: { $0.rect.contains(point) }) else { return nil }
        if case .filters = model.step, case .heading = model.filterRows[entry.index] { return nil }
        return entry.index
    }

    override func isAccessibilityElement() -> Bool { false }
    override func accessibilityRole() -> NSAccessibility.Role? { .list }
    override func accessibilityLabel() -> String? { "Clipboard history" }
    override func accessibilityChildren() -> [Any]? {
        visibleRows.compactMap { entry -> PickerAccessibilityRow? in
            let label: String
            let selected: Bool
            switch model.step {
            case .clips:
                let clip = model.rows[entry.index]
                label = contentLines(for: clip).joined(separator: "\n") + ", " + clip.kind
                selected = entry.index == model.selectedIndex
            case .filters:
                guard case .filter(let filter) = model.filterRows[entry.index] else { return nil }
                label = filter.name + ", " + filter.summary
                selected = entry.index == model.selectedFilterIndex
            }
            let row = PickerAccessibilityRow()
            row.setAccessibilityParent(self)
            row.setAccessibilityRole(.row)
            row.setAccessibilityLabel(label)
            row.setAccessibilitySelected(selected)
            if let window { row.setAccessibilityFrame(window.convertToScreen(convert(entry.rect, to: nil))) }
            row.press = { [weak self] in
                guard let self else { return }
                self.model.select(entry.index)
                self.perform(.enter)
            }
            return row
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        contextMenu(at: convert(event.locationInWindow, from: nil))
    }

    /// Returns a native context menu only for a visible clip row, never filter/footer/empty space.
    func contextMenu(at point: NSPoint) -> NSMenu? {
        guard case .clips = model.step, let index = rowIndex(at: point), model.rows.indices.contains(index) else { return nil }
        model.select(index)
        needsDisplay = true
        let id = model.rows[index].id
        let menu = NSMenu()
        let item = NSMenuItem(title: "Remove from history", action: #selector(removeContextClip(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = NSNumber(value: id)
        menu.addItem(item)
        return menu
    }

    @objc private func removeContextClip(_ sender: NSMenuItem) {
        guard let number = sender.representedObject as? NSNumber else { return }
        onRemoveClip?(number.int64Value)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard Self.canBeginWindowDrag(at: point, in: bounds) else { return }
        mouseDownPoint = window?.convertPoint(toScreen: event.locationInWindow)
        mouseDownFrame = window?.frame
        dragBegan = false
        pendingDoubleClick = false
        if let index = rowIndex(at: point) {
            model.select(index)
            pendingDoubleClick = event.clickCount >= 2
            needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let startPoint = mouseDownPoint, let startFrame = mouseDownFrame else { return }
        let point = window.convertPoint(toScreen: event.locationInWindow)
        let dx = point.x - startPoint.x, dy = point.y - startPoint.y
        if !dragBegan {
            guard Self.shouldBeginWindowDrag(from: startPoint, to: point) else { return }
            dragBegan = true
            pendingDoubleClick = false
        }
        window.setFrameOrigin(NSPoint(x: startFrame.minX + dx, y: startFrame.minY + dy))
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownPoint = nil; mouseDownFrame = nil; dragBegan = false }
        if pendingDoubleClick && !dragBegan { perform(.enter) }
        pendingDoubleClick = false
    }

    static let windowDragThreshold: CGFloat = 4

    /// Corner resize views are layered over these edge areas; they retain priority over window dragging.
    static func canBeginWindowDrag(at point: NSPoint, in bounds: NSRect) -> Bool {
        guard bounds.contains(point) else { return false }
        let corner = WindowCornerView.size
        let inCorner = (point.x < corner || point.x >= bounds.maxX - corner)
            && (point.y < corner || point.y >= bounds.maxY - corner)
        return !inCorner
    }

    static func shouldBeginWindowDrag(from start: NSPoint, to current: NSPoint) -> Bool {
        hypot(current.x - start.x, current.y - start.y) >= windowDragThreshold
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / InterfaceStyle.rowHeight : event.scrollingDeltaY
        scrollRemainder -= delta
        let rows = Int(scrollRemainder.rounded(.towardZero))
        guard rows != 0 else { return }
        scrollRemainder -= CGFloat(rows)
        model.scroll(by: rows)
        needsDisplay = true
    }
}

/// Press recalls the row, matching a double-click; selection is exposed independently.
private final class PickerAccessibilityRow: NSAccessibilityElement {
    var press: (() -> Void)?
    override func accessibilityPerformPress() -> Bool { press?(); return press != nil }
}
