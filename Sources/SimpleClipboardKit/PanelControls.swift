import AppKit

// The settings panel's controls: a checkbox, a row of choices and a text button. They follow noteapp's /import
// controls (ImportWizardCheckbox, ImportWizardSegments and ImportWizardButton in noteapp
// Sources/NoteApp/ImportWizardControls.swift at 617d7221). They draw themselves and never become first responder:
// the panel view keeps the keyboard and gives each key to the focused control (Tab moves the focus).

/// A control the panel can give the focus.
class PanelControl: NSView {
    /// A fixed name for the control, for the focus order and for tests.
    let partName: String
    var isFocused = false { didSet { if isFocused != oldValue { needsDisplay = true } } }
    /// Called when a click lands on the control, so the panel moves the focus to it.
    var onFocusRequest: ((PanelControl) -> Void)?

    init(partName: String) {
        self.partName = partName
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var preferredWidth: CGFloat { 0 }

    /// True when the control used the key.
    func handleKey(_ event: NSEvent) -> Bool { false }

    func click(at point: NSPoint) {}

    override func mouseDown(with event: NSEvent) {
        onFocusRequest?(self)
        click(at: convert(event.locationInWindow, from: nil))
    }
}

final class PanelCheckbox: PanelControl {
    var title: String { didSet { needsDisplay = true } }
    var isOn: Bool { didSet { needsDisplay = true } }
    var onChange: ((Bool) -> Void)?

    init(partName: String, title: String, isOn: Bool) {
        self.title = title
        self.isOn = isOn
        super.init(partName: partName)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private var side: CGFloat { ceil(InterfaceStyle.lineHeight * 0.9) }
    override var preferredWidth: CGFloat { side + InterfaceStyle.gap + InterfaceStyle.width(of: title) + 6 }

    override func draw(_ dirtyRect: NSRect) {
        let box = NSRect(x: 2, y: floor((bounds.height - side) / 2), width: side, height: side)
        NSColor.textBackgroundColor.setFill()
        box.fill()
        InterfaceStyle.strokeBorder(box, color: .secondaryLabelColor)
        if isOn {
            NSColor.labelColor.setStroke()
            let mark = NSBezierPath()
            mark.lineWidth = 1.6
            mark.move(to: NSPoint(x: box.minX + side * 0.2, y: box.midY))
            mark.line(to: NSPoint(x: box.minX + side * 0.42, y: box.maxY - side * 0.22))
            mark.line(to: NSPoint(x: box.maxX - side * 0.2, y: box.minY + side * 0.22))
            mark.stroke()
        }
        let textX = box.maxX + InterfaceStyle.gap
        InterfaceStyle.draw(title, in: NSRect(x: textX, y: 0, width: max(0, bounds.width - textX), height: bounds.height))
        if isFocused { InterfaceStyle.strokeFocus(bounds) }
    }

    func toggle() {
        isOn.toggle()
        onChange?(isOn)
    }

    override func handleKey(_ event: NSEvent) -> Bool {
        guard event.keyCode == 49 || event.keyCode == 36 || event.keyCode == 76 else { return false }
        toggle()
        return true
    }

    override func click(at point: NSPoint) { toggle() }
}

/// A row of choices with the selected one boxed and filled. Left and Right change the choice.
final class PanelChoiceRow: PanelControl {
    let titles: [String]
    /// Text after the choices, for example a unit.
    let suffix: String
    var selectedIndex: Int? { didSet { needsDisplay = true } }
    var onChange: ((Int) -> Void)?

    init(partName: String, titles: [String], suffix: String = "", selectedIndex: Int?) {
        self.titles = titles
        self.suffix = suffix
        self.selectedIndex = selectedIndex
        super.init(partName: partName)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private var padding: CGFloat { InterfaceStyle.gap }
    private var choiceWidths: [CGFloat] { titles.map { InterfaceStyle.width(of: $0) + padding * 2 } }
    override var preferredWidth: CGFloat {
        choiceWidths.reduce(0, +) + 4 + (suffix.isEmpty ? 0 : InterfaceStyle.gap + InterfaceStyle.width(of: suffix))
    }

    func choiceRects() -> [NSRect] {
        var x: CGFloat = 2
        return choiceWidths.map { width in
            defer { x += width - 1 }
            return NSRect(x: x, y: 1, width: width, height: bounds.height - 2)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let rects = choiceRects()
        for (index, rect) in rects.enumerated() where index != selectedIndex {
            InterfaceStyle.strokeBorder(rect)
            InterfaceStyle.draw(titles[index], in: rect, color: .secondaryLabelColor, alignment: .center)
        }
        // The selected choice last, so its darker border is not covered by a neighbor's.
        if let selected = selectedIndex, selected < rects.count {
            InterfaceStyle.selectionFill(rects[selected])
            InterfaceStyle.strokeBorder(rects[selected], color: .labelColor)
            InterfaceStyle.draw(titles[selected], in: rects[selected], alignment: .center)
        }
        if !suffix.isEmpty, let last = rects.last {
            InterfaceStyle.draw(suffix, in: NSRect(x: last.maxX + InterfaceStyle.gap, y: 0,
                                                   width: max(0, bounds.width - last.maxX - InterfaceStyle.gap), height: bounds.height),
                                color: .secondaryLabelColor)
        }
        if isFocused { InterfaceStyle.strokeFocus(NSRect(x: 0, y: 0, width: (rects.last?.maxX ?? 0) + 2, height: bounds.height)) }
    }

    func select(_ index: Int) {
        guard index >= 0, index < titles.count, index != selectedIndex else { return }
        selectedIndex = index
        onChange?(index)
    }

    override func handleKey(_ event: NSEvent) -> Bool {
        let current = selectedIndex ?? -1
        switch event.keyCode {
        case 123: select(max(0, current - 1)); return true
        case 124: select(current + 1); return true
        default: return false
        }
    }

    override func click(at point: NSPoint) {
        if let index = choiceRects().firstIndex(where: { $0.contains(point) }) { select(index) }
    }
}

/// A button: bordered, or with `isLink` a line of text. Space or Return presses it.
final class PanelButton: PanelControl {
    var title: String { didSet { needsDisplay = true } }
    var isLink: Bool
    /// The button Return presses in a confirmation, drawn with a filled background.
    var isDefault = false { didSet { needsDisplay = true } }
    var textColor: NSColor = .labelColor
    var onPress: (() -> Void)?

    init(partName: String, title: String, isLink: Bool = false) {
        self.title = title
        self.isLink = isLink
        super.init(partName: partName)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var preferredWidth: CGFloat {
        InterfaceStyle.width(of: title) + (isLink ? 6 : InterfaceStyle.gap * 3)
    }

    override func draw(_ dirtyRect: NSRect) {
        if isLink {
            InterfaceStyle.draw(title, in: bounds.insetBy(dx: 3, dy: 0), color: textColor)
        } else {
            if isDefault { InterfaceStyle.selectionFill(bounds) }
            InterfaceStyle.strokeBorder(bounds, color: isDefault ? .labelColor : .secondaryLabelColor)
            InterfaceStyle.draw(title, in: bounds, color: textColor, alignment: .center)
        }
        if isFocused { InterfaceStyle.strokeFocus(bounds) }
    }

    func press() { onPress?() }

    override func handleKey(_ event: NSEvent) -> Bool {
        guard event.keyCode == 49 || event.keyCode == 36 || event.keyCode == 76 else { return false }
        press()
        return true
    }

    override func click(at point: NSPoint) { press() }
}
