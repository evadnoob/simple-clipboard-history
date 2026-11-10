import AppKit

/// One tab stop with arrow-key focus and Space selection. The panel's existing native
/// scroll view contains these flat rows, so wheel events need no nested-scroll routing.
final class PanelIconStyleChoices: PanelControl {
    static let rowHeight: CGFloat = 62
    let titles = ClipIconStyle.allCases.map(\.title)
    private(set) var selectedIndex: Int
    private(set) var focusedIndex: Int
    private(set) var rows: [PanelIconStyleRow] = []
    var onChange: ((Int) -> Void)?

    init(selected: ClipIconStyle) {
        selectedIndex = ClipIconStyle.allCases.firstIndex(of: selected)!
        focusedIndex = selectedIndex
        super.init(partName: "iconStyle")
        setAccessibilityRole(.radioGroup)
        setAccessibilityLabel("Icon style")
        for (index, style) in ClipIconStyle.allCases.enumerated() {
            let row = PanelIconStyleRow(style: style)
            row.isSelected = index == selectedIndex
            row.onPress = { [weak self] in
                guard let self, self.isEnabled else { return }
                self.onFocusRequest?(self)
                self.focusRow(index)
                self.select(index)
            }
            rows.append(row)
            addSubview(row)
        }
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    override var isFocused: Bool { didSet { updateRows(); if isFocused { revealFocusedRow() } } }
    override func updateEnabledState() { rows.forEach { $0.isEnabled = isEnabled } }
    override func accessibilityValue() -> Any? { titles[selectedIndex] }
    override func accessibilityChildren() -> [Any]? { rows }
    override func layout() {
        super.layout()
        for (index, row) in rows.enumerated() {
            row.frame = NSRect(x: 0, y: CGFloat(index) * Self.rowHeight, width: bounds.width, height: Self.rowHeight)
        }
    }
    private func updateRows() {
        for (index, row) in rows.enumerated() {
            row.isFocused = isFocused && index == focusedIndex
            let selected = index == selectedIndex
            if row.isSelected != selected {
                row.isSelected = selected
                NSAccessibility.post(element: row, notification: .valueChanged)
            }
            row.needsDisplay = true
        }
    }
    func focusRow(_ index: Int) {
        guard rows.indices.contains(index) else { return }
        focusedIndex = index
        updateRows()
        revealFocusedRow()
    }
    func revealFocusedRow() { rows[focusedIndex].scrollToVisible(rows[focusedIndex].bounds) }
    func revealSelectedRow() { rows[selectedIndex].scrollToVisible(rows[selectedIndex].bounds) }
    func select(_ index: Int) {
        guard isEnabled, rows.indices.contains(index), index != selectedIndex else { return }
        selectedIndex = index
        updateRows()
        rows[index].scrollToVisible(rows[index].bounds)
        onChange?(index)
    }
    override func handleKey(_ event: NSEvent) -> Bool {
        guard isEnabled else { return false }
        switch event.keyCode {
        case 126: focusRow(max(0, focusedIndex - 1)); return true
        case 125: focusRow(min(rows.count - 1, focusedIndex + 1)); return true
        case 49: select(focusedIndex); return true
        default: return false
        }
    }
}

/// Fixed synthetic picker samples. No clipboard summaries, classifier or data access.
final class PanelIconStyleRow: NSView {
    let style: ClipIconStyle
    var isSelected = false
    var isFocused = false
    var isEnabled = true { didSet { setAccessibilityEnabled(isEnabled); needsDisplay = true } }
    var onPress: (() -> Void)?
    static let samples: [(ClipIconCategory, String)] = [(.text, "Notes"), (.formatted, "Styled"), (.link, "Site"), (.file, "brief.pdf")]

    init(style: ClipIconStyle) {
        self.style = style
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(style.title)
        setAccessibilityIdentifier("iconStyle:\(style.rawValue)")
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func accessibilityValue() -> Any? { isSelected ? 1 : 0 }
    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        onPress?()
        return true
    }
    override func mouseDown(with event: NSEvent) { _ = accessibilityPerformPress() }

    var titleFont: NSFont {
        isSelected ? .systemFont(ofSize: InterfaceStyle.controlFont.pointSize, weight: .semibold) : InterfaceStyle.controlFont
    }
    var focusUnderlineRect: NSRect {
        NSRect(x: 24, y: 22, width: InterfaceStyle.width(of: style.title, font: titleFont), height: 2)
    }
    override func draw(_ dirtyRect: NSRect) {
        let color: NSColor = isEnabled ? .labelColor : .disabledControlTextColor
        if isSelected {
            let tint: NSColor = isEnabled ? .systemBlue : .secondaryLabelColor
            tint.withAlphaComponent(isEnabled ? 0.10 : 0.06).setFill()
            bounds.fill()
            (isEnabled ? NSColor.systemBlue : .disabledControlTextColor).setFill()
            NSRect(x: 0, y: 0, width: 2, height: bounds.height).fill()
            InterfaceStyle.drawSymbol("checkmark", in: NSRect(x: 4, y: 7, width: 12, height: 12),
                                      color: isEnabled ? .systemBlue : .disabledControlTextColor)
        }
        InterfaceStyle.draw(style.title, in: NSRect(x: 24, y: 2, width: bounds.width - 28, height: 22),
                            font: titleFont, color: color)
        if isFocused {
            NSColor.keyboardFocusIndicatorColor.setFill()
            focusUnderlineRect.fill()
        }
        let sampleWidth = bounds.width / CGFloat(Self.samples.count)
        for (index, sample) in Self.samples.enumerated() {
            let x = CGFloat(index) * sampleWidth + 2
            let iconRect = NSRect(x: x, y: 31, width: 22, height: 22)
            if style == .current {
                // PickerView preserves Current's original drawing path.
                InterfaceStyle.drawSymbol(ClipTypeIcon.symbolName(category: sample.0, style: .current), in: iconRect, color: color)
            } else {
                ClipTypeIcon.draw(category: sample.0, style: style, in: iconRect, color: color)
            }
            InterfaceStyle.draw(sample.1, in: NSRect(x: x + 26, y: 30, width: sampleWidth - 30, height: 24),
                                font: InterfaceStyle.smallFont, color: color)
        }
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }
}
