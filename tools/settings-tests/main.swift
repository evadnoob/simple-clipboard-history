// Settings file checks. Run: bash tools/run-tests.sh
import Foundation
@testable import SimpleClipboardKit

var checks = 0
var failures = 0
func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    checks += 1
    if !condition() { failures += 1; print("FAIL: \(label)") }
}

// MARK: KDL copy from noteapp parses
let nodes = try? KDL.parse("recall { mode \"clipboard\" }")
check(nodes?.first?.name == "recall", "KDL parses a node")
check(nodes?.first?.children.first?.arguments.first == .string("clipboard"), "KDL parses a child argument")

// MARK: defaults
let empty = Settings.parse("")
check(empty.settings == Settings.defaults, "empty file gives defaults")
check(empty.problems.isEmpty, "empty file has no problems")
check(Settings.defaults.recallMode == .clipboard, "default recall mode is clipboard")

// MARK: the template is valid and matches the defaults
let template = Settings.parse(Settings.template)
check(template.problems.isEmpty, "template has no problems: \(template.problems)")
check(template.settings == Settings.defaults, "template values equal the defaults")

// MARK: values
let full = Settings.parse("""
    recall { mode "paste" }
    history {
        limit 50
        maximum-clip-megabytes 2
    }
    capture {
        ignore-app "com.1password.1password"
        ignore-app "com.apple.keychainaccess"
    }
    """)
check(full.problems.isEmpty, "valid file has no problems: \(full.problems)")
check(full.settings.recallMode == .paste, "recall mode paste")
check(full.settings.historyLimit == 50, "history limit")
check(full.settings.maximumClipBytes == 2 * 1024 * 1024, "maximum clip size in megabytes")
check(full.settings.ignoredApps == ["com.1password.1password", "com.apple.keychainaccess"], "ignored apps in order")

// MARK: invalid values keep the defaults and report a problem with the line
let invalid = Settings.parse("""
    recall { mode "type" }
    history { limit 0; maximum-clip-megabytes 1.5 }
    capture { ignore-app 3 }
    colors { }
    """)
check(invalid.settings == Settings.defaults, "invalid values keep defaults")
check(invalid.problems.count == 5, "one problem per invalid value: \(invalid.problems)")
check(invalid.problems.first == "line 1: recall mode must be \"clipboard\" or \"paste\"", "problem names the line and allowed values")

let broken = Settings.parse("recall { mode \"paste\" ")
check(broken.settings == Settings.defaults, "unparseable file gives defaults")
check(broken.problems.count == 1 && broken.problems[0].hasPrefix("settings file:"), "unparseable file reports one problem")

// MARK: SettingsFile reloads only when the file changes
let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("settings-\(UUID().uuidString)")
let url = directory.appendingPathComponent("simple-clipboard.kdl")
let file = SettingsFile(url: url)
check(file.reloadIfChanged(), "first load reports a change")
check(file.settings == Settings.defaults, "missing file gives defaults")
check(!file.reloadIfChanged(), "missing file again is not a change")
try! file.createIfMissing()
check(FileManager.default.fileExists(atPath: url.path), "createIfMissing writes the template")
check(file.reloadIfChanged(), "new file is a change")
check(file.problems.isEmpty, "template loads without problems")
try! "recall { mode \"paste\" }".write(to: url, atomically: true, encoding: .utf8)
try! FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(10)], ofItemAtPath: url.path)
check(file.reloadIfChanged(), "edited file is a change")
check(file.settings.recallMode == .paste, "edited value applies")
try! "recall { mode \"clipboard\" }".write(to: url, atomically: true, encoding: .utf8)
try! FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(20)], ofItemAtPath: url.path)
try! file.createIfMissing()
check(file.reloadIfChanged() && file.settings.recallMode == .clipboard, "createIfMissing does not overwrite")

// MARK: paths
check(Settings.defaultURL(environment: ["SIMPLE_CLIPBOARD_SETTINGS": "/tmp/x.kdl"]).path == "/tmp/x.kdl", "environment overrides settings path")
check(Settings.defaultURL(environment: [:]).path.hasSuffix(".config/simple-clipboard/simple-clipboard.kdl"), "default settings path")

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
