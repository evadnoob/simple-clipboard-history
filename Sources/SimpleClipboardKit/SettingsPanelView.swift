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
    var loginEnabled = false
    var loginMessage: String?
    var now = Date()
    var copyActivity: [(hour: Int64, copies: Int)] = []
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
    var setLoginEnabled: (Bool) -> Void = { _ in }
    var openLoginSettings: () -> Void = {}
    var quit: () -> Void = {}
    var close: () -> Void = {}
}

/// Flat control panel with direct settings. Changes apply immediately; deleting clips asks inside the panel.
final class SettingsPanelView: NSView {
    static let width: CGFloat = 390
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
    let scrollView = NSScrollView()
    private let settingsBody = PanelSectionView()
    private let footer = PanelSectionView()
    private(set) var activityChart: CopyActivityChartView?
    private var bodyHeight: CGFloat = 0
    private var footerHeight: CGFloat = 0
    var onPreferredSizeChange: (() -> Void)?
    var maximumHeight: CGFloat = .greatestFiniteMagnitude { didSet { layoutContents() } }
    private(set) var preferredHeight: CGFloat = 200

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 200))
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = settingsBody
        addSubview(scrollView)
        addSubview(footer)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func show(_ content: SettingsPanelContent) {
        let previousLimit = self.content?.settings.historyLimit
        if let editor = window?.firstResponder as? NSTextView,
           controls.compactMap({ $0 as? PanelIntegerField }).contains(where: { window?.fieldEditor(false, for: $0.field) === editor }) {
            window?.makeFirstResponder(self)
        }
        var updatedContent = content
        if let previousLimit, let acceptedLimit = self.content?.settings.historyLimit,
           acceptedLimit != previousLimit {
            updatedContent.settings.historyLimit = acceptedLimit
        }
        self.content = updatedContent
        rebuild()
    }

    /// Opening starts without a confirmation or focus.
    func resetInteraction() {
        confirmation = nil
        focused = nil
        rebuild()
    }

    func control(named name: String) -> PanelControl? { controls.first { $0.partName == name } }

    var statusLine: String {
        guard let content else { return "" }
        let state = content.settings.capturePaused ? "Paused" : "Active"
        guard let statistics = content.statistics else { return "\(state) · History unavailable" }
        return "\(state) · \(statistics.clipCount.formatted()) items · \(Format.bytes(statistics.clipBytes)) / \(content.settings.maximumHistoryMegabytes) MB"
    }

    // MARK: layout

    private func rebuild() {
        guard let content else { return }
        let focusedName = focused?.partName
        settingsBody.subviews.forEach { $0.removeFromSuperview() }
        footer.subviews.forEach { $0.removeFromSuperview() }
        settingsBody.separators = []
        activityChart = nil
        settingsBody.sectionHeaders = []
        footer.separators = []
        controls = []
        var container = settingsBody
        let gap = InterfaceStyle.gap
        let rowHeight: CGFloat = 22
        let controlHeight: CGFloat = 24
        let width = Self.width
        let labelWidth: CGFloat = 154
        let valueX = gap + labelWidth
        let settings = content.settings
        var y: CGFloat = 0

        func text(_ string: String, x: CGFloat, width: CGFloat, height: CGFloat = rowHeight, font: NSFont = InterfaceStyle.controlFont,
                  color: NSColor = .labelColor, alignment: NSTextAlignment = .left, identifier: String? = nil) {
            let label = NSTextField(labelWithString: string)
            label.font = font
            label.textColor = color
            label.alignment = alignment
            label.lineBreakMode = .byTruncatingTail
            label.frame = NSRect(x: x, y: y + max(0, (height - 17) / 2), width: max(0, width), height: 17)
            label.toolTip = string
            if let identifier {
                label.setAccessibilityIdentifier(identifier)
                label.setAccessibilityLabel(string)
            }
            container.addSubview(label)
        }
        func separator() {
            container.separators.append(NSRect(x: 0, y: y, width: width, height: 1))
            y += 1 + gap
        }
        func add(_ control: PanelControl, x: CGFloat, width controlWidth: CGFloat? = nil, height: CGFloat = controlHeight) {
            control.frame = NSRect(x: x, y: y, width: min(controlWidth ?? control.preferredWidth, width - x - gap), height: height)
            control.onFocusRequest = { [weak self] in self?.setFocus($0) }
            control.onNavigationKey = { [weak self] in self?.keyDown(with: $0) }
            container.addSubview(control)
            controls.append(control)
        }

        func section(_ title: String) {
            container.sectionHeaders.append(NSRect(x: 0, y: y, width: width, height: 20))
            text(title, x: gap, width: width - gap * 2, height: 20,
                 font: .systemFont(ofSize: 11, weight: .semibold), identifier: "section:\(title)")
            y += 22
        }
        func checkbox(_ name: String, _ title: String, _ on: Bool, _ change: @escaping (Bool) -> Void) {
            let control = PanelCheckbox(partName: name, title: title, isOn: on)
            control.onChange = change
            if name == "paste" { control.toolTip = "When off, choosing an item only restores the clipboard; press Command-V to paste." }
            add(control, x: gap, height: rowHeight)
            y += rowHeight
        }
        func dropdown(_ name: String, _ label: String, _ titles: [String], _ selected: Int?, _ change: @escaping (Int) -> Void) {
            text(label, x: gap, width: labelWidth, height: controlHeight, color: .labelColor)
            let control = PanelDropdown(partName: name, label: label, titles: titles, selectedIndex: selected)
            control.onChange = change
            add(control, x: valueX, width: width - valueX - gap)
            y += controlHeight
        }
        func integerChoice(_ name: String, _ label: String, _ values: [Int], _ value: Int,
                           _ change: @escaping (Int) -> Void) {
            let choices = Self.choices(values, including: value)
            dropdown(name, label, choices.map { $0.formatted() }, choices.firstIndex(of: value)) { change(choices[$0]) }
        }
        func integerInput(_ name: String, _ label: String, _ value: Int, _ change: @escaping (Int) -> Void) {
            text(label, x: gap, width: labelWidth, height: controlHeight, color: .labelColor)
            let control = PanelIntegerField(partName: name, label: label, value: value)
            control.onCommit = change
            control.onTab = { [weak self] in self?.moveFocus(by: 1) }
            add(control, x: valueX, width: width - valueX - gap)
            y += controlHeight
        }

        let status = NSImageView(frame: NSRect(x: gap, y: 8, width: 12, height: 12))
        status.image = NSImage(systemSymbolName: settings.capturePaused ? "pause.circle.fill" : "checkmark.square.fill", accessibilityDescription: nil)
        status.contentTintColor = settings.capturePaused ? .secondaryLabelColor : .systemGreen
        container.addSubview(status)
        text(statusLine, x: gap + 18, width: width - gap * 2 - 18, height: 28)
        y += 28
        text("Clipboard: " + content.clipboardLine, x: gap, width: width - gap * 2,
             height: rowHeight, font: InterfaceStyle.smallFont, color: .secondaryLabelColor, identifier: "clipboardStatus")
        y += rowHeight
        let chart = CopyActivityChartView(days: settings.copyActivityDays, now: content.now, buckets: content.copyActivity)
        chart.frame = NSRect(x: gap, y: y, width: width - gap * 2, height: 43)
        chart.setAccessibilityLabel("Copy activity over the last \(settings.copyActivityDays) days, hourly")
        container.addSubview(chart)
        activityChart = chart
        y += 49
        dropdown("copyActivityDays", "Copy activity", Settings.copyActivityDayChoices.map { "\($0) days" },
                 Settings.copyActivityDayChoices.firstIndex(of: settings.copyActivityDays)) { [weak self] index in
            self?.actions.update { $0.copyActivityDays = Settings.copyActivityDayChoices[index] }
        }
        section("History")
        checkbox("pause", "Enable clipboard history", !settings.capturePaused) { [weak self] on in
            self?.actions.update { $0.capturePaused = !on }
        }
        checkbox("login", "Launch at login", content.loginEnabled) { [weak self] on in self?.actions.setLoginEnabled(on) }
        if let message = content.loginMessage {
            let notice = PanelButton(partName: "loginStatus", title: message, isLink: true)
            notice.toolTip = message
            notice.onPress = { [weak self] in self?.actions.openLoginSettings() }
            add(notice, x: gap, width: width - gap * 2, height: rowHeight)
            y += rowHeight
        }
        dropdown("hotkey", "Picker shortcut", Self.hotkeyTitles.map(\.1),
                 Self.hotkeyTitles.firstIndex { $0.0 == settings.pickerHotkey }) { [weak self] index in
            self?.actions.update { $0.pickerHotkey = Self.hotkeyTitles[index].0 }
        }
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

        section("Paste")
        checkbox("paste", "Paste automatically into frontmost app", settings.recallMode == .paste) { [weak self] on in
            self?.actions.update { $0.recallMode = on ? .paste : .clipboard }
        }
        dropdown("plainText", "When pasting", ["Preserve original formatting", "Paste as plain text"], settings.alwaysPastePlainText ? 1 : 0) { [weak self] index in
            self?.actions.update { $0.alwaysPastePlainText = index == 1 }
        }
        checkbox("pasteSpecial", "Show Paste Special in picker", settings.showPasteSpecial) { [weak self] on in
            self?.actions.update { $0.showPasteSpecial = on }
        }
        section("Limits")
        integerInput("keep", "Maximum items", settings.historyLimit) { [weak self] in self?.chooseHistoryLimit($0) }
        integerChoice("largest", "Largest clip (MB)", Settings.maximumClipMegabyteChoices, settings.maximumClipMegabytes) { [weak self] value in
            self?.actions.update { $0.maximumClipMegabytes = value }
        }
        integerChoice("historySize", "History size (MB)", Settings.maximumHistoryMegabyteChoices, settings.maximumHistoryMegabytes) { [weak self] value in
            self?.actions.update { $0.maximumHistoryMegabytes = value }
        }
        let clear = PanelButton(partName: "clearHistory", title: "Clear History…", isLink: true)
        clear.symbolName = "trash"
        clear.onPress = { [weak self] in
            guard let self, let count = self.content?.statistics?.clipCount, count > 0 else { return }
            self.ask(.clearHistory(clipCount: count))
        }
        add(clear, x: gap)
        y += controlHeight + 2
        let importButton = PanelButton(partName: "import", title: "Import: Not implemented", isLink: true)
        importButton.symbolName = "square.and.arrow.down"
        importButton.isEnabled = false
        add(importButton, x: gap, width: 185)
        let exportButton = PanelButton(partName: "export", title: "Export: Not implemented", isLink: true)
        exportButton.symbolName = "square.and.arrow.up"
        exportButton.isEnabled = false
        add(exportButton, x: 198, width: 184)
        y += controlHeight + 2
        section("Look and feel")
        dropdown("pickerWidth", "Width", ["Narrow (360 pt)", "Standard (460 pt)", "Wide (560 pt)"], Settings.pickerWidthChoices.firstIndex(of: settings.pickerWidth)) { [weak self] index in
            self?.actions.update { $0.pickerWidth = Settings.pickerWidthChoices[index] }
        }
        integerChoice("contentLines", "Content lines per item", Settings.pickerContentLineChoices, settings.pickerContentLines) { [weak self] value in
            self?.actions.update { $0.pickerContentLines = value }
        }
        dropdown("density", "Density", ["Compact", "Normal", "Comfortable"], Settings.pickerDensityChoices.firstIndex(of: settings.pickerDensity)) { [weak self] index in
            self?.actions.update { $0.pickerDensity = Settings.pickerDensityChoices[index] }
        }
        integerChoice("visibleItems", "Maximum visible items", Settings.visibleItemChoices, settings.maximumVisibleItems) { [weak self] value in
            self?.actions.update { $0.maximumVisibleItems = value }
        }
        checkbox("typeIcons", "Show type icons", settings.showTypeIcons) { [weak self] on in self?.actions.update { $0.showTypeIcons = on } }
        checkbox("timestamps", "Show timestamps", settings.showTimestamps) { [weak self] on in self?.actions.update { $0.showTimestamps = on } }

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

        // The action bar stays visible while settings scroll.
        bodyHeight = y
        container = footer
        y = 0
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
            text(question, x: gap, width: width - gap * 2, height: controlHeight)
            y += controlHeight
            add(cancel, x: cancelX)
            add(delete, x: deleteX)
        } else {
            let pickerTitle = "Open Picker" + (content.hotkeyLabel.map { "  \($0)" } ?? "")
            let open = PanelButton(partName: "openPicker", title: pickerTitle, isLink: true)
            open.symbolName = "list.clipboard"
            open.onPress = { [weak self] in self?.actions.openPicker() }
            add(open, x: gap)
            let quit = PanelButton(partName: "quit", title: "Quit", isLink: true)
            quit.symbolName = "power"
            quit.onPress = { [weak self] in self?.actions.quit() }
            add(quit, x: width - gap - quit.preferredWidth)
        }
        y += controlHeight + gap

        if confirmation != nil {
            controls.filter { !$0.partName.hasPrefix("confirm") }.forEach { $0.isEnabled = false }
        }
        footerHeight = y
        let oldPreferredHeight = preferredHeight
        preferredHeight = bodyHeight + footerHeight
        layoutContents()
        focused = focusedName.flatMap { name in controls.first { $0.partName == name } }
        if confirmation != nil && (focused == nil || !(focused?.partName.hasPrefix("confirm") ?? false)) {
            focused = control(named: "confirmDelete")
        }
        focused?.isFocused = true
        if window?.isKeyWindow == true { window?.makeFirstResponder(self) }
        if preferredHeight != oldPreferredHeight { onPreferredSizeChange?() }
        revealFocus()
        settingsBody.needsDisplay = true
        footer.needsDisplay = true
        needsDisplay = true
    }

    private func layoutContents() {
        let height = min(preferredHeight, maximumHeight)
        setFrameSize(NSSize(width: Self.width, height: height))
        let viewportHeight = max(0, height - footerHeight)
        scrollView.frame = NSRect(x: 0, y: 0, width: Self.width, height: viewportHeight)
        settingsBody.frame = NSRect(x: 0, y: 0, width: Self.width, height: bodyHeight)
        footer.frame = NSRect(x: 0, y: viewportHeight, width: Self.width, height: footerHeight)
        // Constrain the previous scroll offset when refreshed settings become shorter.
        let clip = scrollView.contentView
        clip.scroll(to: clip.constrainBoundsRect(clip.bounds).origin)
        scrollView.reflectScrolledClipView(clip)
        revealFocus()
    }

    private func revealFocus() {
        guard let focused, focused.isDescendant(of: settingsBody) else { return }
        focused.scrollToVisible(focused.bounds.insetBy(dx: 0, dy: -4))
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
        InterfaceStyle.panelBackground.setFill()
        bounds.fill()
        InterfaceStyle.strokeBorder(bounds, color: .tertiaryLabelColor)
    }

    // MARK: focus and keys

    private func setFocus(_ control: PanelControl?) {
        focused?.isFocused = false
        focused = control
        control?.isFocused = true
        revealFocus()
        if let integerField = control as? PanelIntegerField {
            window?.makeFirstResponder(integerField.field)
        } else {
            window?.makeFirstResponder(self)
        }
    }

    var focusedPart: String { focused?.partName ?? "" }

    func moveFocus(by delta: Int) {
        let available = controls.filter { $0.isEnabled && (confirmation == nil || $0.partName.hasPrefix("confirm")) }
        guard !available.isEmpty else { return }
        let current = focused.flatMap { available.firstIndex(of: $0) }
        let next = current.map { ($0 + delta + available.count) % available.count } ?? (delta > 0 ? 0 : available.count - 1)
        setFocus(available[next])
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

/// One blue bar per absolute hourly interval in a rolling UTC window.
final class CopyActivityChartView: NSView {
    let days: Int
    let now: Date
    let buckets: [(hour: Int64, copies: Int)]
    init(days: Int, now: Date, buckets: [(hour: Int64, copies: Int)]) {
        self.days = days
        self.now = now
        self.buckets = buckets
        super.init(frame: .zero)
        setAccessibilityRole(.image)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Exactly one horizontal slot per hourly interval. The last slot is always the current hour.
    var intervalRects: [NSRect] {
        let intervalCount = max(0, min(days, 10)) * 24
        guard intervalCount > 0, bounds.width.isFinite, bounds.width > 0 else { return [] }
        let slotWidth = bounds.width / CGFloat(intervalCount)
        let gap = min(1, slotWidth * 0.12)
        let barWidth = max(0, slotWidth - gap)
        return (0..<intervalCount).map { index in
            NSRect(x: CGFloat(index) * slotWidth, y: 0, width: barWidth, height: 0)
        }
    }

    /// Nonempty bars use the same interval geometry as drawing; missing activity stays absent.
    var renderedBarRects: [NSRect] {
        let count = intervalRects.count
        guard count > 0, bounds.height.isFinite, bounds.height > 14 else { return [] }
        let endHour = Int64(floor(now.timeIntervalSince1970 / 3600))
        let startHour = endHour - Int64(count - 1)
        let values = Dictionary(buckets.map { ($0.hour, $0.copies) }, uniquingKeysWith: max)
        let maximum = max(1, values.values.filter { $0 > 0 }.max() ?? 0)
        return intervalRects.enumerated().compactMap { index, slot in
            let value = values[startHour + Int64(index)] ?? 0
            guard value > 0 else { return nil }
            let height = (bounds.height - 14) * CGFloat(value) / CGFloat(maximum)
            guard height.isFinite, height > 0 else { return nil }
            return NSRect(x: slot.minX, y: bounds.height - 14 - height, width: slot.width, height: height)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        for rect in renderedBarRects {
            guard rect.minX.isFinite, rect.minY.isFinite, rect.width.isFinite, rect.height.isFinite,
                  rect.width >= 0, rect.height >= 0, bounds.contains(rect) else { continue }
            NSColor.systemBlue.setFill()
            rect.fill()
        }
        let labels = ["\(days) days ago", "Now"]
        for (label, x) in zip(labels, [CGFloat(0), max(0, bounds.width - 30)]) {
            (label as NSString).draw(at: NSPoint(x: x, y: bounds.height - 12), withAttributes: [.font: InterfaceStyle.smallFont, .foregroundColor: NSColor.secondaryLabelColor])
        }
    }
}

/// Flipped settings document and fixed footer share the panel's flat separator treatment.
final class PanelSectionView: NSView {
    var separators: [NSRect] = []
    var sectionHeaders: [NSRect] = []
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 0)).addClip()
        defer { NSGraphicsContext.restoreGraphicsState() }
        InterfaceStyle.sectionBackground.setFill()
        sectionHeaders.forEach { $0.fill() }
        NSColor.separatorColor.setFill()
        for header in sectionHeaders {
            NSRect(x: header.minX, y: header.minY, width: header.width, height: 1).fill()
            NSRect(x: header.minX, y: header.maxY - 1, width: header.width, height: 1).fill()
        }
        separators.forEach { $0.fill() }
    }
}
