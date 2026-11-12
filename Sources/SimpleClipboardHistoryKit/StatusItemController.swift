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
    private let loginItem: LoginItemController
    let panelView = SettingsPanelView()
    private lazy var panelController: SettingsPanelWindowController = {
        let controller = SettingsPanelWindowController(view: panelView) { [weak self] in
            let window = self?.statusItem.button?.window
            return (window?.frame, (window?.screen ?? NSScreen.main)?.visibleFrame
                    ?? NSRect(x: 0, y: 0, width: 800, height: 600))
        }
        controller.panel.delegate = self
        return controller
    }()
    private var panel: FloatingPanel { panelController.panel }
    /// The app in front when the panel opened. The panel does not activate Simple Clipboard History, so this is the
    /// user's app.
    private var frontmostApp: NSRunningApplication?
    /// When the panel last closed because it lost the keyboard. A click on the menu bar item closes the panel
    /// that way just before the click's action arrives; the action must not reopen it.
    private var closedByResignAt = Date.distantPast

    init(store: ClipStore, settingsStore: SettingsStore, monitor: ClipboardMonitor, picker: PickerController,
         hotkey: GlobalHotkey, loginItem: LoginItemController = LoginItemController()) {
        self.loginItem = loginItem
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
        if let button = statusItem.button { Self.configureStatusButton(button, paused: false) }
        panelView.actions = makeActions()
        monitor.onChange = { [weak self] in self?.refresh() }
        refresh()
    }

    /// A template image, so macOS colors it for the menu bar in light and dark mode.
    static let icon: NSImage = {
        let image = ClipboardIcon.image(size: NSSize(width: 16, height: 17.33), accessibilityDescription: "Simple Clipboard History")
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

    static func configureStatusButton(_ button: NSStatusBarButton, paused: Bool) {
        button.image = icon
        button.setAccessibilityLabel(paused ? "Simple Clipboard History, capture paused" : "Simple Clipboard History")
        button.toolTip = nil
        button.appearsDisabled = paused
    }

    private func updateIcon() {
        statusItem.button?.title = "" // Statistics belong only inside the panel.
        if let button = statusItem.button { Self.configureStatusButton(button, paused: settingsStore.settings.capturePaused) }
    }

    // MARK: panel

    @objc private func togglePanel() {
        if panel.isVisible { closePanel(); return }
        if Date().timeIntervalSince(closedByResignAt) < 0.3 { return }
        openPanel()
    }

    func openPanel(page: SettingsPanelView.Page = .main) {
        frontmostApp = NSWorkspace.shared.frontmostApplication
        statistics = try? store.statistics()
        panelController.prepareToOpen(content(), page: page)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(panelView)
    }

    func closePanel() {
        panel.orderOut(nil)
        panelView.resetInteraction()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard panel.isVisible else { return }
        closedByResignAt = Date()
        closePanel()
    }

    private func showContent() {
        panelController.show(content())
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
        let now = Date()
        let activityStart = now.addingTimeInterval(-Double(5 * 24 - 1) * 3600)
        let activity = (try? store.copyActivity(from: activityStart, through: now)) ?? []
        return SettingsPanelContent(settings: settings, statistics: statistics, clipboardLine: clipboardLine(),
                                    frontmostApp: front.map { (identifier: $0.0, name: $0.1) }, notices: notices,
                                    appNames: names, hotkeyLabel: hotkeyLabel,
                                    loginEnabled: loginItem.isEnabled, loginMessage: loginItem.message,
                                    now: now, copyActivity: activity)
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
        actions.setLoginEnabled = { [weak self] enabled in
            self?.loginItem.setEnabled(enabled)
            self?.refresh()
        }
        actions.openLoginSettings = { [weak self] in self?.loginItem.openSettings() }
        actions.quit = { NSApplication.shared.terminate(nil) }
        actions.close = { [weak self] in self?.closePanel() }
        return actions
    }

    // MARK: text

    private func clipboardLine() -> String {
        guard let current = monitor.current else { return "no copy since Simple Clipboard History started" }
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

/// Owns the production settings window's sizing path, including view-only confirmation changes.
/// Placement is injectable so window fitting can be checked without a status item or live history.
final class SettingsPanelWindowController {
    let panel: FloatingPanel
    private let view: SettingsPanelView
    private let placement: () -> (anchor: NSRect?, visibleFrame: NSRect)

    init(view: SettingsPanelView,
         placement: @escaping () -> (anchor: NSRect?, visibleFrame: NSRect)) {
        self.view = view
        self.placement = placement
        panel = FloatingPanel(contentView: view, size: view.frame.size)
        view.onPreferredSizeChange = { [weak self] in self?.resizeToFit() }
    }

    func prepareToOpen(_ content: SettingsPanelContent, page: SettingsPanelView.Page = .main) {
        view.resetInteraction(page: page)
        show(content)
    }

    func show(_ content: SettingsPanelContent) {
        view.show(content)
        resizeToFit()
    }

    func resizeToFit() {
        let (anchor, visible) = placement()
        let top = floor(min(anchor.map { $0.minY - 4 } ?? visible.maxY - 4, visible.maxY - 4))
        let bottom = ceil(visible.minY + 4)
        view.maximumHeight = max(1, top - bottom)
        let size = view.frame.size
        let x = min(max(visible.minX + 4, anchor?.minX ?? visible.midX - size.width / 2),
                    visible.maxX - size.width - 4)
        panel.setFrame(NSRect(x: floor(x), y: top - size.height, width: size.width, height: size.height), display: true)
    }
}
