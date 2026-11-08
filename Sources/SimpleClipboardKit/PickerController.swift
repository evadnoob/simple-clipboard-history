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
    /// A compact one-line picker and its bottom bar, also valid as a saved height cap.
    static let minimumSize = NSSize(width: 280, height: PickerView.compactHeight)
    private static let widthKey = "pickerManualWidth"
    private static let presetKey = "pickerLastWidthPreset"
    private static let heightKey = "pickerHeight"
    private let defaults: UserDefaults
    private let screenFrame: (() -> NSRect?)?
    private var resizeStartSize: NSSize?

    private lazy var panel: FloatingPanel = {
        // An unflipped container holds the picker and, above it, the four corner squares that resize the panel.
        let container = NSView(frame: NSRect(origin: .zero, size: InterfaceStyle.pickerSize))
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
        for corner in [WindowCorner.bottomLeft, .bottomRight, .topLeft, .topRight] {
            let cornerView = WindowCornerView(corner: corner)
            cornerView.place(in: container)
            cornerView.onResizeStarted = { [weak self] frame in self?.resizeStartSize = frame.size }
            cornerView.onResizeEnded = { [weak self] frame in self?.finishResize(frame) }
            container.addSubview(cornerView)
        }
        let panel = FloatingPanel(contentView: container, size: InterfaceStyle.pickerSize, resizable: true)
        panel.minSize = Self.minimumSize
        panel.delegate = self
        return panel
    }()

    /// The size the user last gave the picker, or the default.
    var savedSize: NSSize {
        let preset = settingsStore.settings.pickerWidth
        let lastPreset = defaults.object(forKey: Self.presetKey) as? Int
        let manual = defaults.double(forKey: Self.widthKey)
        let width = lastPreset == preset && manual.isFinite && manual >= Self.minimumSize.width ? manual : Double(preset)
        let height = defaults.double(forKey: Self.heightKey)
        return NSSize(width: width, height: height.isFinite && height >= Self.minimumSize.height ? height : 10_000)
    }

    func saveSize(_ size: NSSize, widthChanged: Bool = true, heightChanged: Bool = true) {
        // A temporarily compact height must never discard an otherwise valid manual width.
        if widthChanged && size.width.isFinite && size.width >= Self.minimumSize.width {
            defaults.set(Double(size.width), forKey: Self.widthKey)
            defaults.set(settingsStore.settings.pickerWidth, forKey: Self.presetKey)
        }
        if heightChanged && size.height.isFinite && size.height >= Self.minimumSize.height {
            defaults.set(Double(size.height), forKey: Self.heightKey)
        }
        resizeToContent()
    }

    private func resizeToContent(centered: Bool = false) {
        let visible = screenFrame?() ?? (centered ? Self.screenWithMouse() : panel.screen ?? Self.screenWithMouse())?.visibleFrame
        let available = NSSize(width: max(1, (visible?.width ?? 1440) - 40),
                               height: max(1, (visible?.height ?? 900) - 40))
        let saved = savedSize
        panel.minSize = NSSize(width: min(Self.minimumSize.width, available.width),
                               height: min(view.minimumContentHeight, available.height))
        panel.maxSize = available
        let size = NSSize(width: min(saved.width, available.width),
                          height: view.desiredHeight(cap: saved.height, screenHeight: available.height))
        var frame = NSRect(x: panel.frame.minX, y: panel.frame.maxY - size.height, width: size.width, height: size.height)
        if centered, let visible {
            frame.origin = NSPoint(x: floor(visible.midX - size.width / 2),
                                   y: floor(min(visible.maxY - size.height - 20,
                                                visible.midY - size.height / 2 + visible.height * 0.1)))
        }
        if let visible {
            frame.origin.x = min(max(frame.minX, visible.minX + 20), visible.maxX - 20 - frame.width)
            frame.origin.y = min(max(frame.minY, visible.minY + 20), visible.maxY - 20 - frame.height)
        }
        panel.setFrame(frame, display: true)
        view.updateRowCount()
    }

    /// Compare against the start of either resize route, not the saved content-height cap.
    private func finishResize(_ frame: NSRect) {
        guard let start = resizeStartSize else { return }
        resizeStartSize = nil
        saveSize(frame.size, widthChanged: abs(frame.width - start.width) > 0.5,
                 heightChanged: abs(frame.height - start.height) > 0.5)
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        resizeStartSize = panel.frame.size
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        finishResize(panel.frame)
    }

    init(store: ClipStore, settingsStore: SettingsStore, monitor: ClipboardMonitor, defaults: UserDefaults = .standard,
         model: PickerModel? = nil, screenFrame: (() -> NSRect?)? = nil) {
        self.defaults = defaults
        self.screenFrame = screenFrame
        self.store = store
        self.settingsStore = settingsStore
        self.monitor = monitor
        self.model = model ?? PickerModel(search: { query, limit in (try? store.search(query, limit: limit)) ?? [] })
        view = PickerView(model: self.model)
        super.init()
        view.onContentChanged = { [weak self] in self?.resizeToContent() }
        view.loadItems = { id in (try? store.items(for: id)) ?? [] }
        view.loadThumbnail = { id, pixelSize in try? store.thumbnail(for: id, maximumPixelSize: pixelSize) }
        view.onAction = { [weak self] action in self?.handle(action) }
    }

    var isOpen: Bool { panel.isVisible }

    func toggle() {
        if isOpen { close() } else { open() }
    }

    func open() {
        prepareToOpen()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(view)
    }

    /// Prepares the real panel without ordering it front; the harness uses this with synthetic rows and screens.
    func prepareToOpen() {
        view.resetThumbnailCache()
        model.reset()
        view.settings = settingsStore.settings
        view.recallVerb = settingsStore.settings.recallMode == .paste ? "paste" : "copy"
        model.alwaysPastePlainText = settingsStore.settings.alwaysPastePlainText
        view.updateRowCount()
        view.needsDisplay = true
        resizeToContent(centered: true)
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
