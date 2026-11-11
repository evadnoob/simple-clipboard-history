// swift-tools-version:5.9
import PackageDescription

/// Test harness targets. tools/run-tests.sh runs every name in this list, so add new harnesses here.
let harnesses: [(name: String, path: String, exclude: [String])] = [
    ("SettingsTests", "tools/settings-tests", []),
    ("StoreTests", "tools/store-tests", []),
    ("PickerTests", "tools/picker-tests", []),
    ("FilterTests", "tools/filter-tests", []),
    ("PanelTests", "tools/panel-tests", []),
    ("IconTests", "tools/icon-tests", []),
    ("RenameTransitionTests", "tools/rename-transition-tests", [])
]

let package = Package(
    name: "SimpleClipboardHistory",
    platforms: [.macOS(.v13)],
    targets: [
        // All app code. The app and the test harnesses link it.
        .target(
            name: "SimpleClipboardHistoryKit",
            path: "Sources/SimpleClipboardHistoryKit",
            linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(
            name: "SimpleClipboardHistory",
            dependencies: ["SimpleClipboardHistoryKit"],
            path: "Sources/SimpleClipboardHistoryMain"),
        // Test harnesses: one executable target per tools/<name> directory. They use
        // "@testable import SimpleClipboardHistoryKit", so they build only in the debug configuration.
    ] + harnesses.map { harness in
        .executableTarget(
            name: harness.name,
            dependencies: ["SimpleClipboardHistoryKit"],
            path: harness.path,
            exclude: harness.exclude)
    }
)
