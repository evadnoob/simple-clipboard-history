import AppKit

/// Entry point. The app has no Dock icon and no windows; it lives in the menu bar.
public enum SimpleClipboardHistoryApp {
    public static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var monitor: ClipboardMonitor?
    private var statusItemController: StatusItemController?
    private var picker: PickerController?
    private var hotkey: GlobalHotkey?

    static func migrateHistory(to destination: URL, environment: [String: String] = ProcessInfo.processInfo.environment,
                               fileManager: FileManager = .default,
                               isLegacyAppRunning: () -> Bool = {
                                   NSWorkspace.shared.runningApplications.contains {
                                       $0.bundleIdentifier == SettingsStore.legacyBundleIdentifier
                                   }
                               },
                               move: ((URL, URL) throws -> Void)? = nil) throws {
        guard ClipStore.dataOverride(environment: environment) == nil else { return }
        let source = destination.deletingLastPathComponent().appendingPathComponent("simple-clipboard", isDirectory: true)
        guard fileManager.fileExists(atPath: source.path), !fileManager.fileExists(atPath: destination.path) else { return }
        guard !isLegacyAppRunning() else { throw HistoryMigrationError.legacyAppRunning }
        try (move ?? { try fileManager.moveItem(at: $0, to: $1) })(source, destination)
    }

    enum HistoryMigrationError: LocalizedError {
        case legacyAppRunning
        var errorDescription: String? {
            "The older Simple Clipboard app is still running. Quit it, then launch Simple Clipboard History again."
        }
    }

    /// The same local callback chain is exercised with synthetic panel content in the harness.
    static func connectControlPanelNavigation(picker: PickerController,
                                          openPanel: @escaping (SettingsPanelView.Page) -> Void) {
        picker.onOpenControlPanel = { openPanel(.main) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store: ClipStore
        do {
            let destination = ClipStore.defaultDirectory()
            try Self.migrateHistory(to: destination)
            SettingsStore.migrateLegacySettings(defaults: .standard)
            store = try ClipStore(directory: destination)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Simple Clipboard History cannot open its history"
            alert.informativeText = "\(error)\nIf this is a storage error, check that the Application Support folder is writable. Existing history was not intentionally discarded."
            alert.runModal()
            NSApplication.shared.terminate(nil)
            return
        }
        let settingsStore = SettingsStore()
        let monitor = ClipboardMonitor(store: store, settings: { settingsStore.settings })
        let picker = PickerController(store: store, settingsStore: settingsStore, monitor: monitor)
        let hotkey = GlobalHotkey { [weak picker] in picker?.toggle() }
        hotkey.register(settingsStore.settings.pickerHotkey)
        let statusItemController = StatusItemController(store: store, settingsStore: settingsStore, monitor: monitor,
                                                  picker: picker, hotkey: hotkey)
        Self.connectControlPanelNavigation(picker: picker) { [weak statusItemController] page in
            statusItemController?.openPanel(page: page)
        }
        settingsStore.onChange = { [weak hotkey, weak monitor, weak picker] settings in
            if let hotkey, hotkey.status != .registered(settings.pickerHotkey) { hotkey.register(settings.pickerHotkey) }
            picker?.applySettings()
            monitor?.enforceRetention()
        }
        monitor.start()
        self.picker = picker
        self.hotkey = hotkey
        self.statusItemController = statusItemController
        self.monitor = monitor
    }
}
