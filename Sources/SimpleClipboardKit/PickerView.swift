import AppKit

/// Draws the picker and turns key and mouse events into `PickerKey`s for the model. It draws its own rows and
/// prompt instead of using NSTableView and NSTextField, like noteapp's /import popup: the view is the only first
/// responder and the model decides what each key does.
final class PickerView: NSView {
    let model: PickerModel
    /// Called with the model's answer to a key or a double-click.
    var onAction: ((PickerAction) -> Void)?
    /// Loads the stored items of a clip for the preview.
    var loadItems: ((Int64) -> [[Representation]])?
    /// Shown in the bar: "paste" or "copy", what recall does with the clip.
    var recallVerb = "paste"
    var now: () -> Date = Date.init

    private var previewCache: (id: Int64, preview: ClipPreview)?
    private var scrollRemainder: CGFloat = 0

    init(model: PickerModel) {
        self.model = model
        super.init(frame: NSRect(origin: .zero, size: InterfaceStyle.pickerSize))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var chrome: PickerChrome { PickerChrome(box: bounds, previewOpen: model.previewOpen) }

    /// Tells the model how many rows fit. Call after a size or preview change.
    func updateRowCount() {
        model.visibleRowCount = max(1, Int(floor(chrome.listRect.height / InterfaceStyle.rowHeight)))
    }

    override func layout() {
        super.layout()
        updateRowCount()
    }

    // MARK: drawing

    override func draw(_ dirtyRect: NSRect) {
        let chrome = self.chrome
        if case .filters = model.step {
            let clipPreview = model.selectedClip?.preview ?? ""
            chrome.draw(title: "Filter", detail: clipPreview)
            drawFilterRows(in: chrome.listRect)
            drawBar(in: chrome.barRect)
            return
        }
        let count = model.rows.count
        let detail = model.query.isEmpty ? "\(count.formatted()) clips" : "\(count.formatted()) matching"
        chrome.draw(title: "Clipboard", detail: count >= PickerModel.resultLimit ? "\(detail)+" : detail)
        drawRows(in: chrome.listRect)
        if model.previewOpen { drawPreview(in: chrome.previewRect) }
        drawBar(in: chrome.barRect)
    }

    private func drawRows(in rect: NSRect) {
        let gap = InterfaceStyle.gap
        let rowHeight = InterfaceStyle.rowHeight
        if model.rows.isEmpty {
            let message = model.query.isEmpty ? "No clips yet" : "No clips match"
            InterfaceStyle.draw(message, in: NSRect(x: rect.minX + gap, y: rect.minY, width: rect.width - gap * 2, height: rowHeight),
                             color: .secondaryLabelColor)
            return
        }
        let numberWidth = InterfaceStyle.width(of: "9", font: InterfaceStyle.smallFont)
        for position in 0..<model.visibleRowCount {
            let index = model.firstRow + position
            guard index < model.rows.count else { break }
            let clip = model.rows[index]
            let row = NSRect(x: rect.minX, y: rect.minY + CGFloat(position) * rowHeight, width: rect.width, height: rowHeight)
            if index == model.selectedIndex { InterfaceStyle.selectionFill(row) }
            if position < 9 {
                InterfaceStyle.draw("\(position + 1)", in: NSRect(x: row.minX + gap, y: row.minY, width: numberWidth, height: rowHeight),
                                 font: InterfaceStyle.smallFont, color: .tertiaryLabelColor)
            }
            let detail = Self.rowDetail(clip, now: now())
            let detailWidth = InterfaceStyle.width(of: detail, font: InterfaceStyle.smallFont)
            InterfaceStyle.draw(detail, in: NSRect(x: row.maxX - gap - detailWidth, y: row.minY, width: detailWidth, height: rowHeight),
                             font: InterfaceStyle.smallFont, color: .tertiaryLabelColor, alignment: .right)
            let textX = row.minX + gap * 2 + numberWidth
            InterfaceStyle.draw(clip.preview, in: NSRect(x: textX, y: row.minY, width: max(0, row.maxX - gap * 2 - detailWidth - textX),
                                                      height: rowHeight))
        }
    }

    private func drawFilterRows(in rect: NSRect) {
        let gap = InterfaceStyle.gap
        let rowHeight = InterfaceStyle.rowHeight
        if model.filterRows.isEmpty {
            InterfaceStyle.draw("No filters match", in: NSRect(x: rect.minX + gap, y: rect.minY, width: rect.width - gap * 2,
                                                               height: rowHeight), color: .secondaryLabelColor)
            return
        }
        for position in 0..<model.visibleRowCount {
            let index = model.firstFilterRow + position
            guard index < model.filterRows.count else { break }
            let row = NSRect(x: rect.minX, y: rect.minY + CGFloat(position) * rowHeight, width: rect.width, height: rowHeight)
            switch model.filterRows[index] {
            case .heading(let group):
                InterfaceStyle.draw(group.rawValue, in: row.insetBy(dx: gap, dy: 0), font: InterfaceStyle.smallFont,
                                    color: .secondaryLabelColor)
            case .filter(let filter):
                if index == model.selectedFilterIndex { InterfaceStyle.selectionFill(row) }
                let summaryWidth = min(InterfaceStyle.width(of: filter.summary, font: InterfaceStyle.smallFont), row.width / 2)
                InterfaceStyle.draw(filter.summary, in: NSRect(x: row.maxX - gap - summaryWidth, y: row.minY, width: summaryWidth,
                                                               height: rowHeight),
                                    font: InterfaceStyle.smallFont, color: .tertiaryLabelColor, alignment: .right)
                let textX = row.minX + gap * 2
                InterfaceStyle.draw(filter.name, in: NSRect(x: textX, y: row.minY,
                                                            width: max(0, row.maxX - gap * 2 - summaryWidth - textX), height: rowHeight))
            }
        }
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
        let hintsWidth = min(InterfaceStyle.width(of: hints, font: InterfaceStyle.smallFont), rect.width * 0.7)
        InterfaceStyle.draw(hints, in: NSRect(x: rect.maxX - hintsWidth, y: rect.minY, width: hintsWidth, height: rect.height),
                         font: InterfaceStyle.smallFont, color: .tertiaryLabelColor, alignment: .right)
        let prompt = ":"
        let promptWidth = InterfaceStyle.width(of: prompt)
        InterfaceStyle.draw(prompt, in: NSRect(x: rect.minX, y: rect.minY, width: promptWidth, height: rect.height),
                         color: .secondaryLabelColor)
        let queryX = rect.minX + promptWidth + gap / 2
        let queryMaxWidth = max(0, rect.maxX - hintsWidth - gap - queryX)
        let query = model.step == .clips ? model.query : model.filterQuery
        let shown = Self.tail(of: query, fitting: queryMaxWidth - 2)
        if shown.isEmpty {
            InterfaceStyle.draw(model.step == .clips ? "search" : "filter", in: NSRect(x: queryX + 3, y: rect.minY, width: queryMaxWidth, height: rect.height),
                             color: .tertiaryLabelColor)
        } else {
            InterfaceStyle.draw(shown, in: NSRect(x: queryX, y: rect.minY, width: queryMaxWidth, height: rect.height))
        }
        // A bar cursor after the query.
        let cursorX = queryX + (shown.isEmpty ? 0 : InterfaceStyle.width(of: shown)) + 1
        NSColor.labelColor.setFill()
        NSRect(x: cursorX, y: rect.minY + 3, width: 2, height: rect.height - 6).fill()
    }

    /// The key hints at the right of the bar. "plain" and "formatted" swap with Always Paste Plain Text.
    var barHints: String {
        if case .filters = model.step { return "\u{21A9} \(recallVerb)  esc back" }
        let alternate = model.alwaysPastePlainText ? "formatted" : "plain"
        let main = "\u{21A9} \(recallVerb)\(model.alwaysPastePlainText ? " plain" : "")  \u{21E7}\u{21A9} \(alternate)  \u{2318}\u{21A9} filter"
        if model.previewOpen, let clip = model.selectedClip {
            return "\(clip.kind), \(Format.bytes(clip.byteSize))  \(main)  esc back"
        }
        return "\(main)  tab preview  esc close"
    }

    /// The end of the text that fits the width, so the end of a long query stays visible.
    static func tail(of text: String, fitting width: CGFloat) -> String {
        var shown = Substring(text)
        while !shown.isEmpty && InterfaceStyle.width(of: String(shown)) > width { shown = shown.dropFirst() }
        return String(shown)
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
        let action = model.handle(key)
        updateRowCount()
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
        let rect = chrome.listRect
        guard rect.contains(point) else { return nil }
        let offset = Int(floor((point.y - rect.minY) / InterfaceStyle.rowHeight))
        switch model.step {
        case .clips:
            let index = model.firstRow + offset
            return index < model.rows.count ? index : nil
        case .filters:
            let index = model.firstFilterRow + offset
            guard index < model.filterRows.count, case .filter = model.filterRows[index] else { return nil }
            return index
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let index = rowIndex(at: convert(event.locationInWindow, from: nil)) else { return }
        model.select(index)
        needsDisplay = true
        if event.clickCount >= 2 { perform(.enter) }
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
