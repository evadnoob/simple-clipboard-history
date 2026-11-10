// Settings storage checks. Run: bash tools/run-tests.sh
import Foundation
@testable import SimpleClipboardKit

var checks = 0
var failures = 0
func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    checks += 1
    if !condition() { failures += 1; print("FAIL: \(label)") }
}

func freshDefaults() -> UserDefaults {
    let name = "simple-clipboard-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

// MARK: defaults
let defaults = freshDefaults()
let store = SettingsStore(defaults: defaults)
check(store.settings == Settings.defaults, "nothing stored gives defaults")
check(Settings.defaults.recallMode == .paste, "default recall mode is paste")
check(!Settings.defaults.alwaysPastePlainText, "formatting kept by default")
check(Settings.defaults.historyLimit == 1000, "default history limit")
check(Settings.defaults.maximumClipBytes == 20 * 1024 * 1024, "default largest clip")
check(!Settings.defaults.capturePaused, "capture runs by default")
check(Settings.historyLimitChoices.contains(Settings.defaults.historyLimit), "default limit is a menu choice")
check(Settings.maximumClipMegabyteChoices.contains(Settings.defaults.maximumClipMegabytes), "default size is a menu choice")
check(Settings.defaults.pickerWidth == 560 && Settings.defaults.pickerContentLines == 2, "picker geometry defaults")
check(Settings.defaults.pickerDensity == 4 && Settings.defaults.maximumVisibleItems == 8, "density and visible-item defaults")
check(Settings.defaults.showTypeIcons && !Settings.defaults.showTimestamps && Settings.defaults.showPasteSpecial, "picker toggles default")
check(Settings.defaults.maximumHistoryMegabytes == 500, "history size defaults")
check(Settings.defaults.copyActivityDays == 5, "copy activity range defaults to five days")

// MARK: icon families persist independently and reject invalid stored choices
check(store.settings.iconStyle == .current, "existing appearance remains the default")
for style in ClipIconStyle.allCases {
    let isolated = freshDefaults()
    let familyStore = SettingsStore(defaults: isolated)
    var notifications = 0
    familyStore.onChange = { _ in notifications += 1 }
    familyStore.update { $0.iconStyle = style }
    check(SettingsStore(defaults: isolated).settings.iconStyle == style, "family persists: \(style.rawValue)")
    check(familyStore.settings.showTypeIcons && familyStore.settings.pickerWidth == Settings.defaults.pickerWidth,
          "family does not alter independent appearance settings")
    check(notifications == (style == .current ? 0 : 1), "family flows through settings notifications")
}
for invalid: Any in ["future-family", "", 3, true, ["openOutlines"]] {
    let isolated = freshDefaults()
    isolated.set(invalid, forKey: "iconStyle")
    check(SettingsStore(defaults: isolated).settings.iconStyle == .current, "invalid family safely defaults")
}

// MARK: updates persist and notify
var notified: [Settings] = []
store.onChange = { notified.append($0) }
store.update {
    $0.recallMode = .clipboard
    $0.alwaysPastePlainText = true
    $0.historyLimit = 500
    $0.maximumClipMegabytes = 50
    $0.capturePaused = true
    $0.pickerWidth = 777
    $0.pickerContentLines = 5
    $0.pickerDensity = 10
    $0.maximumVisibleItems = 15
    $0.showTypeIcons = false
    $0.showTimestamps = true
    $0.showPasteSpecial = false
    $0.maximumHistoryMegabytes = 1000
    $0.copyActivityDays = 10
}
check(notified.count == 1, "one notification per update")
store.update { $0.historyLimit = 500 }
check(notified.count == 1, "no notification when nothing changed")
store.ignore("com.1password.1password")
store.ignore("com.apple.keychainaccess")
store.ignore("com.1password.1password")
check(store.settings.ignoredApps == ["com.1password.1password", "com.apple.keychainaccess"], "ignore keeps order, no duplicates")
let reloaded = SettingsStore(defaults: defaults).settings
check(reloaded.recallMode == .clipboard, "recall mode persists")
check(reloaded.alwaysPastePlainText, "always plain text persists")
check(reloaded.historyLimit == 500, "history limit persists")
check(reloaded.maximumClipMegabytes == 50 && reloaded.maximumClipBytes == 50 * 1024 * 1024, "largest clip persists")
check(reloaded.capturePaused, "pause persists")
check(reloaded.pickerWidth == 777 && reloaded.pickerContentLines == 5 && reloaded.pickerDensity == 10, "picker appearance persists including resized width")
check(reloaded.maximumVisibleItems == 15 && !reloaded.showTypeIcons && reloaded.showTimestamps && !reloaded.showPasteSpecial, "picker toggles persist")
check(reloaded.maximumHistoryMegabytes == 1000, "history size persists")
check(reloaded.copyActivityDays == 10, "copy activity range persists")
check(reloaded.ignoredApps == ["com.1password.1password", "com.apple.keychainaccess"], "ignored apps persist")
store.stopIgnoring("com.1password.1password")
check(SettingsStore(defaults: defaults).settings.ignoredApps == ["com.apple.keychainaccess"], "stop ignoring persists")

// MARK: invalid stored values read as defaults
let broken = freshDefaults()
broken.set("type", forKey: "recallMode")
broken.set(0, forKey: "historyLimit")
broken.set(-3, forKey: "maximumClipMegabytes")
broken.set("not a list", forKey: "ignoredApps")
broken.set(2000, forKey: "pickerWidth")
broken.set(99, forKey: "pickerContentLines")
broken.set(6, forKey: "pickerDensity")
broken.set(4, forKey: "maximumVisibleItems")
broken.set(-1, forKey: "maximumHistoryMegabytes")
broken.set(7, forKey: "copyActivityDays")
broken.set(36_500, forKey: "retentionDays") // ignored legacy preference
check(SettingsStore(defaults: broken).settings == Settings.defaults, "invalid stored values give defaults")

// MARK: each numeric setting persists independently, including every offered choice
let integerSettings: [(String, WritableKeyPath<Settings, Int>, [Int], [Int])] = [
    ("historyLimit", \.historyLimit, [1, 1234, Int.max], [0, -1, Int.min]),
    ("maximumClipMegabytes", \.maximumClipMegabytes, [1, 37, Int.max / (1024 * 1024)], [0, -1, Int.max]),
    ("pickerWidth", \.pickerWidth, [280, 777, 1200] + Settings.pickerWidthChoices, [279, 1201, Int.max, Int.min]),
    ("pickerContentLines", \.pickerContentLines, Settings.pickerContentLineChoices, [0, 4, Int.max, Int.min]),
    ("pickerDensity", \.pickerDensity, Settings.pickerDensityChoices, [0, 6, Int.max, Int.min]),
    ("maximumVisibleItems", \.maximumVisibleItems, Settings.visibleItemChoices, [0, 9, Int.max, Int.min]),
    ("maximumHistoryMegabytes", \.maximumHistoryMegabytes, Settings.maximumHistoryMegabyteChoices, [0, -1, Int.max, Int.min]),
    ("copyActivityDays", \.copyActivityDays, Settings.copyActivityDayChoices, [0, 4, 7, Int.max, Int.min]),
]
for (key, path, valid, invalid) in integerSettings {
    let domain = freshDefaults()
    for value in valid {
        let subject = SettingsStore(defaults: domain)
        subject.update { $0[keyPath: path] = value }
        check(SettingsStore(defaults: domain).settings[keyPath: path] == value, "\(key) persists \(value)")
    }
    for value in invalid {
        domain.set(value, forKey: key)
        check(SettingsStore(defaults: domain).settings[keyPath: path] == Settings.defaults[keyPath: path], "\(key) rejects stored \(value)")
        let subject = SettingsStore(defaults: freshDefaults())
        var notifications = 0
        subject.onChange = { _ in notifications += 1 }
        subject.update { $0[keyPath: path] = value }
        check(subject.settings[keyPath: path] == Settings.defaults[keyPath: path] && notifications == 0, "\(key) validates update \(value) before notifying")
    }
    let malformed: [Any] = ["\(valid[0])", true, Double(valid[0]) + 0.5, [valid[0]], ["bad": 1], "NaN", Double.nan, Double.infinity, NSNumber(value: UInt64.max)]
    for value in malformed {
        domain.set(value, forKey: key)
        check(SettingsStore(defaults: domain).settings[keyPath: path] == Settings.defaults[keyPath: path], "\(key) rejects malformed \(value)")
    }
}
let booleanSettings: [(String, WritableKeyPath<Settings, Bool>)] = [
    ("capturePaused", \.capturePaused), ("alwaysPastePlainText", \.alwaysPastePlainText),
    ("showTypeIcons", \.showTypeIcons), ("showTimestamps", \.showTimestamps), ("showPasteSpecial", \.showPasteSpecial)
]
for (key, path) in booleanSettings {
    let domain = freshDefaults()
    for value in [true, false] {
        let subject = SettingsStore(defaults: domain)
        subject.update { $0[keyPath: path] = value }
        check(SettingsStore(defaults: domain).settings[keyPath: path] == value, "\(key) persists \(value)")
    }
    for value: Any in ["true", "false", 1, 0, 0.5, [true]] {
        domain.set(value, forKey: key)
        check(SettingsStore(defaults: domain).settings[keyPath: path] == Settings.defaults[keyPath: path], "\(key) rejects malformed boolean \(value)")
    }
}
for value in HotkeyChoice.allCases {
    let domain = freshDefaults()
    SettingsStore(defaults: domain).update { $0.pickerHotkey = value }
    check(SettingsStore(defaults: domain).settings.pickerHotkey == value, "hotkey persists \(value)")
}
for value in RecallMode.allCases {
    let domain = freshDefaults()
    SettingsStore(defaults: domain).update { $0.recallMode = value }
    check(SettingsStore(defaults: domain).settings.recallMode == value, "recall mode persists \(value)")
}
let malformedEnums = freshDefaults()
malformedEnums.set("unknown", forKey: "pickerHotkey")
malformedEnums.set(["paste"], forKey: "recallMode")
malformedEnums.set([1, "com.example.app"] as [Any], forKey: "ignoredApps")
check(SettingsStore(defaults: malformedEnums).settings == Settings.defaults, "malformed enums and mixed ignored-app array rejected")
let filteredApps = SettingsStore(defaults: freshDefaults())
filteredApps.update { $0.ignoredApps = ["", "com.example.app"] }
check(filteredApps.settings.ignoredApps == ["com.example.app"], "update filters empty ignored-app identifiers")
let invalidUpdateDefaults = freshDefaults()
let invalidUpdate = SettingsStore(defaults: invalidUpdateDefaults)
invalidUpdate.update {
    $0.maximumClipMegabytes = Int.max
    $0.maximumHistoryMegabytes = Int.max
    $0.pickerWidth = 777
    $0.pickerContentLines = 4
}
let invalidUpdateReloaded = SettingsStore(defaults: invalidUpdateDefaults).settings
check(invalidUpdateReloaded.maximumClipMegabytes == 20 && invalidUpdateReloaded.maximumHistoryMegabytes == 500,
      "invalid overflowing update values are never persisted")
check(invalidUpdateReloaded.pickerWidth == 777 && invalidUpdateReloaded.pickerContentLines == 2,
      "valid manual width preserved alongside invalid update fields")
var extreme = Settings()
extreme.maximumClipMegabytes = Int.max
extreme.maximumHistoryMegabytes = Int.max
check(extreme.maximumClipBytes == Int.max && extreme.maximumHistoryBytes == Int.max, "direct Settings byte conversion saturates on positive overflow")
extreme.maximumClipMegabytes = Int.min
extreme.maximumHistoryMegabytes = Int.min
check(extreme.maximumClipBytes == 0 && extreme.maximumHistoryBytes == 0, "direct Settings byte conversion handles negative extremes")
extreme.maximumClipMegabytes = Int.max / (1024 * 1024)
extreme.maximumHistoryMegabytes = Int.max / (1024 * 1024)
check(extreme.maximumClipBytes == (Int.max / (1024 * 1024)) * 1024 * 1024 && extreme.maximumHistoryBytes == extreme.maximumClipBytes,
      "largest representable megabyte product remains exact")

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
