import AppKit

/// What the settings panel shows. Built by the status item controller each time the panel opens or changes.
struct SettingsPanelContent {
    var settings: Settings
    var statistics: StoreStatistics?
    /// The current clipboard: kind, size and source, or why it was not recorded.
    var clipboardLine: String
    /// The app in front when the panel opened, offered for "Ignore".
    var frontmostApp: (identifier: String, name: String)?
    var notices: [PanelNotice]
    /// Display names of the ignored apps, by bundle identifier.
    var appNames: [String: String]
    /// The registered picker hotkey, shown on the Open Picker button.
    var hotkeyLabel: String?
    var now = Date()
}

enum PanelNotice: Equatable {
    case needsAccessibility
    case hotkeyUnavailable(HotkeyChoice)

    var title: String {
        switch self {
        case .needsAccessibility: return "Pasting needs Accessibility permission. Open settings\u{2026}"
        case .hotkeyUnavailable(let choice): return "\(choice.title) is taken by another app. Retry"
        }
    }
}

/// What the panel asks its owner to do.
struct SettingsPanelActions {
    var update: (_ change: (inout Settings) -> Void) -> Void = { _ in }
    /// Applies a smaller history limit. Called only after the user confirms deleting the extra clips.
    var keepHistory: (Int) -> Void = { _ in }
    var clearHistory: () -> Void = {}
    var openPicker: () -> Void = {}
    var openNotice: (PanelNotice) -> Void = { _ in }
    var quit: () -> Void = {}
    var close: () -> Void = {}
}

/// The settings panel: statistics at the top, then checkboxes and choice rows, then buttons. Drawn like the picker
/// and noteapp's /import popup. Every change applies at once; deleting clips asks first, inside the panel.
final class SettingsPanelView: NSView {
    static let width: CGFloat = 480
    static let hotkeyTitles: [(HotkeyChoice, String)] = [
        (.shiftCommandV, "\u{21E7}\u{2318}V"), (.optionCommandV, "\u{2325}\u{2318}V"), (.controlCommandV, "\u{2303}\u{2318}V"),
        (.shiftOptionCommandV, "\u{21E7}\u{2325}\u{2318}V"), (.none, "None"),
    ]

    enum Confirmation: Equatable {
        case clearHistory(clipCount: Int)
        case keepHistory(limit: Int, deleting: Int)
    }

