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

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
