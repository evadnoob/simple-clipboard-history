import AppKit

/// What the menu shows about the clipboard right now.
struct CurrentClipboard: Equatable {
    enum State: Equatable {
        case recorded(ClipSummary)
        case skipped(SkipReason)
        case failed(String)
    }
    var changeCount: Int
    var state: State
    var sourceAppName: String?
}

/// Polls the pasteboard change counter. Reading the counter is cheap; contents are read only after a change.
/// macOS has no clipboard change notification, so every clipboard manager polls.
final class ClipboardMonitor {
    static let interval: TimeInterval = 0.25

    private let pasteboard: NSPasteboard
    private let store: ClipStore
    private let settings: () -> Settings
    private var timer: Timer?
    private var lastChangeCount: Int
    /// The change count produced by our own recall write. That write is not recorded again.
    private var ownChangeCount: Int?

    private(set) var current: CurrentClipboard?
    /// Called on the main thread after each pasteboard change.
    var onChange: (() -> Void)?

    init(pasteboard: NSPasteboard = .general, store: ClipStore, settings: @escaping () -> Settings) {
        self.pasteboard = pasteboard
        self.store = store
        self.settings = settings
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in self?.poll() }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Call right after writing a recalled clip, so the write is not recorded as a new copy.
    func noteOwnWrite(clip: ClipSummary) {
        ownChangeCount = pasteboard.changeCount
        lastChangeCount = pasteboard.changeCount
        current = CurrentClipboard(changeCount: pasteboard.changeCount, state: .recorded(clip),
                                   sourceAppName: "Simple Clipboard")
        onChange?()
    }

    func poll() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount
        if changeCount == ownChangeCount { return }
        let sourceApp = NSWorkspace.shared.frontmostApplication
        var state: CurrentClipboard.State
        let settings = settings()
        if settings.capturePaused {
            state = .skipped(.paused)
        } else {
            switch Capture.read(pasteboard, sourceApp: sourceApp, settings: settings) {
            case .failure(let reason):
                state = .skipped(reason)
            case .success(let clip):
                do {
                    let id = try store.record(clip)
                    try store.enforceLimit(settings.historyLimit)
                    if let summary = try store.recent(limit: 1).first, summary.id == id {
                        state = .recorded(summary)
                    } else {
                        state = .failed("recorded clip not found")
                    }
                } catch {
                    state = .failed("\(error)")
                }
            }
        }
        current = CurrentClipboard(changeCount: changeCount, state: state, sourceAppName: sourceApp?.localizedName)
        onChange?()
    }
}
