import AppKit

/// The menu bar item: a clipboard icon, dimmed while capture is paused. Clicking it opens the settings panel
/// under it; clicking it again, pressing Esc or clicking elsewhere closes the panel.
final class StatusItemController: NSObject, NSWindowDelegate {
    private let statusItem: NSStatusItem
    private let store: ClipStore
    private let settingsStore: SettingsStore
    private let monitor: ClipboardMonitor
    private let picker: PickerController
    private let hotkey: GlobalHotkey
    private var statistics: StoreStatistics?
    let panelView = SettingsPanelView()
    private lazy var panel: FloatingPanel = {
        let panel = FloatingPanel(contentView: panelView, size: panelView.frame.size)
        panel.delegate = self
        return panel
    }()
    /// The app in front when the panel opened. The panel does not activate Simple Clipboard, so this is the
    /// user's app.
    private var frontmostApp: NSRunningApplication?
    /// When the panel last closed because it lost the keyboard. A click on the menu bar item closes the panel
    /// that way just before the click's action arrives; the action must not reopen it.
    private var closedByResignAt = Date.distantPast

    init(store: ClipStore, settingsStore: SettingsStore, monitor: ClipboardMonitor, picker: PickerController,
         hotkey: GlobalHotkey) {
        self.store = store
        self.settingsStore = settingsStore
        self.monitor = monitor
        self.picker = picker
        self.hotkey = hotkey
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        statusItem.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
        statusItem.button?.image = Self.icon
        statusItem.button?.toolTip = "Simple Clipboard"
        panelView.actions = makeActions()
        monitor.onChange = { [weak self] in self?.refresh() }
        refresh()
    }

    /// A template image, so macOS colors it for the menu bar in light and dark mode.
    static let icon: NSImage = {
        let image = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "Simple Clipboard")
            ?? NSImage(size: NSSize(width: 16, height: 16))
        image.isTemplate = true
        return image
    }()

    /// True when the icon is dimmed, for tests.
    var iconDimmed: Bool { statusItem.button?.appearsDisabled ?? false }

    private func refresh() {
        statistics = try? store.statistics()
        updateIcon()
        if panel.isVisible { showContent() }
    }

    private func updateIcon() {
        let paused = settingsStore.settings.capturePaused
        statusItem.button?.appearsDisabled = paused
        statusItem.button?.toolTip = paused ? "Simple Clipboard (capture paused)" : "Simple Clipboard"
    }

    // MARK: panel

    @objc private func togglePanel() {
        if panel.isVisible { closePanel(); return }
        if Date().timeIntervalSince(closedByResignAt) < 0.3 { return }
        openPanel()
    }

    func openPanel() {
        frontmostApp = NSWorkspace.shared.frontmostApplication
        statistics = try? store.statistics()
        panelView.resetInteraction()
        showContent()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(panelView)
    }

    func closePanel() {
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard panel.isVisible else { return }
        closedByResignAt = Date()
        closePanel()
    }

    private func showContent() {
        panelView.show(content())
        panel.setFrame(panelFrame(for: panelView.frame.size), display: true)
    }

    func content() -> SettingsPanelContent {
        let settings = settingsStore.settings
        var front: (String, String)?
        if let app = frontmostApp, let identifier = app.bundleIdentifier, identifier != Bundle.main.bundleIdentifier {
            front = (identifier, app.localizedName ?? identifier)
        }
        var notices: [PanelNotice] = []
        if settings.recallMode == .paste && !Recall.hasAccessibility { notices.append(.needsAccessibility) }
        if case .failed(let choice, _) = hotkey.status { notices.append(.hotkeyUnavailable(choice)) }
        var names: [String: String] = [:]
        for identifier in settings.ignoredApps { names[identifier] = Self.appName(identifier) }
        var hotkeyLabel: String?
        if case .registered(let choice) = hotkey.status {
            hotkeyLabel = SettingsPanelView.hotkeyTitles.first { $0.0 == choice }?.1
        }
        return SettingsPanelContent(settings: settings, statistics: statistics, clipboardLine: clipboardLine(),
                                    frontmostApp: front.map { (identifier: $0.0, name: $0.1) }, notices: notices,
                                    appNames: names, hotkeyLabel: hotkeyLabel)
    }

    /// Under the menu bar item, kept on its screen.
    private func panelFrame(for size: NSSize) -> NSRect {
        guard let buttonWindow = statusItem.button?.window else {
            return PickerController.frame(for: size, on: NSScreen.main)
        }
        let anchor = buttonWindow.frame
        let screen = buttonWindow.screen ?? NSScreen.main
        var x = anchor.minX
        if let visible = screen?.visibleFrame {
            x = min(max(visible.minX + 4, x), visible.maxX - size.width - 4)
        }
        return NSRect(x: floor(x), y: floor(anchor.minY - size.height - 4), width: size.width, height: size.height)
    }

    private func makeActions() -> SettingsPanelActions {
        var actions = SettingsPanelActions()
        actions.update = { [weak self] change in
            guard let self else { return }
            let before = self.settingsStore.settings
            self.settingsStore.update(change)
            let after = self.settingsStore.settings
            if after.recallMode == .paste && before.recallMode != .paste && !Recall.hasAccessibility {
                Recall.requestAccessibility()
            }
            self.refresh()
        }
        actions.keepHistory = { [weak self] limit in
            guard let self else { return }
            self.settingsStore.update { $0.historyLimit = limit }
            _ = try? self.store.enforceLimit(limit)
            self.refresh()
        }
        actions.clearHistory = { [weak self] in
            try? self?.store.deleteAll()
            self?.refresh()
        }
        actions.openPicker = { [weak self] in
            self?.closePanel()
            DispatchQueue.main.async { self?.picker.open() }
        }
        actions.openNotice = { [weak self] notice in
            switch notice {
            case .needsAccessibility:
                self?.closePanel()
                Recall.requestAccessibility()
            case .hotkeyUnavailable:
                // Retry, in case the other app has quit since.
                if let self { self.hotkey.register(self.settingsStore.settings.pickerHotkey); self.refresh() }
            }
        }
        actions.quit = { NSApplication.shared.terminate(nil) }
        actions.close = { [weak self] in self?.closePanel() }
        return actions
    }

    // MARK: text

    private func clipboardLine() -> String {
        guard let current = monitor.current else { return "no copy since Simple Clipboard started" }
        let source = current.sourceAppName.map { " from \($0)" } ?? ""
        switch current.state {
        case .recorded(let clip):
            return "\(clip.kind), \(Format.bytes(clip.byteSize))\(source)"
        case .skipped(let reason):
            return "not recorded\(source): " + Self.describe(reason)
        case .failed(let message):
            return "not recorded: \(message)"
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

    static func appName(_ bundleIdentifier: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return bundleIdentifier
        }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}
