import AppKit

// Compact panel controls. The panel owns custom-control focus; dropdowns use native menu tracking.

/// A control the panel can give the focus.
class PanelControl: NSView {
    /// A fixed name for the control, for the focus order and for tests.
    let partName: String
    var isEnabled = true { didSet { setAccessibilityEnabled(isEnabled); needsDisplay = true } }
    var isFocused = false { didSet { if isFocused != oldValue { needsDisplay = true } } }
    /// Called when a click lands on the control, so the panel moves the focus to it.
    var onFocusRequest: ((PanelControl) -> Void)?
    var onNavigationKey: ((NSEvent) -> Void)?

    init(partName: String) {
        self.partName = partName
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityIdentifier(partName)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var preferredWidth: CGFloat { 0 }

    /// True when the control used the key.
    func handleKey(_ event: NSEvent) -> Bool { false }

    func click(at point: NSPoint) {}

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
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
        setAccessibilityRole(.checkBox)
        setAccessibilityLabel(title)
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
            NSColor.controlAccentColor.setStroke()
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

    override func accessibilityValue() -> Any? { isOn ? 1 : 0 }
    override func accessibilityPerformPress() -> Bool { guard isEnabled else { return false }; onFocusRequest?(self); toggle(); return true }

    func toggle() {
        guard isEnabled else { return }
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
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var preferredWidth: CGFloat {
        InterfaceStyle.width(of: title) + (isLink ? 6 : InterfaceStyle.gap * 3)
    }

    override func draw(_ dirtyRect: NSRect) {
        if isLink {
            InterfaceStyle.draw(title, in: bounds.insetBy(dx: 3, dy: 0), color: isEnabled ? textColor : .disabledControlTextColor)
        } else {
            if isDefault { InterfaceStyle.selectionFill(bounds) }
            InterfaceStyle.strokeBorder(bounds, color: isDefault ? .labelColor : .secondaryLabelColor)
            InterfaceStyle.draw(title, in: bounds, color: isEnabled ? textColor : .disabledControlTextColor, alignment: .center)
        }
        if isFocused { InterfaceStyle.strokeFocus(bounds) }
    }

    override func accessibilityPerformPress() -> Bool { guard isEnabled else { return false }; onFocusRequest?(self); press(); return true }
    func press() { guard isEnabled else { return }; onPress?() }

    override func handleKey(_ event: NSEvent) -> Bool {
        guard event.keyCode == 49 || event.keyCode == 36 || event.keyCode == 76 else { return false }
        press()
        return true
    }

    override func click(at point: NSPoint) { press() }
}

/// The popup itself provides native menu tracking, labels and accessibility actions.
final class PanelDropdown: PanelControl {
    override var isEnabled: Bool { didSet { popup.isEnabled = isEnabled } }
    let popup = PanelPopupButton(frame: .zero, pullsDown: false)
    let titles: [String]
    var selectedIndex: Int { popup.indexOfSelectedItem }
    var onChange: ((Int) -> Void)?
    init(partName: String, label: String, titles: [String], selectedIndex: Int?) {
        self.titles = titles
        super.init(partName: partName)
        setAccessibilityElement(false)
        popup.addItems(withTitles: titles)
        if let selectedIndex { popup.selectItem(at: selectedIndex) }
        popup.controlSize = .small
        popup.font = InterfaceStyle.font
        popup.setAccessibilityRole(.popUpButton)
        popup.setAccessibilityLabel(label)
        popup.setAccessibilityIdentifier(partName)
        popup.onPanelKey = { [weak self] event in
            guard let self else { return }
            self.onFocusRequest?(self)
            self.onNavigationKey?(event)
        }
        popup.target = self
        popup.action = #selector(changed)
        addSubview(popup)
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    override var preferredWidth: CGFloat { 190 }
    override func layout() { super.layout(); popup.frame = bounds }
    @objc private func changed() { onFocusRequest?(self); onChange?(selectedIndex) }
    func select(_ index: Int) {
        guard isEnabled, titles.indices.contains(index), index != selectedIndex else { return }
        popup.selectItem(at: index)
        onChange?(index)
    }
    override func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 123, 126: select(max(0, selectedIndex - 1)); return true
        case 124, 125: select(min(titles.count - 1, selectedIndex + 1)); return true
        case 49, 36, 76: popup.performClick(nil); return true
        default: return false
        }
    }
    override func draw(_ dirtyRect: NSRect) { if isFocused { InterfaceStyle.strokeFocus(bounds) } }
}

final class PanelPopupButton: NSPopUpButton {
    var onPanelKey: ((NSEvent) -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 48 || event.keyCode == 53 { onPanelKey?(event) }
        else { super.keyDown(with: event) }
    }
}
