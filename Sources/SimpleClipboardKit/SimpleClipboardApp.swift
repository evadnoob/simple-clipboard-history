import AppKit

/// Entry point. The app has no Dock icon and no windows; it lives in the menu bar.
public enum SimpleClipboardApp {
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

    /// The same local callback chain is exercised with synthetic panel content in the harness.
    static func connectControlPanelNavigation(picker: PickerController,
                                          openPanel: @escaping (SettingsPanelView.Page) -> Void) {
        picker.onOpenControlPanel = { openPanel(.main) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settingsStore = SettingsStore()
        let store: ClipStore
        do {
            store = try ClipStore(directory: ClipStore.defaultDirectory())
        } catch {
            let alert = NSAlert()
            alert.messageText = "Simple Clipboard cannot open its history"
            alert.informativeText = "\(error)"
            alert.runModal()
            NSApplication.shared.terminate(nil)
            return
        }
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
