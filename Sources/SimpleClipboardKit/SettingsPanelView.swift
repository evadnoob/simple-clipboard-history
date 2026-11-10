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

/// Flat control panel with an in-panel settings page. Changes apply immediately; deleting clips asks inside the panel.
final class SettingsPanelView: NSView {
    static let width: CGFloat = 390
    static func headerCount(_ count: Int) -> String {
        guard count >= 1_000_000 else { return count.formatted() }
        let units: [(Int, String)] = [(1_000_000_000_000, "T"), (1_000_000_000, "B"), (1_000_000, "M")]
        guard let (divisor, suffix) = units.first(where: { count >= $0.0 }) else { return count.formatted() }
        return String(format: "%.1f%@", Double(count) / Double(divisor), suffix)
    }

    static let hotkeyTitles: [(HotkeyChoice, String)] = [
        (.shiftCommandV, "\u{21E7}\u{2318}V"), (.optionCommandV, "\u{2325}\u{2318}V"), (.controlCommandV, "\u{2303}\u{2318}V"),
        (.shiftOptionCommandV, "\u{21E7}\u{2325}\u{2318}V"), (.none, "None"),
    ]

    enum Confirmation: Equatable {
        case clearHistory(clipCount: Int)
        case keepHistory(limit: Int, deleting: Int)
    }

    enum Page { case main, settings }
    private(set) var page: Page = .main