    var actions = SettingsPanelActions()
    private(set) var content: SettingsPanelContent?
    private(set) var confirmation: Confirmation?
    private(set) var controls: [PanelControl] = []
    private var focused: PanelControl?
    private var texts: [(text: String, rect: NSRect, font: NSFont, color: NSColor, alignment: NSTextAlignment)] = []
    private var separators: [NSRect] = []
    private(set) var preferredHeight: CGFloat = 200

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 200))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func show(_ content: SettingsPanelContent) {
        self.content = content
        rebuild()
    }

    /// Opening starts without a confirmation or focus.
    func resetInteraction() {
        confirmation = nil
        focused = nil
        rebuild()
    }

    func control(named name: String) -> PanelControl? { controls.first { $0.partName == name } }

    // MARK: layout

    private func rebuild() {
        guard let content else { return }
        let focusedName = focused?.partName
        controls.forEach { $0.removeFromSuperview() }
        controls = []
        texts = []
        separators = []
        let gap = InterfaceStyle.gap
        let rowHeight = InterfaceStyle.rowHeight
        let controlHeight = rowHeight + 4
        let width = Self.width
        let labelWidth = InterfaceStyle.width(of: "Largest clip") + gap * 2
        let valueX = gap + labelWidth
        let settings = content.settings
        var y: CGFloat = 0

        func text(_ string: String, x: CGFloat, width: CGFloat, height: CGFloat = rowHeight, font: NSFont = InterfaceStyle.font,
                  color: NSColor = .labelColor, alignment: NSTextAlignment = .left) {
            texts.append((string, NSRect(x: x, y: y, width: max(0, width), height: height), font, color, alignment))
        }
        func separator() {
            separators.append(NSRect(x: 0, y: y, width: width, height: 1))
            y += 1 + gap
        }
        func add(_ control: PanelControl, x: CGFloat, width controlWidth: CGFloat? = nil, height: CGFloat = controlHeight) {
            control.frame = NSRect(x: x, y: y, width: min(controlWidth ?? control.preferredWidth, width - x - gap), height: height)
            control.onFocusRequest = { [weak self] in self?.setFocus($0) }
            addSubview(control)
            controls.append(control)
        }

        // Title row.
        let titleHeight = rowHeight + gap
        let count = content.statistics?.clipCount ?? 0
        text("Simple Clipboard", x: gap, width: width / 2, height: titleHeight)
        text(settings.capturePaused ? "paused" : "\(count.formatted()) clips", x: width / 2, width: width / 2 - gap,
             height: titleHeight, color: .secondaryLabelColor, alignment: .right)
        y += titleHeight
        separator()

        // Statistics.
        text("Clipboard", x: gap, width: labelWidth, color: .secondaryLabelColor)
        text(content.clipboardLine, x: valueX, width: width - valueX - gap)
        y += rowHeight
        text("History", x: gap, width: labelWidth, color: .secondaryLabelColor)
        if let statistics = content.statistics {
            text("\(statistics.clipCount.formatted()) clips, \(Format.bytes(statistics.clipBytes)) copied, "
                 + "\(Format.bytes(statistics.diskBytes)) on disk", x: valueX, width: width - valueX - gap)
            y += rowHeight
            var details: [String] = []
            if let oldest = statistics.oldestCopiedAt { details.append("oldest \(Format.shortDate(oldest))") }
            if let latest = statistics.latest {
                var last = "last copy \(Format.age(from: latest.lastCopiedAt, to: content.now))"
                if last != "last copy now" { last += " ago" }
                if let app = latest.sourceAppName { last += " in \(app)" }
                details.append(last)
            }
            for detail in details {
                text(detail, x: valueX, width: width - valueX - gap, color: .secondaryLabelColor)
                y += rowHeight
            }
        } else {
            text("not available", x: valueX, width: width - valueX - gap, color: .secondaryLabelColor)
            y += rowHeight
        }
        y += gap - 4
        separator()

        // Checkboxes.
        let paste = PanelCheckbox(partName: "paste", title: "Paste into the frontmost app", isOn: settings.recallMode == .paste)
        paste.onChange = { [weak self] on in self?.actions.update { $0.recallMode = on ? .paste : .clipboard } }
        add(paste, x: gap - 2, height: rowHeight)
        y += rowHeight + 2
        let plain = PanelCheckbox(partName: "plainText", title: "Always paste plain text", isOn: settings.alwaysPastePlainText)
        plain.onChange = { [weak self] on in self?.actions.update { $0.alwaysPastePlainText = on } }
        add(plain, x: gap - 2, height: rowHeight)
        y += rowHeight + 2
        let pause = PanelCheckbox(partName: "pause", title: "Pause capture", isOn: settings.capturePaused)
        pause.onChange = { [weak self] on in self?.actions.update { $0.capturePaused = on } }
        add(pause, x: gap - 2, height: rowHeight)
        y += rowHeight + gap

        // Choice rows.
        text("Hotkey", x: gap, width: labelWidth, height: controlHeight, color: .secondaryLabelColor)
        let hotkey = PanelChoiceRow(partName: "hotkey", titles: Self.hotkeyTitles.map(\.1),
                                    selectedIndex: Self.hotkeyTitles.firstIndex { $0.0 == settings.pickerHotkey })
        hotkey.onChange = { [weak self] index in self?.actions.update { $0.pickerHotkey = Self.hotkeyTitles[index].0 } }
        add(hotkey, x: valueX)
        y += controlHeight + 4

        let limits = Self.choices(Settings.historyLimitChoices, including: settings.historyLimit)
        text("Keep", x: gap, width: labelWidth, height: controlHeight, color: .secondaryLabelColor)
        let keep = PanelChoiceRow(partName: "keep", titles: limits.map { $0.formatted() }, suffix: "clips",
                                  selectedIndex: limits.firstIndex(of: settings.historyLimit))
        keep.onChange = { [weak self] index in self?.chooseHistoryLimit(limits[index]) }
        add(keep, x: valueX)
        y += controlHeight + 4

        let sizes = Self.choices(Settings.maximumClipMegabyteChoices, including: settings.maximumClipMegabytes)
        text("Largest clip", x: gap, width: labelWidth, height: controlHeight, color: .secondaryLabelColor)
        let largest = PanelChoiceRow(partName: "largest", titles: sizes.map { "\($0)" }, suffix: "MB",
                                     selectedIndex: sizes.firstIndex(of: settings.maximumClipMegabytes))
        largest.onChange = { [weak self] index in self?.actions.update { $0.maximumClipMegabytes = sizes[index] } }
        add(largest, x: valueX)
        y += controlHeight + gap

        // Ignored apps.
        text("Ignored apps", x: gap, width: labelWidth, color: .secondaryLabelColor)
        var listedAny = false
        for identifier in settings.ignoredApps {
            let name = content.appNames[identifier] ?? identifier
            let checkbox = PanelCheckbox(partName: "ignored:\(identifier)", title: name, isOn: true)
            checkbox.toolTip = identifier
            checkbox.onChange = { [weak self] on in
                self?.actions.update { settings in
                    if on {
                        if !settings.ignoredApps.contains(identifier) { settings.ignoredApps.append(identifier) }
                    } else {
                        settings.ignoredApps.removeAll { $0 == identifier }
                    }
                }
            }
            add(checkbox, x: valueX - 2, height: rowHeight)
            y += rowHeight + 2
            listedAny = true
        }
        if let front = content.frontmostApp, !settings.ignoredApps.contains(front.identifier) {
            let ignore = PanelButton(partName: "ignoreFrontmost", title: "+ Ignore \(front.name)", isLink: true)
            ignore.textColor = .secondaryLabelColor
            ignore.onPress = { [weak self] in self?.actions.update { $0.ignoredApps.append(front.identifier) } }
            add(ignore, x: valueX - 3, height: rowHeight)
            y += rowHeight + 2
            listedAny = true
        }
        if !listedAny {
            text("none", x: valueX, width: width - valueX - gap, color: .secondaryLabelColor)
            y += rowHeight + 2
        }
        y += gap - 2

        // Notices.
        if !content.notices.isEmpty {
            separator()
            for notice in content.notices {
                let button = PanelButton(partName: "notice", title: notice.title, isLink: true)
                button.onPress = { [weak self] in self?.actions.openNotice(notice) }
                add(button, x: gap - 3, width: width - gap * 2, height: rowHeight)
                y += rowHeight + 2
            }
            y += gap - 2
        }

        // Bottom bar.
        separator()
        if let confirmation {
            let question: String
            switch confirmation {
            case .clearHistory(let clipCount): question = "Delete all \(clipCount.formatted()) clips?"
            case .keepHistory(let limit, let deleting):
                question = "Keep \(limit.formatted()): delete the \(deleting.formatted()) oldest clips?"
            }
            let delete = PanelButton(partName: "confirmDelete", title: "Delete")
            delete.isDefault = true
            delete.onPress = { [weak self] in self?.confirm() }
            let cancel = PanelButton(partName: "confirmCancel", title: "Cancel")
            cancel.onPress = { [weak self] in self?.cancelConfirmation() }
            let deleteX = width - gap - delete.preferredWidth
            let cancelX = deleteX - gap - cancel.preferredWidth
            text(question, x: gap, width: cancelX - gap * 2, height: controlHeight)
            add(cancel, x: cancelX)
            add(delete, x: deleteX)
        } else {
            let pickerTitle = "Open Picker" + (content.hotkeyLabel.map { "  \($0)" } ?? "")
            let open = PanelButton(partName: "openPicker", title: pickerTitle)
            open.onPress = { [weak self] in self?.actions.openPicker() }
            add(open, x: gap)
            let clear = PanelButton(partName: "clearHistory", title: "Clear History\u{2026}")
            clear.onPress = { [weak self] in
                guard let self, let count = self.content?.statistics?.clipCount, count > 0 else { NSSound.beep(); return }
                self.ask(.clearHistory(clipCount: count))
            }
            add(clear, x: gap + open.preferredWidth + gap)
            let quit = PanelButton(partName: "quit", title: "Quit")
            quit.onPress = { [weak self] in self?.actions.quit() }
            add(quit, x: width - gap - quit.preferredWidth)
        }
        y += controlHeight + gap

        preferredHeight = y
        setFrameSize(NSSize(width: width, height: y))
        focused = focusedName.flatMap { name in controls.first { $0.partName == name } }
        if confirmation != nil && (focused == nil || !(focused?.partName.hasPrefix("confirm") ?? false)) {
            focused = control(named: "confirmDelete")
        }
        focused?.isFocused = true
        needsDisplay = true
    }

    /// The menu choices plus the current value when it is not one of them, in order.
    static func choices(_ base: [Int], including value: Int) -> [Int] {
        base.contains(value) ? base : (base + [value]).sorted()
    }

    // MARK: confirmation

    private func chooseHistoryLimit(_ limit: Int) {
        let deleting = max(0, (content?.statistics?.clipCount ?? 0) - limit)
        if deleting > 0 {
            ask(.keepHistory(limit: limit, deleting: deleting))
        } else {
            actions.update { $0.historyLimit = limit }
        }
    }

    private func ask(_ question: Confirmation) {
        confirmation = question
        focused = nil
        rebuild()
    }

    func confirm() {
        guard let confirmation else { return }
        self.confirmation = nil
        focused = nil
        switch confirmation {
        case .clearHistory: actions.clearHistory()
        case .keepHistory(let limit, _): actions.keepHistory(limit)
        }
        rebuild()
    }

    func cancelConfirmation() {
        confirmation = nil
        focused = nil
        rebuild()
    }

    // MARK: drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
        InterfaceStyle.strokeBorder(bounds, color: .tertiaryLabelColor)
        NSColor.separatorColor.setFill()
        separators.forEach { $0.fill() }
        for item in texts {
            InterfaceStyle.draw(item.text, in: item.rect, font: item.font, color: item.color, alignment: item.alignment)
        }
    }

    // MARK: focus and keys

    private func setFocus(_ control: PanelControl?) {
        focused?.isFocused = false
        focused = control
        control?.isFocused = true
    }

    var focusedPart: String { focused?.partName ?? "" }

    func moveFocus(by delta: Int) {
        guard !controls.isEmpty else { return }
        let current = focused.flatMap { controls.firstIndex(of: $0) }
        let next = current.map { ($0 + delta + controls.count) % controls.count } ?? (delta > 0 ? 0 : controls.count - 1)
        setFocus(controls[next])
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:
            if confirmation != nil { cancelConfirmation() } else { actions.close() }
            return
        case 48:
            moveFocus(by: event.modifierFlags.contains(.shift) ? -1 : 1)
            return
        default:
            break
        }
        if let focused, focused.handleKey(event) { return }
        if confirmation != nil, event.keyCode == 36 || event.keyCode == 76 { confirm(); return }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if flags == .command, event.charactersIgnoringModifiers == "w" { actions.close(); return true }
        if flags == .command, event.charactersIgnoringModifiers == "q" { actions.quit(); return true }
        return super.performKeyEquivalent(with: event)
    }
}
