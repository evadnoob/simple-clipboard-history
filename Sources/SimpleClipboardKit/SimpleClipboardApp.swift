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
    private var menuController: StatusMenuController?

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
        menuController = StatusMenuController(store: store, settingsStore: settingsStore, monitor: monitor)
        monitor.start()
        self.monitor = monitor
    }
}
