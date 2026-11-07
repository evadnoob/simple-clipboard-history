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
    private var retentionTimer: Timer?
    private var lastChangeCount: Int
    /// The change count produced by our own recall write. That write is not recorded again.
    private var ownChangeCount: Int?

    private var clipboardCurrent: CurrentClipboard?
    private var retentionError: String?
    private var previewError: String?
    private let previewQueue: DispatchQueue
    private var previewGeneration: UUID?

    /// Maintenance errors overlay, rather than replace, the last genuine clipboard event.
    var current: CurrentClipboard? {
        guard let error = retentionError ?? previewError else { return clipboardCurrent }
        return CurrentClipboard(changeCount: clipboardCurrent?.changeCount ?? lastChangeCount,
                                state: .failed(error), sourceAppName: clipboardCurrent?.sourceAppName)
    }
    /// Called on the main thread after a pasteboard change or maintenance batch.
    var onChange: (() -> Void)?

    init(pasteboard: NSPasteboard = .general, store: ClipStore, settings: @escaping () -> Settings,
         previewQueue: DispatchQueue = DispatchQueue(label: "simple-clipboard.preview-backfill", qos: .utility)) {
        self.pasteboard = pasteboard
        self.store = store
        self.settings = settings
        self.previewQueue = previewQueue
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard timer == nil else { return }
        enforceRetention()
        let retentionTimer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in self?.enforceRetention() }
        retentionTimer.tolerance = 300
        RunLoop.main.add(retentionTimer, forMode: .common)
        self.retentionTimer = retentionTimer
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in self?.poll() }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        let generation = UUID()
        previewGeneration = generation
        schedulePreviewBatch(generation)
    }

    private func schedulePreviewBatch(_ generation: UUID) {
        previewQueue.async { [weak self] in
            guard let self else { return }
            let result = Result { try self.store.backfillContentPreviewBatch() }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.previewGeneration == generation else { return }
                switch result {
                case .success(let complete):
                    self.previewError = nil
                    self.onChange?()
                    // Refresh/read on main between batches; never hold the store lock across scheduling.
                    if self.previewGeneration == generation, !complete { self.schedulePreviewBatch(generation) }
                case .failure(let error):
                    self.previewError = "Preview migration failed: \(error)"
                    self.onChange?()
                    // No retry loop: a subsequent start can resume from the durable cursor.
                }
            }
        }
    }

    func stop() {
        previewGeneration = nil
        timer?.invalidate()
        timer = nil
        retentionTimer?.invalidate()
        retentionTimer = nil
    }

    /// Call right after writing a recalled clip, so the write is not recorded as a new copy.
    func noteOwnWrite(clip: ClipSummary) {
        ownChangeCount = pasteboard.changeCount
        lastChangeCount = pasteboard.changeCount
        clipboardCurrent = CurrentClipboard(changeCount: pasteboard.changeCount, state: .recorded(clip),
                                   sourceAppName: "Simple Clipboard")
        onChange?()
    }

    @discardableResult
    func enforceRetention(now: Date = Date()) -> Int {
        let value = settings()
        defer { onChange?() }
        do {
            let removed = try store.enforceRetention(countLimit: value.historyLimit, maximumBytes: value.maximumHistoryBytes,
                                                     retentionDays: value.retentionDays, now: now)
            retentionError = nil
            return removed
        } catch {
            retentionError = "Retention failed: \(error)"
            return 0
        }
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
                    try store.enforceRetention(countLimit: settings.historyLimit, maximumBytes: settings.maximumHistoryBytes,
                                               retentionDays: settings.retentionDays)
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
        clipboardCurrent = CurrentClipboard(changeCount: changeCount, state: state, sourceAppName: sourceApp?.localizedName)
        onChange?()
    }
}
