// swift-tools-version:5.9
import PackageDescription

/// Test harness targets. tools/run-tests.sh runs every name in this list, so add new harnesses here.
let harnesses: [(name: String, path: String, exclude: [String])] = [
    ("SettingsTests", "tools/settings-tests", []),
    ("StoreTests", "tools/store-tests", [])
]

let package = Package(
    name: "SimpleClipboard",
    platforms: [.macOS(.v13)],
    targets: [
        // All app code. The app and the test harnesses link it.
        .target(
            name: "SimpleClipboardKit",
            path: "Sources/SimpleClipboardKit",
            linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(
            name: "SimpleClipboard",
            dependencies: ["SimpleClipboardKit"],
            path: "Sources/SimpleClipboardMain"),
        // Test harnesses: one executable target per tools/<name> directory. They use
        // "@testable import SimpleClipboardKit", so they build only in the debug configuration.
    ] + harnesses.map { harness in
        .executableTarget(
            name: harness.name,
            dependencies: ["SimpleClipboardKit"],
            path: harness.path,
            exclude: harness.exclude)
    }
)
