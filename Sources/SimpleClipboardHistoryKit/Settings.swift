import CoreFoundation
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
    var pickerWidth = 560
    var pickerContentLines = 2
    var pickerDensity = 4
    var maximumVisibleItems = 8
    var iconStyle: ClipIconStyle = .current
    var showTypeIcons = true
    var showTimestamps = false
    var showPasteSpecial = true
    var maximumHistoryMegabytes = 500
    var copyActivityDays = 5

    var maximumClipBytes: Int { Self.bytes(megabytes: maximumClipMegabytes) }
    var maximumHistoryBytes: Int { Self.bytes(megabytes: maximumHistoryMegabytes) }

    private static func bytes(megabytes: Int) -> Int {
        let result = max(0, megabytes).multipliedReportingOverflow(by: 1024 * 1024)
        return result.overflow ? Int.max : result.partialValue
    }

    fileprivate func validated() -> Settings {
        var value = self
        if historyLimit < 1 { value.historyLimit = Self.defaults.historyLimit }
        if maximumClipMegabytes < 1 || maximumClipMegabytes > Int.max / (1024 * 1024) {
            value.maximumClipMegabytes = Self.defaults.maximumClipMegabytes
        }
        if !Self.copyActivityDayChoices.contains(copyActivityDays) { value.copyActivityDays = Self.defaults.copyActivityDays }
        if !(280...1200).contains(pickerWidth) { value.pickerWidth = Self.defaults.pickerWidth }
        if !Self.pickerContentLineChoices.contains(pickerContentLines) { value.pickerContentLines = Self.defaults.pickerContentLines }
        if !Self.pickerDensityChoices.contains(pickerDensity) { value.pickerDensity = Self.defaults.pickerDensity }
        if !Self.visibleItemChoices.contains(maximumVisibleItems) { value.maximumVisibleItems = Self.defaults.maximumVisibleItems }
        if !Self.maximumHistoryMegabyteChoices.contains(maximumHistoryMegabytes) { value.maximumHistoryMegabytes = Self.defaults.maximumHistoryMegabytes }
        value.ignoredApps = ignoredApps.filter { !$0.isEmpty }
        return value
    }

    static let defaults = Settings()
    /// Choices offered in the settings panel.
    static let historyLimitChoices = [100, 500, 1000, 5000, 10_000]
    static let copyActivityDayChoices = [3, 5, 10]
    static let maximumClipMegabyteChoices = [5, 20, 50, 100]
    static let pickerWidthChoices = [360, 460, 560]
    static let pickerContentLineChoices = [1, 2, 3, 5]
    static let pickerDensityChoices = [4, 7, 10]
    static let pickerDensityLabels = ["Compact", "Normal", "Comfortable"]
    static let visibleItemChoices = [5, 8, 10, 15]
    static let maximumHistoryMegabyteChoices = [100, 250, 500, 1000]
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
        static let pickerWidth = "pickerWidth"
        static let pickerContentLines = "pickerContentLines"
        static let pickerDensity = "pickerDensity"
        static let maximumVisibleItems = "maximumVisibleItems"
        static let iconStyle = "iconStyle"
        static let showTypeIcons = "showTypeIcons"
        static let showTimestamps = "showTimestamps"
        static let showPasteSpecial = "showPasteSpecial"
        static let maximumHistoryMegabytes = "maximumHistoryMegabytes"
        static let copyActivityDays = "copyActivityDays"
    }

    static let migrationMarker = "simpleClipboardHistorySettingsMigratedV1"
    static let legacyBundleIdentifier = "com.evadnoob.simple-clipboard"
    static let persistedKeys = ["recallMode", "historyLimit", "maximumClipMegabytes", "ignoredApps", "capturePaused",
                                "pickerHotkey", "alwaysPastePlainText", "pickerWidth", "pickerContentLines", "pickerDensity",
                                "maximumVisibleItems", "iconStyle", "showTypeIcons", "showTimestamps", "showPasteSpecial",
                                "maximumHistoryMegabytes", "copyActivityDays", "pickerManualWidth",
                                "pickerLastWidthPreset", "pickerHeight"]

    static func migrateLegacySettings(defaults: UserDefaults, legacyDomain: String = legacyBundleIdentifier) {
        guard !defaults.bool(forKey: migrationMarker) else { return }
        let legacy = defaults.persistentDomain(forName: legacyDomain) ?? [:]
        for key in persistedKeys where defaults.object(forKey: key) == nil {
            if let value = legacy[key] { defaults.set(value, forKey: key) }
        }
        defaults.set(true, forKey: migrationMarker)
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
        if let limit = integer(defaults, Key.historyLimit) { settings.historyLimit = limit }
        if let megabytes = integer(defaults, Key.maximumClipMegabytes) { settings.maximumClipMegabytes = megabytes }
        if let apps = defaults.array(forKey: Key.ignoredApps) as? [String] {
            settings.ignoredApps = apps.filter { !$0.isEmpty }
        }
        settings.capturePaused = boolean(defaults, Key.capturePaused) ?? settings.capturePaused
        settings.alwaysPastePlainText = boolean(defaults, Key.alwaysPastePlainText) ?? settings.alwaysPastePlainText
        if let text = defaults.string(forKey: Key.pickerHotkey), let choice = HotkeyChoice(rawValue: text) {
            settings.pickerHotkey = choice
        }
        if let value = integer(defaults, Key.pickerWidth) { settings.pickerWidth = value }
        if let value = integer(defaults, Key.pickerContentLines) { settings.pickerContentLines = value }
        if let value = integer(defaults, Key.pickerDensity) { settings.pickerDensity = value }
        if let value = integer(defaults, Key.maximumVisibleItems) { settings.maximumVisibleItems = value }
        if let value = integer(defaults, Key.maximumHistoryMegabytes) { settings.maximumHistoryMegabytes = value }
        if let value = integer(defaults, Key.copyActivityDays) { settings.copyActivityDays = value }
        if let value = defaults.string(forKey: Key.iconStyle), let style = ClipIconStyle(rawValue: value) { settings.iconStyle = style }
        if let value = boolean(defaults, Key.showTypeIcons) { settings.showTypeIcons = value }
        if let value = boolean(defaults, Key.showTimestamps) { settings.showTimestamps = value }
        if let value = boolean(defaults, Key.showPasteSpecial) { settings.showPasteSpecial = value }
        return settings.validated()
    }

    // Do not coerce strings, booleans or fractional numbers into integer choices.
    private static func integer(_ defaults: UserDefaults, _ key: String) -> Int? {
        guard let number = defaults.object(forKey: key) as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return Int(number.stringValue)
    }

    private static func boolean(_ defaults: UserDefaults, _ key: String) -> Bool? {
        guard let number = defaults.object(forKey: key) as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    func update(_ change: (inout Settings) -> Void) {
        var updated = settings
        change(&updated)
        updated = updated.validated()
        guard updated != settings else { return }
        settings = updated
        defaults.set(updated.recallMode.rawValue, forKey: Key.recallMode)
        defaults.set(updated.historyLimit, forKey: Key.historyLimit)
        defaults.set(updated.maximumClipMegabytes, forKey: Key.maximumClipMegabytes)
        defaults.set(updated.ignoredApps, forKey: Key.ignoredApps)
        defaults.set(updated.capturePaused, forKey: Key.capturePaused)
        defaults.set(updated.pickerHotkey.rawValue, forKey: Key.pickerHotkey)
        defaults.set(updated.alwaysPastePlainText, forKey: Key.alwaysPastePlainText)
        defaults.set(updated.pickerWidth, forKey: Key.pickerWidth)
        defaults.set(updated.pickerContentLines, forKey: Key.pickerContentLines)
        defaults.set(updated.pickerDensity, forKey: Key.pickerDensity)
        defaults.set(updated.maximumVisibleItems, forKey: Key.maximumVisibleItems)
        defaults.set(updated.iconStyle.rawValue, forKey: Key.iconStyle)
        defaults.set(updated.showTypeIcons, forKey: Key.showTypeIcons)
        defaults.set(updated.showTimestamps, forKey: Key.showTimestamps)
        defaults.set(updated.showPasteSpecial, forKey: Key.showPasteSpecial)
        defaults.set(updated.maximumHistoryMegabytes, forKey: Key.maximumHistoryMegabytes)
        defaults.set(updated.copyActivityDays, forKey: Key.copyActivityDays)
        onChange?(updated)
    }

    func ignore(_ bundleIdentifier: String) {
        update { if !$0.ignoredApps.contains(bundleIdentifier) { $0.ignoredApps.append(bundleIdentifier) } }
    }

    func stopIgnoring(_ bundleIdentifier: String) {
        update { $0.ignoredApps.removeAll { $0 == bundleIdentifier } }
    }
}
