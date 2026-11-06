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

// MARK: updates persist and notify
var notified: [Settings] = []
store.onChange = { notified.append($0) }
store.update {
    $0.recallMode = .clipboard
    $0.alwaysPastePlainText = true
    $0.historyLimit = 500
    $0.maximumClipMegabytes = 50
    $0.capturePaused = true
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
check(reloaded.ignoredApps == ["com.1password.1password", "com.apple.keychainaccess"], "ignored apps persist")
store.stopIgnoring("com.1password.1password")
check(SettingsStore(defaults: defaults).settings.ignoredApps == ["com.apple.keychainaccess"], "stop ignoring persists")

// MARK: invalid stored values read as defaults
let broken = freshDefaults()
broken.set("type", forKey: "recallMode")
broken.set(0, forKey: "historyLimit")
broken.set(-3, forKey: "maximumClipMegabytes")
broken.set("not a list", forKey: "ignoredApps")
check(SettingsStore(defaults: broken).settings == Settings.defaults, "invalid stored values give defaults")

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