    func navigate(to page: Page) {
        window?.makeFirstResponder(self)
        confirmation = nil
        let showFocus = focused?.isFocused == true
        self.page = page
        focused = nil
        scrollView.contentView.scroll(to: .zero)
        rebuild()
        setFocus(control(named: page == .settings ? "back" : "settings"), showFocus: showFocus)
        (control(named: "iconStyle") as? PanelIconStyleChoices)?.revealSelectedRow()
        NSAccessibility.post(element: self, notification: .layoutChanged)
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
    func resetInteraction(page: Page = .main) {
        confirmation = nil
        self.page = page
        focused = nil
        scrollView.contentView.scroll(to: .zero)
        rebuild()
        if page == .settings { (control(named: "iconStyle") as? PanelIconStyleChoices)?.revealSelectedRow() }
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
        let focusedStyleIndex = (focused as? PanelIconStyleChoices)?.focusedIndex
        let showFocus = focused?.isFocused == true
        settingsBody.subviews.forEach { $0.removeFromSuperview() }
        footer.subviews.forEach { $0.removeFromSuperview() }
        settingsBody.separators = []
        activityChart = nil
        settingsBody.sectionHeaders = []
        footer.separators = []
        controls = []
        var container = settingsBody
        let gap = InterfaceStyle.gap
        let rowInset: CGFloat = 16
        let rowHeight: CGFloat = 22
        let controlHeight: CGFloat = 24
        let width = Self.width
        let labelWidth: CGFloat = 154
        let valueX = rowInset + labelWidth
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
            let availableWidth = name == "pause" && content.hotkeyLabel != nil
                ? width - rowInset * 2 - 72 - gap : width - rowInset * 2
            add(control, x: rowInset, width: availableWidth, height: rowHeight)
            y += rowHeight
        }
        func dropdown(_ name: String, _ label: String, _ titles: [String], _ selected: Int?, _ change: @escaping (Int) -> Void) {
            text(label, x: rowInset, width: labelWidth, height: controlHeight, color: .labelColor)
            let control = PanelDropdown(partName: name, label: label, titles: titles, selectedIndex: selected)
            control.onChange = change
            add(control, x: valueX, width: width - valueX - rowInset)
            y += controlHeight
        }
        func integerChoice(_ name: String, _ label: String, _ values: [Int], _ value: Int,
                           _ change: @escaping (Int) -> Void) {
            let choices = Self.choices(values, including: value)
            dropdown(name, label, choices.map { $0.formatted() }, choices.firstIndex(of: value)) { change(choices[$0]) }
        }
        func integerInput(_ name: String, _ label: String, _ value: Int, _ change: @escaping (Int) -> Void) {
            text(label, x: rowInset, width: labelWidth, height: controlHeight, color: .labelColor)
            let control = PanelIntegerField(partName: name, label: label, value: value)
            control.onCommit = change
            control.onTab = { [weak self] in self?.moveFocus(by: 1) }
            add(control, x: valueX, width: width - valueX - rowInset)
            y += controlHeight
        }

        func confirmationControls(_ confirmation: Confirmation, inset: CGFloat) {
            let question: String
            switch confirmation {
            case .clearHistory: question = "Clear all clipboard history?"
            case .keepHistory(let limit, let deleting):
                question = "Keep \(limit.formatted()): delete the \(deleting.formatted()) oldest clips?"
            }
            let clearing: Bool
            if case .clearHistory = confirmation { clearing = true } else { clearing = false }
            let delete = PanelButton(partName: "confirmDelete", title: clearing ? "Clear history" : "Delete")
            delete.isDefault = !clearing
            delete.onPress = { [weak self] in self?.confirm() }
            let cancel = PanelButton(partName: "confirmCancel", title: "Cancel")
            cancel.isDefault = clearing
            cancel.onPress = { [weak self] in self?.cancelConfirmation() }
            let deleteX = width - inset - delete.preferredWidth
            let cancelX = deleteX - inset - cancel.preferredWidth
            text(question, x: inset, width: width - inset * 2, height: controlHeight)
            y += controlHeight
            if clearing {
                text("This cannot be undone.", x: inset, width: width - inset * 2, height: 16,
                     font: InterfaceStyle.smallFont, color: .secondaryLabelColor, identifier: "clearHistoryWarning")
                y += 16
            }
            add(cancel, x: cancelX)
            add(delete, x: deleteX)
        }

        if page == .main {
            let header = SettingsPanelHeaderView(frame: NSRect(x: 0, y: 0, width: width, height: 64))
            let icon = NSImageView(frame: NSRect(x: gap, y: 8, width: 24, height: 26))
            icon.image = ClipboardIcon.image(size: NSSize(width: 24, height: 26), accessibilityDescription: "Clipboard")
            icon.imageScaling = .scaleAxesIndependently
            icon.contentTintColor = .labelColor
            icon.setAccessibilityLabel("Clipboard")
            header.addSubview(icon)
            let title = NSTextField(labelWithString: "Simple Clipboard History")
            title.font = .systemFont(ofSize: 16, weight: .bold)
            let titleWidth = width - (gap + 32) - 68 - gap
            title.frame = NSRect(x: gap + 32, y: 8, width: titleWidth, height: 24)
            title.setAccessibilityIdentifier("panelTitle")
            title.setAccessibilityLabel("Simple Clipboard History")
            header.addSubview(title)
            let chart = CopyActivityChartView(days: 5, now: content.now, buckets: content.copyActivity)
            chart.frame = NSRect(x: width - 68, y: 9, width: 54, height: 17)
            chart.setAccessibilityLabel("Copy activity over the last 5 days, in 20-hour groups")
            header.addSubview(chart)
            activityChart = chart
            let stats = content.statistics
            let state = settings.capturePaused ? "Paused" : "Active"
            let count = stats.map { Self.headerCount($0.clipCount) } ?? "Unavailable"
            let percent = stats.map { min(100, Int(Double($0.clipBytes) * 100 / (Double(settings.maximumHistoryMegabytes) * 1_048_576))) } ?? 0
            let bytes = stats.map { "\(Format.bytes($0.clipBytes)) / \(settings.maximumHistoryMegabytes) MB (\(percent)%)" } ?? "Unavailable"
            let countLabel = stats == nil ? "Unavailable items" : "\(count) items"
            let groups = [(state, gap + 18, 68.0), (countLabel, 107.0, 96.0), (bytes, 215.0, 167.0)]
            for (index, group) in groups.enumerated() {
                let label = NSTextField(labelWithString: group.0)
                label.font = .systemFont(ofSize: 12, weight: .semibold)
                label.frame = NSRect(x: group.1, y: 40, width: group.2, height: 18)
                label.setAccessibilityIdentifier("headerStat:\(index)")
                label.setAccessibilityLabel(group.0)
                header.addSubview(label)
                if index == 0 {
                    let square = NSView(frame: NSRect(x: gap, y: 45, width: 10, height: 10))
                    square.wantsLayer = true
                    square.layer?.backgroundColor = (settings.capturePaused ? NSColor.secondaryLabelColor : NSColor.systemGreen).cgColor
                    square.setAccessibilityLabel(state)
                    header.addSubview(square)
                }
                if index < 2 {
                    let dividerX = index == 0 ? 100 : 207
                    let divider = NSView(frame: NSRect(x: dividerX, y: 40, width: 1, height: 18))
                    divider.wantsLayer = true
                    divider.layer?.backgroundColor = NSColor.separatorColor.cgColor
                    header.addSubview(divider)
                }
            }
            container.addSubview(header)
            y += 66
            section("History")
            checkbox("pause", "Keep clipboard history", !settings.capturePaused) { [weak self] on in
                self?.actions.update { $0.capturePaused = !on }
            }
            if let shortcut = content.hotkeyLabel {
                let hint = NSTextField(labelWithString: shortcut)
                hint.font = .systemFont(ofSize: 12)
                hint.alignment = .right
                hint.textColor = .secondaryLabelColor
                hint.frame = NSRect(x: width - rowInset - 72, y: y - rowHeight + 2, width: 72, height: 18)
                hint.setAccessibilityLabel("Picker shortcut \(shortcut)")
                hint.setAccessibilityIdentifier("pickerShortcutHint")
                settingsBody.addSubview(hint)
            }
            checkbox("login", "Launch at login", content.loginEnabled) { [weak self] on in self?.actions.setLoginEnabled(on) }
            if let message = content.loginMessage {
                let notice = PanelButton(partName: "loginStatus", title: message, isLink: true)
                notice.toolTip = message
                notice.onPress = { [weak self] in self?.actions.openLoginSettings() }
                add(notice, x: gap, width: width - gap * 2, height: rowHeight)
                y += rowHeight
            }
            // Ignored apps.
            text("Ignored apps", x: rowInset, width: labelWidth, color: .secondaryLabelColor)
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
            section("Look and feel")
            dropdown("pickerWidth", "Width", ["Narrow (360 pt)", "Standard (460 pt)", "Wide (560 pt)"], Settings.pickerWidthChoices.firstIndex(of: settings.pickerWidth)) { [weak self] index in
                self?.actions.update { $0.pickerWidth = Settings.pickerWidthChoices[index] }
            }
            integerChoice("contentLines", "Content lines per item", Settings.pickerContentLineChoices, settings.pickerContentLines) { [weak self] value in
                self?.actions.update { $0.pickerContentLines = value }
            }
            dropdown("density", "Density", Settings.pickerDensityLabels, Settings.pickerDensityChoices.firstIndex(of: settings.pickerDensity)) { [weak self] index in
                self?.actions.update { $0.pickerDensity = Settings.pickerDensityChoices[index] }
            }
            integerChoice("visibleItems", "Maximum visible items", Settings.visibleItemChoices, settings.maximumVisibleItems) { [weak self] value in
                self?.actions.update { $0.maximumVisibleItems = value }
            }
            checkbox("typeIcons", "Show type icons", settings.showTypeIcons) { [weak self] on in self?.actions.update { $0.showTypeIcons = on } }
            checkbox("timestamps", "Show timestamps", settings.showTimestamps) { [weak self] on in self?.actions.update { $0.showTimestamps = on } }

        } else {
            y = rowInset
            let back = PanelButton(partName: "back", title: "Main", isLink: true)
            back.isNavigation = true
            back.textColor = .secondaryLabelColor
            back.setAccessibilityLabel("Return to Main")
            back.onPress = { [weak self] in self?.navigate(to: .main) }
            add(back, x: rowInset - 3, width: back.preferredWidth)
            let chevron = NSImageView(frame: NSRect(x: rowInset + back.preferredWidth + 3, y: y + 7, width: 8, height: 10))
            chevron.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
            chevron.contentTintColor = .tertiaryLabelColor
            chevron.setAccessibilityIdentifier("breadcrumbSeparator")
            container.addSubview(chevron)
            text("Settings", x: chevron.frame.maxX + 8, width: 100, height: controlHeight,
                 font: InterfaceStyle.controlFont, color: .secondaryLabelColor, identifier: "settingsTitle")
            y += controlHeight + 16
            text("Icon style", x: rowInset, width: width - rowInset * 2,
                 font: .systemFont(ofSize: 12, weight: .semibold), identifier: "section:Icon style")
            y += rowHeight
            let explanation = NSTextField(wrappingLabelWithString: "Choose how content types appear in the picker.")
            explanation.font = InterfaceStyle.smallFont
            explanation.textColor = .secondaryLabelColor
            let explanationWidth = width - rowInset * 2
            let explanationHeight = ceil(explanation.sizeThatFits(NSSize(width: explanationWidth, height: .greatestFiniteMagnitude)).height)
            explanation.frame = NSRect(x: rowInset, y: y, width: explanationWidth, height: explanationHeight)
            explanation.setAccessibilityIdentifier("iconStyleExplanation")
            container.addSubview(explanation)
            y += explanationHeight + 12
            let styles = PanelIconStyleChoices(selected: settings.iconStyle)
            styles.onChange = { [weak self] index in
                self?.actions.update { $0.iconStyle = ClipIconStyle.allCases[index] }
            }
            add(styles, x: rowInset, width: width - rowInset * 2,
                height: CGFloat(ClipIconStyle.allCases.count) * PanelIconStyleChoices.rowHeight)
            styles.layoutSubtreeIfNeeded()
            y += styles.frame.height + rowInset
            separator()
            if let confirmation {
                confirmationControls(confirmation, inset: rowInset)
                y += controlHeight
            } else {
                let clear = PanelButton(partName: "clearHistory", title: "Clear history…", isLink: true)
                clear.symbolName = "trash"
                clear.isEnabled = (content.statistics?.clipCount ?? 0) > 0
                clear.onPress = { [weak self] in
                    guard let self, let count = self.content?.statistics?.clipCount, count > 0 else { return }
                    self.ask(.clearHistory(clipCount: count))
                }
                add(clear, x: rowInset)
                y += controlHeight
            }
            y += rowInset
        }

        // Notices.
        if page == .main && !content.notices.isEmpty {
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
        if page == .main {
            separator()
            if let confirmation {
                confirmationControls(confirmation, inset: gap)
            } else {
                let actionY = y
                func footerAction(_ name: String, _ title: String, _ symbol: String, x: CGFloat, width: CGFloat,
                                  enabled: Bool = true, action: (() -> Void)? = nil) -> PanelButton {
                    let button = PanelButton(partName: name, title: title, isLink: true)
                    button.symbolName = symbol
                    button.isEnabled = enabled
                    button.onPress = action
                    add(button, x: x, width: width)
                    return button
                }
                let export = footerAction("export", "Export", "square.and.arrow.up", x: 104, width: 84, enabled: false)
                export.toolTip = "Export: Not implemented"
                export.setAccessibilityLabel("Export, Not implemented")
                footer.separators.append(NSRect(x: 194, y: actionY + 3, width: 1, height: 18))
                let importAction = footerAction("import", "Import", "square.and.arrow.down", x: 202, width: 78, enabled: false)
                importAction.toolTip = "Import: Not implemented"
                importAction.setAccessibilityLabel("Import, Not implemented")
                if page == .main {
                    footer.separators.append(NSRect(x: 290, y: actionY + 3, width: 1, height: 18))
                    let settingsNavigation = footerAction("settings", "Settings", "gearshape", x: 298, width: 82) { [weak self] in
                        self?.navigate(to: .settings)
                    }
                    settingsNavigation.isNavigation = true
                }
                y += controlHeight
                let unavailableFont = NSFont.systemFont(ofSize: 9)
                text("Not implemented", x: 100, width: 90, height: 16, font: unavailableFont,
                     color: .secondaryLabelColor, alignment: .center)
                text("Not implemented", x: 198, width: 88, height: 16, font: unavailableFont,
                     color: .secondaryLabelColor, alignment: .center)
                y += 16 + gap
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
        }
        if confirmation != nil {
            controls.filter { !$0.partName.hasPrefix("confirm") }.forEach { $0.isEnabled = false }
        }
        footerHeight = y
        let oldPreferredHeight = preferredHeight
        preferredHeight = bodyHeight + footerHeight
        layoutContents()
        focused = focusedName.flatMap { name in controls.first { $0.partName == name } }
        if confirmation != nil && (focused == nil || !(focused?.partName.hasPrefix("confirm") ?? false)) {
            if case .clearHistory? = confirmation { focused = control(named: "confirmCancel") }
            else { focused = control(named: "confirmDelete") }
        }
        focused?.isFocused = confirmation != nil || showFocus
        if let focusedStyleIndex, let styles = focused as? PanelIconStyleChoices { styles.focusRow(focusedStyleIndex) }
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
        if let styles = focused as? PanelIconStyleChoices { styles.revealFocusedRow() }
        else { focused.scrollToVisible(focused.bounds.insetBy(dx: 0, dy: -4)) }
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
        case .clearHistory:
            guard (content?.statistics?.clipCount ?? 0) > 0 else { rebuild(); return }
            actions.clearHistory()
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

    private func setFocus(_ control: PanelControl?, showFocus: Bool = true) {
        focused?.isFocused = false
        focused = control
        control?.isFocused = showFocus
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
            if confirmation != nil { cancelConfirmation() } else if page == .settings { navigate(to: .main) } else { actions.close() }
            return
        case 48:
            moveFocus(by: event.modifierFlags.contains(.shift) ? -1 : 1)
            return
        default:
            break
        }
        if let focused, focused.handleKey(event) { return }
        if case .keepHistory? = confirmation, event.keyCode == 36 || event.keyCode == 76 { confirm(); return }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if flags == .command, event.charactersIgnoringModifiers == "w" { actions.close(); return true }
        if flags == .command, event.charactersIgnoringModifiers == "q" { actions.quit(); return true }
        return super.performKeyEquivalent(with: event)
    }
}

final class SettingsPanelHeaderView: NSView {
    override var isFlipped: Bool { true }
}

/// One blue bar per 20-hour group of absolute hourly intervals in a rolling UTC window.
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
    override var isFlipped: Bool { true }

    var showsRangeCaptions: Bool { bounds.width >= 100 }

    private let hoursPerGroup = 20

    /// Groups consecutive hours in the rolling window; the newest group includes the current hour.
    var intervalRects: [NSRect] {
        let hourlyCount = max(0, min(days, 10)) * 24
        let intervalCount = hourlyCount == 0 ? 0 : (hourlyCount + hoursPerGroup - 1) / hoursPerGroup
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
        let hourlyCount = max(0, min(days, 10)) * 24
        let startHour = endHour - Int64(hourlyCount - 1)
        var values: [Int: Int] = [:]
        for bucket in buckets where bucket.copies > 0 {
            let offset = bucket.hour - startHour
            guard offset >= 0, offset < Int64(hourlyCount) else { continue }
            let group = Int(offset) / hoursPerGroup
            let (sum, overflow) = values[group, default: 0].addingReportingOverflow(bucket.copies)
            values[group] = overflow ? Int.max : sum
        }
        let maximum = max(1, values.values.max() ?? 0)
        let captionHeight: CGFloat = bounds.width < 100 ? 0 : 14
        return intervalRects.enumerated().compactMap { index, slot in
            let value = values[index] ?? 0
            guard value > 0 else { return nil }
            let height = (bounds.height - captionHeight) * CGFloat(value) / CGFloat(maximum)
            guard height.isFinite, height > 0 else { return nil }
            return NSRect(x: slot.minX, y: bounds.height - captionHeight - height, width: slot.width, height: height)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        for rect in renderedBarRects {
            guard rect.minX.isFinite, rect.minY.isFinite, rect.width.isFinite, rect.height.isFinite,
                  rect.width >= 0, rect.height >= 0, bounds.contains(rect) else { continue }
            NSColor.systemBlue.setFill()
            rect.fill()
        }
        guard showsRangeCaptions else { return }
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
