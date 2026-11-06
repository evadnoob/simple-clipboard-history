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
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "clipboard"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit Simple Clipboard", action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }
}
