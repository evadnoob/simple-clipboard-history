import Foundation

/// How choosing a clip gives it back.
enum RecallMode: String, CaseIterable {
    /// Put the clip on the clipboard. The user presses Cmd-V.
    case clipboard
    /// Put the clip on the clipboard, then send Cmd-V to the frontmost app. Needs Accessibility.
    case paste
}

/// The settings values. Changed from the settings panel.
struct Settings: Equatable {
    /// Paste by default, like Pastebot. Without Accessibility permission the clip goes on the clipboard only.
    var recallMode: RecallMode = .paste
    /// Recall pastes only the text, without fonts, colors or links. Shift-Return in the picker does the opposite.
    var alwaysPastePlainText = false
    /// Most clips kept. The least recently copied clips are deleted first.
    var historyLimit = 1000
    /// Clips larger than this are not recorded.
    var maximumClipMegabytes = 20
    /// Bundle identifiers of apps whose copies are not recorded.
    var ignoredApps: [String] = []
    var capturePaused = false
    var pickerHotkey = HotkeyChoice.defaultChoice

    var maximumClipBytes: Int { maximumClipMegabytes * 1024 * 1024 }

    static let defaults = Settings()
    /// Choices offered in the settings panel.
    static let historyLimitChoices = [100, 500, 1000, 5000, 10_000]
    static let maximumClipMegabyteChoices = [5, 20, 50, 100]
}

/// Keeps the settings in user defaults (the app's preferences domain). Invalid stored values read as defaults.
final class SettingsStore {
    private enum Key {
        static let recallMode = "recallMode"
        static let historyLimit = "historyLimit"
        static let maximumClipMegabytes = "maximumClipMegabytes"
        static let ignoredApps = "ignoredApps"
        static let capturePaused = "capturePaused"
        static let pickerHotkey = "pickerHotkey"
        static let alwaysPastePlainText = "alwaysPastePlainText"
    }

    private let defaults: UserDefaults
    private(set) var settings: Settings
    /// Called after every change.
    var onChange: ((Settings) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = Self.load(defaults)
    }

    private static func load(_ defaults: UserDefaults) -> Settings {
        var settings = Settings()
        if let text = defaults.string(forKey: Key.recallMode), let mode = RecallMode(rawValue: text) {
            settings.recallMode = mode
        }
        if let limit = defaults.object(forKey: Key.historyLimit) as? Int, limit >= 1 {
            settings.historyLimit = limit
        }
        if let megabytes = defaults.object(forKey: Key.maximumClipMegabytes) as? Int, megabytes >= 1 {
            settings.maximumClipMegabytes = megabytes
        }
        if let apps = defaults.array(forKey: Key.ignoredApps) as? [String] {
            settings.ignoredApps = apps.filter { !$0.isEmpty }
        }
        settings.capturePaused = defaults.bool(forKey: Key.capturePaused)
        settings.alwaysPastePlainText = defaults.bool(forKey: Key.alwaysPastePlainText)
        if let text = defaults.string(forKey: Key.pickerHotkey), let choice = HotkeyChoice(rawValue: text) {
            settings.pickerHotkey = choice
        }
        return settings
    }

    func update(_ change: (inout Settings) -> Void) {
        var updated = settings
        change(&updated)
        guard updated != settings else { return }
        settings = updated
        defaults.set(updated.recallMode.rawValue, forKey: Key.recallMode)
        defaults.set(updated.historyLimit, forKey: Key.historyLimit)
        defaults.set(updated.maximumClipMegabytes, forKey: Key.maximumClipMegabytes)
        defaults.set(updated.ignoredApps, forKey: Key.ignoredApps)
        defaults.set(updated.capturePaused, forKey: Key.capturePaused)
        defaults.set(updated.pickerHotkey.rawValue, forKey: Key.pickerHotkey)
        defaults.set(updated.alwaysPastePlainText, forKey: Key.alwaysPastePlainText)
        onChange?(updated)
    }

    func ignore(_ bundleIdentifier: String) {
        update { if !$0.ignoredApps.contains(bundleIdentifier) { $0.ignoredApps.append(bundleIdentifier) } }
    }

    func stopIgnoring(_ bundleIdentifier: String) {
        update { $0.ignoredApps.removeAll { $0 == bundleIdentifier } }
    }
}
