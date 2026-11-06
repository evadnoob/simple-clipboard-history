import AppKit

/// A borderless panel that takes keys without activating Simple Clipboard, so the app the user was in stays the
/// active app. That is where a pasted clip goes when the picker closes. The settings panel uses it too.
final class FloatingPanel: NSPanel {
    init(contentView: NSView, size: NSSize, resizable: Bool = false) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: resizable ? [.borderless, .nonactivatingPanel, .resizable] : [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        self.contentView = contentView
        isFloatingPanel = true
        level = .modalPanel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Opens and closes the picker and recalls the chosen clip.
final class PickerController: NSObject, NSWindowDelegate {
    private let store: ClipStore
    private let settingsStore: SettingsStore
    private let monitor: ClipboardMonitor
    let model: PickerModel
    let view: PickerView
    /// Smallest picker size: a few rows and the bar.
    static let minimumSize = NSSize(width: 420, height: 200)
    private static let widthKey = "pickerWidth"
    private static let heightKey = "pickerHeight"
    private let defaults: UserDefaults

    private lazy var panel: FloatingPanel = {
        // An unflipped container holds the picker and, above it, the four corner squares that resize the panel.
        let container = NSView(frame: NSRect(origin: .zero, size: InterfaceStyle.pickerSize))
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
        for corner in [WindowCorner.bottomLeft, .bottomRight, .topLeft, .topRight] {
            let cornerView = WindowCornerView(corner: corner)
            cornerView.place(in: container)
            cornerView.onResizeEnded = { [weak self] frame in self?.saveSize(frame.size) }
            container.addSubview(cornerView)
        }
        let panel = FloatingPanel(contentView: container, size: InterfaceStyle.pickerSize, resizable: true)
        panel.minSize = Self.minimumSize
        panel.delegate = self
        return panel
    }()

    /// The size the user last gave the picker, or the default.
    var savedSize: NSSize {
        let width = defaults.double(forKey: Self.widthKey)
        let height = defaults.double(forKey: Self.heightKey)
        guard width >= Self.minimumSize.width, height >= Self.minimumSize.height else { return InterfaceStyle.pickerSize }
        return NSSize(width: width, height: height)
    }

    func saveSize(_ size: NSSize) {
        defaults.set(Double(size.width), forKey: Self.widthKey)
        defaults.set(Double(size.height), forKey: Self.heightKey)
    }

    /// Edge resizes go through the system; corner resizes report through `onResizeEnded`.
    func windowDidEndLiveResize(_ notification: Notification) {
        saveSize(panel.frame.size)
    }

    init(store: ClipStore, settingsStore: SettingsStore, monitor: ClipboardMonitor, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.store = store
        self.settingsStore = settingsStore
        self.monitor = monitor
        model = PickerModel(search: { query, limit in (try? store.search(query, limit: limit)) ?? [] })
        view = PickerView(model: model)
        super.init()
        view.loadItems = { id in (try? store.items(for: id)) ?? [] }
        view.onAction = { [weak self] action in self?.handle(action) }
    }

    var isOpen: Bool { panel.isVisible }

    func toggle() {
        if isOpen { close() } else { open() }
    }

    func open() {
        model.reset()
        view.recallVerb = settingsStore.settings.recallMode == .paste ? "paste" : "copy"
        model.alwaysPastePlainText = settingsStore.settings.alwaysPastePlainText
        view.updateRowCount()
        view.needsDisplay = true
        panel.setFrame(Self.frame(for: savedSize, on: Self.screenWithMouse()), display: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(view)
    }

    func close() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
    }

    private func handle(_ action: PickerAction) {
        switch action {
        case .none: break
        case .close: close()
        case .recall(let id, let format): recall(id, format: format)
        }
    }

    private func recall(_ id: Int64, format: RecallFormat) {
        guard let items = try? store.items(for: id), !items.isEmpty else { NSSound.beep(); return }
        // A filter that does not apply leaves the picker open, so another filter can be chosen.
        guard Recall.items(for: items, format: format) != nil else { NSSound.beep(); return }
        close()
        let outcome = Recall.perform(items: items, mode: settingsStore.settings.recallMode, format: format)
        if outcome == .needsAccessibility { Recall.requestAccessibility() }
        try? store.touch(id)
        if let clip = try? store.recent(limit: 1).first { monitor.noteOwnWrite(clip: clip) }
    }

    /// Closing when the panel loses the keyboard, for example after a click in another app.
    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    static func screenWithMouse() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) } ?? NSScreen.main
    }

    /// Centered horizontally, a little above the middle of the visible area.
    static func frame(for size: NSSize, on screen: NSScreen?) -> NSRect {
        guard let visible = screen?.visibleFrame else { return NSRect(origin: .zero, size: size) }
        let width = min(size.width, visible.width - 40)
        let height = min(size.height, visible.height - 40)
        let x = visible.midX - width / 2
        let y = min(visible.maxY - height - 20, visible.midY - height / 2 + visible.height * 0.1)
        return NSRect(x: floor(x), y: floor(y), width: width, height: height)
    }
}
