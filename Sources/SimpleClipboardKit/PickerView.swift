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
    /// Shown in the bar: what Return does.
    var returnHint = "copy"
    var now: () -> Date = Date.init

    private var previewCache: (id: Int64, preview: ClipPreview)?
    private var scrollRemainder: CGFloat = 0

    init(model: PickerModel) {
        self.model = model
        super.init(frame: NSRect(origin: .zero, size: PickerStyle.boxSize))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var chrome: PickerChrome { PickerChrome(box: bounds, previewOpen: model.previewOpen) }

    /// Tells the model how many rows fit. Call after a size or preview change.
    func updateRowCount() {
        model.visibleRowCount = max(1, Int(floor(chrome.listRect.height / PickerStyle.rowHeight)))
    }

    override func layout() {
        super.layout()
        updateRowCount()
    }

    // MARK: drawing

    override func draw(_ dirtyRect: NSRect) {
        let chrome = self.chrome
        let count = model.rows.count
        let detail = model.query.isEmpty ? "\(count.formatted()) clips" : "\(count.formatted()) matching"
        chrome.draw(title: "Clipboard", detail: count >= PickerModel.resultLimit ? "\(detail)+" : detail)
        drawRows(in: chrome.listRect)
        if model.previewOpen { drawPreview(in: chrome.previewRect) }
        drawBar(in: chrome.barRect)
    }

    private func drawRows(in rect: NSRect) {
        let gap = PickerStyle.gap
        let rowHeight = PickerStyle.rowHeight
        if model.rows.isEmpty {
            let message = model.query.isEmpty ? "No clips yet" : "No clips match"
            PickerStyle.draw(message, in: NSRect(x: rect.minX + gap, y: rect.minY, width: rect.width - gap * 2, height: rowHeight),
                             color: .secondaryLabelColor)
            return
        }
        let numberWidth = PickerStyle.width(of: "9", font: PickerStyle.smallFont)
        for position in 0..<model.visibleRowCount {
            let index = model.firstRow + position
            guard index < model.rows.count else { break }
            let clip = model.rows[index]
            let row = NSRect(x: rect.minX, y: rect.minY + CGFloat(position) * rowHeight, width: rect.width, height: rowHeight)
            if index == model.selectedIndex { PickerStyle.selectionFill(row) }
            if position < 9 {
                PickerStyle.draw("\(position + 1)", in: NSRect(x: row.minX + gap, y: row.minY, width: numberWidth, height: rowHeight),
                                 font: PickerStyle.smallFont, color: .tertiaryLabelColor)
            }
            let detail = Self.rowDetail(clip, now: now())
            let detailWidth = PickerStyle.width(of: detail, font: PickerStyle.smallFont)
            PickerStyle.draw(detail, in: NSRect(x: row.maxX - gap - detailWidth, y: row.minY, width: detailWidth, height: rowHeight),
                             font: PickerStyle.smallFont, color: .tertiaryLabelColor, alignment: .right)
            let textX = row.minX + gap * 2 + numberWidth
            PickerStyle.draw(clip.preview, in: NSRect(x: textX, y: row.minY, width: max(0, row.maxX - gap * 2 - detailWidth - textX),
                                                      height: rowHeight))
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
                                attributes: [.font: PickerStyle.font, .foregroundColor: color, .paragraphStyle: style])
    }

    private func drawBar(in rect: NSRect) {
        let gap = PickerStyle.gap
        var hints = "Return \(returnHint)  Tab preview  Esc close"
        if model.previewOpen, let clip = model.selectedClip {
            hints = "\(clip.kind), \(Format.bytes(clip.byteSize))  Return \(returnHint)  Esc back"
        }
        let hintsWidth = min(PickerStyle.width(of: hints, font: PickerStyle.smallFont), rect.width / 2)
        PickerStyle.draw(hints, in: NSRect(x: rect.maxX - hintsWidth, y: rect.minY, width: hintsWidth, height: rect.height),
                         font: PickerStyle.smallFont, color: .tertiaryLabelColor, alignment: .right)
        let prompt = ":"
        let promptWidth = PickerStyle.width(of: prompt)
        PickerStyle.draw(prompt, in: NSRect(x: rect.minX, y: rect.minY, width: promptWidth, height: rect.height),
                         color: .secondaryLabelColor)
        let queryX = rect.minX + promptWidth + gap / 2
        let queryMaxWidth = max(0, rect.maxX - hintsWidth - gap - queryX)
        let shown = Self.tail(of: model.query, fitting: queryMaxWidth - 2)
        if shown.isEmpty {
            PickerStyle.draw("type to search", in: NSRect(x: queryX + 3, y: rect.minY, width: queryMaxWidth, height: rect.height),
                             color: .tertiaryLabelColor)
        } else {
            PickerStyle.draw(shown, in: NSRect(x: queryX, y: rect.minY, width: queryMaxWidth, height: rect.height))
        }
        // A bar cursor after the query.
        let cursorX = queryX + (shown.isEmpty ? 0 : PickerStyle.width(of: shown)) + 1
        NSColor.labelColor.setFill()
        NSRect(x: cursorX, y: rect.minY + 3, width: 2, height: rect.height - 6).fill()
    }

    /// The end of the text that fits the width, so the end of a long query stays visible.
    static func tail(of text: String, fitting width: CGFloat) -> String {
        var shown = Substring(text)
        while !shown.isEmpty && PickerStyle.width(of: String(shown)) > width { shown = shown.dropFirst() }
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
        case 36, 76: return .enter
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

    func rowIndex(at point: NSPoint) -> Int? {
        let rect = chrome.listRect
        guard rect.contains(point) else { return nil }
        let index = model.firstRow + Int(floor((point.y - rect.minY) / PickerStyle.rowHeight))
        return index < model.rows.count ? index : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard let index = rowIndex(at: convert(event.locationInWindow, from: nil)) else { return }
        model.select(index)
        needsDisplay = true
        if event.clickCount >= 2, let clip = model.selectedClip { onAction?(.recall(clip.id)) }
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / PickerStyle.rowHeight : event.scrollingDeltaY
        scrollRemainder -= delta
        let rows = Int(scrollRemainder.rounded(.towardZero))
        guard rows != 0 else { return }
        scrollRemainder -= CGFloat(rows)
        model.scroll(by: rows)
        needsDisplay = true
    }
}
