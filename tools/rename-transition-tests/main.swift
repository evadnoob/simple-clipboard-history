import Foundation
@testable import SimpleClipboardHistoryKit

var checks = 0
var failures = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() { failures += 1; print("FAIL: \(message)") }
}

let newOverride = ClipStore.defaultDirectory(environment: ["SIMPLE_CLIPBOARD_HISTORY_DATA": "~/new", "SIMPLE_CLIPBOARD_DATA": "~/old"])
let oldOverride = ClipStore.defaultDirectory(environment: ["SIMPLE_CLIPBOARD_DATA": "~/old"])
check(newOverride.path.hasSuffix("/new"), "new data override takes precedence")
check(oldOverride.path.hasSuffix("/old"), "legacy data override remains fallback")
check(ClipStore.dataOverride(environment: ["SIMPLE_CLIPBOARD_HISTORY_DATA": "", "SIMPLE_CLIPBOARD_DATA": "~/old"]) == "~/old", "empty new override falls back to legacy")
check(ClipStore.dataOverride(environment: ["SIMPLE_CLIPBOARD_HISTORY_DATA": "", "SIMPLE_CLIPBOARD_DATA": ""]) == nil, "empty overrides resolve as absent")
check(SettingsStore.legacyBundleIdentifier == "com.evadnoob.simple-clipboard", "legacy identifier remains explicit for defaults migration")

let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
let legacyDirectory = root.appendingPathComponent("simple-clipboard")
let newDirectory = root.appendingPathComponent("simple-clipboard-history")
try! FileManager.default.createDirectory(at: legacyDirectory.appendingPathComponent("blobs"), withIntermediateDirectories: true)
try! Data("sqlite-sidecar".utf8).write(to: legacyDirectory.appendingPathComponent("clips.sqlite-wal"))
try! Data("blob".utf8).write(to: legacyDirectory.appendingPathComponent("blobs/example"))
try! AppDelegate.migrateHistory(to: newDirectory, environment: [:], isLegacyAppRunning: { false })
check(FileManager.default.fileExists(atPath: newDirectory.appendingPathComponent("clips.sqlite-wal").path), "move preserves SQLite sidecars")
check(FileManager.default.fileExists(atPath: newDirectory.appendingPathComponent("blobs/example").path), "move preserves blob directory")
try! FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
try! Data("old".utf8).write(to: legacyDirectory.appendingPathComponent("retained"))
try! Data("new".utf8).write(to: newDirectory.appendingPathComponent("winner"))
try! AppDelegate.migrateHistory(to: newDirectory, environment: [:], isLegacyAppRunning: { false })
check(FileManager.default.fileExists(atPath: legacyDirectory.appendingPathComponent("retained").path), "old data retained when both directories exist")

let guardedDestination = root.appendingPathComponent("guarded-destination")
var blockedByRunningApp = false
do { try AppDelegate.migrateHistory(to: guardedDestination, environment: [:], isLegacyAppRunning: { true }) }
catch { blockedByRunningApp = true }
check(blockedByRunningApp && FileManager.default.fileExists(atPath: legacyDirectory.path), "running legacy app blocks move")
var moveFailed = false
do {
    try AppDelegate.migrateHistory(to: guardedDestination, environment: [:], isLegacyAppRunning: { false },
                                   move: { _, _ in throw NSError(domain: "synthetic-move-failure", code: 1) })
} catch { moveFailed = true }
check(moveFailed && FileManager.default.fileExists(atPath: legacyDirectory.path), "move failure surfaces and retains source")
let suppressedDestination = root.appendingPathComponent("suppressed-destination")
try AppDelegate.migrateHistory(to: suppressedDestination, environment: ["SIMPLE_CLIPBOARD_HISTORY_DATA": "~/custom"], isLegacyAppRunning: { false })
check(!FileManager.default.fileExists(atPath: suppressedDestination.path), "explicit override suppresses default move")
let emptyOverrideDestination = root.appendingPathComponent("empty-override-destination")
try AppDelegate.migrateHistory(to: emptyOverrideDestination,
                               environment: ["SIMPLE_CLIPBOARD_HISTORY_DATA": "", "SIMPLE_CLIPBOARD_DATA": ""],
                               isLegacyAppRunning: { false })
check(FileManager.default.fileExists(atPath: emptyOverrideDestination.path), "empty overrides permit default migration")

let suite = "rename-migration-\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defaults.removePersistentDomain(forName: suite)
let legacySuite = "legacy-\(UUID().uuidString)"
let legacyDefaults = UserDefaults(suiteName: legacySuite)!
legacyDefaults.set(false, forKey: "capturePaused")
legacyDefaults.set(0, forKey: "historyLimit")
legacyDefaults.set(["legacy.app"], forKey: "ignoredApps")
legacyDefaults.set(true, forKey: "showTimestamps")
legacyDefaults.set(555.0, forKey: "pickerManualWidth")
legacyDefaults.set(460, forKey: "pickerLastWidthPreset")
legacyDefaults.set(720.0, forKey: "pickerHeight")
defaults.set(false, forKey: "showTimestamps")
defaults.set(555.0, forKey: "pickerManualWidth")
legacyDefaults.set("not-a-setting", forKey: "unrelated")
SettingsStore.migrateLegacySettings(defaults: defaults, legacyDomain: legacySuite)
check(defaults.object(forKey: "capturePaused") as? Bool == false, "false setting transferred")
check(defaults.object(forKey: "historyLimit") as? Int == 0, "zero setting transferred")
check(defaults.object(forKey: "showTimestamps") as? Bool == false, "existing new value wins")
check(defaults.object(forKey: "unrelated") == nil, "unrelated legacy key excluded")
check(defaults.double(forKey: "pickerManualWidth") == 555, "existing manual picker width wins")
check(defaults.integer(forKey: "pickerLastWidthPreset") == 460, "last width preset migrates")
check(defaults.double(forKey: "pickerHeight") == 720, "manual picker height migrates")
check((defaults.persistentDomain(forName: suite)?[SettingsStore.migrationMarker] as? Bool) == true, "migration marker persists in destination domain")
legacyDefaults.set(true, forKey: "capturePaused")
defaults.removeObject(forKey: "capturePaused")
let reopenedDefaults = UserDefaults(suiteName: suite)!
SettingsStore.migrateLegacySettings(defaults: reopenedDefaults, legacyDomain: legacySuite)
check(reopenedDefaults.object(forKey: "capturePaused") == nil, "persisted marker prevents reimport after reset and reopen")
check(legacyDefaults.object(forKey: "capturePaused") as? Bool == true, "legacy domain unchanged")
defaults.removePersistentDomain(forName: suite)
legacyDefaults.removePersistentDomain(forName: legacySuite)
print("\(checks - failures) checks, \(failures) failures")
if failures > 0 { exit(1) }
