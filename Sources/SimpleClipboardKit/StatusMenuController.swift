import AppKit

/// The menu bar item: a text title with the clip count and the age of the last copy, and a plain menu with
/// clipboard statistics, recent clips and commands. The menu is rebuilt each time it opens.
final class StatusMenuController: NSObject, NSMenuDelegate {
    static let recentClipCount = 10

    private let statusItem: NSStatusItem
    private let store: ClipStore
    private let settingsFile: SettingsFile
    private let monitor: ClipboardMonitor
    private var timer: Timer?
    private var statistics: StoreStatistics?
    private var lastRecallOutcome: Recall.Outcome?

    init(store: ClipStore, settingsFile: SettingsFile, monitor: ClipboardMonitor) {
        self.store = store
        self.settingsFile = settingsFile
        self.monitor = monitor
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        monitor.onChange = { [weak self] in self?.refreshStatistics() }
        refreshStatistics()
        // Every 2 seconds: reload the settings file if it changed, and update the age in the title.
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            self?.settingsFile.reloadIfChanged()
            self?.updateTitle()
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func refreshStatistics() {
        statistics = try? store.statistics()
        updateTitle()
    }

    private func updateTitle() {
        let title = Format.statusTitle(clipCount: statistics?.clipCount ?? 0,
                                       lastCopiedAt: statistics?.latest?.lastCopiedAt, now: Date(),
                                       paused: monitor.paused)
        guard statusItem.button?.title != title else { return }
        statusItem.button?.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
        ])
    }

    // MARK: menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshStatistics()
        menu.removeAllItems()
        let now = Date()

        menu.addItem(header("Clipboard"))
        menu.addItem(info(currentClipboardLine()))

        menu.addItem(.separator())
        menu.addItem(header("History"))
        if let statistics {
            menu.addItem(info("\(statistics.clipCount) clips, \(Format.bytes(statistics.clipBytes)) copied, "
                              + "\(Format.bytes(statistics.diskBytes)) on disk"))
            if let oldest = statistics.oldestCopiedAt { menu.addItem(info("Oldest clip: \(Format.dateTime(oldest))")) }
            if let latest = statistics.latest {
                var line = "Last copy: \(Format.age(from: latest.lastCopiedAt, to: now)) ago"
                if let app = latest.sourceAppName { line += " in \(app)" }
                menu.addItem(info(line))
            }
        } else {
            menu.addItem(info("History is not available"))
        }

        let recent = (try? store.recent(limit: Self.recentClipCount)) ?? []
        if !recent.isEmpty {
            menu.addItem(.separator())
            menu.addItem(header("Recent clips"))
            for (index, clip) in recent.enumerated() {
                let item = NSMenuItem(title: Format.menuPreview(clip.preview), action: #selector(recallClip(_:)),
                                      keyEquivalent: index < 9 ? "\(index + 1)" : "")
                item.target = self
                item.representedObject = clip.id
                item.toolTip = "\(clip.kind), \(Format.bytes(clip.byteSize)), copied \(clip.copyCount) times"
                    + (clip.sourceAppName.map { ", last in \($0)" } ?? "")
                menu.addItem(item)
            }
        }

        let notices = noticeItems()
        if !notices.isEmpty {
            menu.addItem(.separator())
            notices.forEach(menu.addItem)
        }

        menu.addItem(.separator())
        let pause = NSMenuItem(title: "Pause Capture", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        pause.state = monitor.paused ? .on : .off
        menu.addItem(pause)
        let settings = NSMenuItem(title: "Open Settings File", action: #selector(openSettingsFile), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(NSMenuItem(title: "Quit Simple Clipboard", action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
    }

    private func currentClipboardLine() -> String {
        guard let current = monitor.current else { return "No copy since Simple Clipboard started" }
        let source = current.sourceAppName.map { " from \($0)" } ?? ""
        switch current.state {
        case .recorded(let clip):
            return "\(clip.kind), \(Format.bytes(clip.byteSize))\(source)"
        case .skipped(let reason):
            return "Not recorded\(source): " + Self.describe(reason)
        case .failed(let message):
            return "Not recorded: \(message)"
        }
    }

    static func describe(_ reason: SkipReason) -> String {
        switch reason {
        case .concealed: return "marked concealed"
        case .ignoredApp(let identifier): return "\(identifier) is ignored"
        case .tooLarge(let bytes): return "larger than the limit (\(Format.bytes(bytes)) read)"
        case .empty: return "empty"
        case .paused: return "capture paused"
        }
    }

    private func noticeItems() -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        if settingsFile.settings.recallMode == .paste && !Recall.hasAccessibility {
            let item = NSMenuItem(title: "Paste needs Accessibility permission\u{2026}",
                                  action: #selector(openAccessibility), keyEquivalent: "")
            item.target = self
            item.toolTip = "Recall mode is \"paste\". Until Accessibility is granted, clips go on the clipboard only."
            items.append(item)
        }
        for problem in settingsFile.problems {
            let item = NSMenuItem(title: "Settings: \(problem)", action: #selector(openSettingsFile), keyEquivalent: "")
            item.target = self
            items.append(item)
        }
        return items
    }

    private func header(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        item.isEnabled = false
        return item
    }

    private func info(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: actions

    @objc private func recallClip(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? Int64,
              let items = try? store.items(for: id), !items.isEmpty else { NSSound.beep(); return }
        lastRecallOutcome = Recall.perform(items: items, mode: settingsFile.settings.recallMode)
        try? store.touch(id)
        if let clip = try? store.recent(limit: 1).first { monitor.noteOwnWrite(clip: clip) }
    }

    @objc private func togglePause() {
        monitor.paused.toggle()
        updateTitle()
    }

    @objc private func openSettingsFile() {
        do {
            try settingsFile.createIfMissing()
        } catch {
            NSSound.beep()
            return
        }
        let url = settingsFile.url
        if NSWorkspace.shared.urlForApplication(toOpen: url) != nil {
            NSWorkspace.shared.open(url)
        } else if let textEdit = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") {
            NSWorkspace.shared.open([url], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    @objc private func openAccessibility() {
        Recall.openAccessibilitySettings()
    }
}
