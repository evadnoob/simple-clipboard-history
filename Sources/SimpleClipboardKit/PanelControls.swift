import AppKit

// Compact panel controls. The panel owns custom-control focus; dropdowns use native menu tracking.

/// A control the panel can give the focus.
class PanelControl: NSView {
    /// A fixed name for the control, for the focus order and for tests.
    let partName: String
    var isEnabled = true { didSet { setAccessibilityEnabled(isEnabled); updateEnabledState(); needsDisplay = true } }
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
    func updateEnabledState() {}

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
    var title: String { didSet { button.title = title; setAccessibilityLabel(title) } }
    var isOn: Bool { didSet { button.state = isOn ? .on : .off } }
    override var isEnabled: Bool { didSet { button.isEnabled = isEnabled } }
    let button = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    var onChange: ((Bool) -> Void)?

    init(partName: String, title: String, isOn: Bool) {
        self.title = title
        self.isOn = isOn
        super.init(partName: partName)
        setAccessibilityRole(.checkBox)
        setAccessibilityLabel(title)
        button.title = title
        button.state = isOn ? .on : .off
        button.controlSize = .small
        button.font = InterfaceStyle.controlFont
        button.setAccessibilityElement(false)
        // The wrapper owns keyboard focus and accessibility; the native cell supplies checkbox drawing.
        addSubview(button)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var preferredWidth: CGFloat { 22 + InterfaceStyle.width(of: title, font: InterfaceStyle.controlFont) }
    override func layout() { super.layout(); button.frame = bounds }
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }

    override func draw(_ dirtyRect: NSRect) {
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
    var symbolName: String?
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
        InterfaceStyle.width(of: title, font: InterfaceStyle.controlFont) + (isLink ? 6 : InterfaceStyle.gap * 3) + (symbolName == nil ? 0 : 18)
    }

    override func draw(_ dirtyRect: NSRect) {
        let color: NSColor = !isEnabled ? .disabledControlTextColor : isDefault ? .alternateSelectedControlTextColor : textColor
        if !isLink {
            if isDefault { InterfaceStyle.selectionFill(bounds) }
            InterfaceStyle.strokeBorder(bounds, color: .separatorColor)
        }
        var textRect = isLink ? bounds.insetBy(dx: 3, dy: 0) : bounds
        if let symbolName {
            InterfaceStyle.drawSymbol(symbolName, in: NSRect(x: textRect.minX, y: bounds.midY - 6, width: 12, height: 12), color: color)
            textRect.origin.x += 18
            textRect.size.width -= 18
        }
        InterfaceStyle.draw(title, in: textRect, font: InterfaceStyle.controlFont, color: color, alignment: isLink ? .left : .center)
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
        popup.font = InterfaceStyle.controlFont
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

final class PanelIntegerField: PanelControl {
    let label: String
    let field = NSTextField(string: "")
    var onTab: (() -> Void)?
    var onCommit: ((Int) -> Void)?
    private var acceptedValue: Int
    private var dispatchedValue: Int?

    init(partName: String, label: String, value: Int) {
        self.label = label
        self.acceptedValue = value
        super.init(partName: partName)
        setAccessibilityRole(.textField)
        setAccessibilityLabel(label)
        field.stringValue = String(value)
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.controlSize = .small
        field.font = InterfaceStyle.controlFont
        field.alignment = .right
        field.delegate = self
        field.target = self
        field.action = #selector(commitField)
        field.setAccessibilityLabel(label)
        addSubview(field)
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    override var preferredWidth: CGFloat { 190 }
    override func updateEnabledState() { field.isEnabled = isEnabled }
    override func layout() { super.layout(); field.frame = NSRect(x: 0, y: 2, width: bounds.width, height: bounds.height - 4) }
    override func draw(_ dirtyRect: NSRect) { if isFocused { InterfaceStyle.strokeFocus(bounds) } }
    override func accessibilityValue() -> Any? { field.stringValue }
    override func handleKey(_ event: NSEvent) -> Bool { false }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard isEnabled, commandSelector == #selector(NSResponder.insertTab(_:)) else { return false }
        onTab?()
        return true
    }
    @objc private func commitField() { commit() }

    func commit() {
        guard isEnabled, let value = Int(field.stringValue), value > 0 else {
            NSSound.beep()
            field.stringValue = String(acceptedValue)
            return
        }
        guard value != acceptedValue, value != dispatchedValue else { return }
        dispatchedValue = value
        onCommit?(value)
    }
}

extension PanelIntegerField: NSTextFieldDelegate {
    func controlTextDidBeginEditing(_ obj: Notification) { onFocusRequest?(self) }
    func controlTextDidEndEditing(_ obj: Notification) { commit() }
}

final class PanelPopupButton: NSPopUpButton {
    var onPanelKey: ((NSEvent) -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 48 || event.keyCode == 53 { onPanelKey?(event) }
        else { super.keyDown(with: event) }
    }
}
