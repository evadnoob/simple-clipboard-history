import AppKit

/// The menu bar item: a text title with the clip count and the age of the last copy, and a plain menu with
/// clipboard statistics and settings. Clips are not listed here. The menu is rebuilt each time it opens.
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let store: ClipStore
    private let settingsStore: SettingsStore
    private let monitor: ClipboardMonitor
    private let picker: PickerController
    private let hotkey: GlobalHotkey
    private var timer: Timer?
    private var statistics: StoreStatistics?
    /// The app in front when the menu opened. The menu does not activate this app, so this is the user's app.
    private var frontmostApp: NSRunningApplication?

    init(store: ClipStore, settingsStore: SettingsStore, monitor: ClipboardMonitor, picker: PickerController,
         hotkey: GlobalHotkey) {
        self.store = store
        self.settingsStore = settingsStore
        self.monitor = monitor
        self.picker = picker
        self.hotkey = hotkey
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        monitor.onChange = { [weak self] in self?.refreshStatistics() }
        refreshStatistics()
        // Every 30 seconds: update the age in the title, which changes in minute steps.
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.updateTitle() }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func refreshStatistics() {
        statistics = try? store.statistics()
        updateTitle()
    }

    private func updateTitle() {
        let title = Format.statusTitle(clipCount: statistics?.clipCount ?? 0,
                                       lastCopiedAt: statistics?.latest?.lastCopiedAt, now: Date(),
                                       paused: settingsStore.settings.capturePaused)
        guard statusItem.button?.title != title else { return }
        statusItem.button?.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
        ])
    }

    // MARK: menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        frontmostApp = NSWorkspace.shared.frontmostApplication
        refreshStatistics()
        menu.removeAllItems()
        let settings = settingsStore.settings

        let open = action("Open Picker", #selector(openPicker))
        if case .registered(let choice) = hotkey.status {
            open.keyEquivalent = "v"
            open.keyEquivalentModifierMask = choice.menuModifiers
        }
        menu.addItem(open)
        menu.addItem(.separator())

        menu.addItem(header("Clipboard"))
        menu.addItem(info(currentClipboardLine()))

        menu.addItem(.separator())
        menu.addItem(header("History"))
        if let statistics {
            menu.addItem(info("\(statistics.clipCount) clips, \(Format.bytes(statistics.clipBytes)) copied, "
                              + "\(Format.bytes(statistics.diskBytes)) on disk"))
            if let oldest = statistics.oldestCopiedAt { menu.addItem(info("Oldest clip: \(Format.dateTime(oldest))")) }
            if let latest = statistics.latest {
                var line = "Last copy: \(Format.age(from: latest.lastCopiedAt, to: Date())) ago"
                if let app = latest.sourceAppName { line += " in \(app)" }
                menu.addItem(info(line))
            }
        } else {
            menu.addItem(info("History is not available"))
        }

        var notices: [NSMenuItem] = []
        if settings.recallMode == .paste && !Recall.hasAccessibility {
            let item = action("Paste needs Accessibility permission\u{2026}", #selector(openAccessibility))
            item.toolTip = "Until Accessibility is granted, recalled clips go on the clipboard only."
            notices.append(item)
        }
        if case .failed(let choice, let code) = hotkey.status {
            let item = info("\(choice.title) is not available (another app may use it)")
            item.toolTip = "RegisterEventHotKey returned \(code). Choose another Picker Hotkey."
            notices.append(item)
        }
        if !notices.isEmpty {
            menu.addItem(.separator())
            notices.forEach(menu.addItem)
        }

        menu.addItem(.separator())
        menu.addItem(header("Settings"))
        menu.addItem(submenu("Picker Hotkey", hotkeyMenu(settings)))
        menu.addItem(submenu("Recall", recallMenu(settings)))
        menu.addItem(submenu("Keep History", historyLimitMenu(settings)))
        menu.addItem(submenu("Largest Clip", maximumClipMenu(settings)))
        menu.addItem(submenu("Ignored Apps", ignoredAppsMenu(settings)))
        let pause = action("Pause Capture", #selector(togglePause))
        pause.state = settings.capturePaused ? .on : .off
        menu.addItem(pause)

        menu.addItem(.separator())
        menu.addItem(action("Clear History\u{2026}", #selector(clearHistory)))
        menu.addItem(NSMenuItem(title: "Quit Simple Clipboard", action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
    }

    private func hotkeyMenu(_ settings: Settings) -> NSMenu {
        let menu = NSMenu()
        for choice in HotkeyChoice.allCases {
            if choice == .none { menu.addItem(.separator()) }
            let item = action(choice.title, #selector(chooseHotkey(_:)))
            item.representedObject = choice.rawValue
            item.state = settings.pickerHotkey == choice ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    private func recallMenu(_ settings: Settings) -> NSMenu {
        let menu = NSMenu()
        let choices: [(RecallMode, String)] = [(.clipboard, "Put on Clipboard"), (.paste, "Paste into Frontmost App")]
        for (mode, title) in choices {
            let item = action(title, #selector(chooseRecallMode(_:)))
            item.representedObject = mode.rawValue
            item.state = settings.recallMode == mode ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    private func historyLimitMenu(_ settings: Settings) -> NSMenu {
        let menu = NSMenu()
        var choices = Settings.historyLimitChoices
        if !choices.contains(settings.historyLimit) { choices = (choices + [settings.historyLimit]).sorted() }
        for limit in choices {
            let item = action("\(limit.formatted()) clips", #selector(chooseHistoryLimit(_:)))
            item.representedObject = limit
            item.state = settings.historyLimit == limit ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    private func maximumClipMenu(_ settings: Settings) -> NSMenu {
        let menu = NSMenu()
        var choices = Settings.maximumClipMegabyteChoices
        if !choices.contains(settings.maximumClipMegabytes) {
            choices = (choices + [settings.maximumClipMegabytes]).sorted()
        }
        for megabytes in choices {
            let item = action("\(megabytes) MB", #selector(chooseMaximumClip(_:)))
            item.representedObject = megabytes
            item.state = settings.maximumClipMegabytes == megabytes ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    private func ignoredAppsMenu(_ settings: Settings) -> NSMenu {
        let menu = NSMenu()
        if let app = frontmostApp, let identifier = app.bundleIdentifier,
           identifier != Bundle.main.bundleIdentifier, !settings.ignoredApps.contains(identifier) {
            let item = action("Ignore \(app.localizedName ?? identifier)", #selector(ignoreApp(_:)))
            item.representedObject = identifier
            menu.addItem(item)
            menu.addItem(.separator())
        }
        if settings.ignoredApps.isEmpty {
            menu.addItem(info("No ignored apps"))
        } else {
            for identifier in settings.ignoredApps {
                let item = action(Self.appName(identifier), #selector(stopIgnoringApp(_:)))
                item.representedObject = identifier
                item.state = .on
                item.toolTip = "\(identifier). Choose to record copies from this app again."
                menu.addItem(item)
            }
        }
        return menu
    }

    static func appName(_ bundleIdentifier: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return bundleIdentifier
        }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private func currentClipboardLine() -> String {
        guard let current = monitor.current else { return "No copy since Simple Clipboard started" }
        let source = current.sourceAppName.map { " from \($0)" } ?? ""
        switch current.state {
        case .recorded(let clip):
            return "\(clip.kind), \(Format.bytes(clip.byteSize))\(source)"
        case .skipped(let reason):
            return "Not recorded\(source): " + Self.describe(reason)
        case .failed(let message):
            return "Not recorded: \(message)"
        }
    }

    static func describe(_ reason: SkipReason) -> String {
        switch reason {
        case .concealed: return "marked concealed"
        case .ignoredApp(let identifier): return "\(appName(identifier)) is ignored"
        case .tooLarge(let bytes): return "larger than the limit (\(Format.bytes(bytes)) read)"
        case .empty: return "empty"
        case .paused: return "capture paused"
        }
    }

    private func header(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        item.isEnabled = false
        return item
    }

    private func info(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    private func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menu.autoenablesItems = false
        item.submenu = menu
        return item
    }

    // MARK: actions

    @objc private func openPicker() {
        // Let the menu finish closing first, so the picker becomes the key window.
        DispatchQueue.main.async { [picker] in picker.open() }
    }

    @objc private func chooseHotkey(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String, let choice = HotkeyChoice(rawValue: text) else { return }
        settingsStore.update { $0.pickerHotkey = choice }
        // Choosing the current choice again retries a registration that failed.
        if hotkey.status != .registered(choice) { hotkey.register(choice) }
    }

    @objc private func chooseRecallMode(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String, let mode = RecallMode(rawValue: text) else { return }
        settingsStore.update { $0.recallMode = mode }
        if mode == .paste && !Recall.hasAccessibility { Recall.openAccessibilitySettings() }
    }

    @objc private func chooseHistoryLimit(_ sender: NSMenuItem) {
        guard let limit = sender.representedObject as? Int else { return }
        let deleting = max(0, (statistics?.clipCount ?? 0) - limit)
        if deleting > 0 && !confirm("Keep \(limit.formatted()) clips?",
                                    "The \(deleting.formatted()) least recently copied clips will be deleted.",
                                    button: "Delete \(deleting.formatted()) Clips") {
            return
        }
        settingsStore.update { $0.historyLimit = limit }
        _ = try? store.enforceLimit(limit)
        refreshStatistics()
    }

    @objc private func chooseMaximumClip(_ sender: NSMenuItem) {
        guard let megabytes = sender.representedObject as? Int else { return }
        settingsStore.update { $0.maximumClipMegabytes = megabytes }
    }

    @objc private func ignoreApp(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String else { return }
        settingsStore.ignore(identifier)
    }

    @objc private func stopIgnoringApp(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String else { return }
        settingsStore.stopIgnoring(identifier)
    }

    @objc private func togglePause() {
        settingsStore.update { $0.capturePaused.toggle() }
        updateTitle()
    }

    @objc private func clearHistory() {
        let count = statistics?.clipCount ?? 0
        guard confirm("Clear the clipboard history?", "All \(count.formatted()) clips will be deleted.",
                      button: "Delete All Clips") else { return }
        try? store.deleteAll()
        refreshStatistics()
    }

    @objc private func openAccessibility() {
        Recall.openAccessibilitySettings()
    }

    private func confirm(_ message: String, _ detail: String, button: String) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
