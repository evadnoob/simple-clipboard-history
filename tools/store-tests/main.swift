// Capture, storage, search, retention, formatting and monitor checks. Run: bash tools/run-tests.sh
import AppKit
@testable import SimpleClipboardKit

var checks = 0
var failures = 0
func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    checks += 1
    if !condition() { failures += 1; print("FAIL: \(label)") }
}

let textType = NSPasteboard.PasteboardType.string.rawValue
func textClip(_ text: String, app: String? = "Safari") -> CapturedClip {
    CapturedClip(items: [[Representation(type: textType, data: Data(text.utf8))]], sourceAppName: app,
                 sourceBundleIdentifier: app.map { "com.example.\($0)" })
}
func freshStore() -> ClipStore {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("store-\(UUID().uuidString)")
    return try! ClipStore(directory: directory)
}

// MARK: captured clip
let multiline = textClip("  first line\n\n  second\tline  ")
check(multiline.preview == "first line second line", "preview collapses whitespace")
check(multiline.kind == "text", "text kind")
check(multiline.byteSize == 29, "byte size counts every representation")
check(textClip("a").contentHash == textClip("a", app: "Notes").contentHash, "hash ignores the source app")
check(textClip("a").contentHash != textClip("b").contentHash, "hash differs by content")
let twoTypes = CapturedClip(items: [[Representation(type: textType, data: Data("a".utf8)),
                                     Representation(type: "public.rtf", data: Data("{\\rtf1 a}".utf8))]])
check(twoTypes.contentHash != textClip("a").contentHash, "hash includes every type")
let files = CapturedClip(items: [
    [Representation(type: NSPasteboard.PasteboardType.fileURL.rawValue, data: Data("file:///tmp/a.txt".utf8))],
    [Representation(type: NSPasteboard.PasteboardType.fileURL.rawValue, data: Data("file:///tmp/b%20c.png".utf8))],
])
check(files.preview == "a.txt, b c.png", "file preview lists file names")
check(files.kind == "2 files", "file kind counts files")
let image = CapturedClip(items: [[Representation(type: NSPasteboard.PasteboardType.png.rawValue, data: Data([1, 2, 3]))]])
check(image.preview == "Image" && image.kind == "image", "image preview and kind")
check(String(textClip(String(repeating: "x", count: 500)).preview.count) == "200", "preview capped at 200 characters")

// MARK: skip rules
let settings = Settings()
check(Capture.skipReason(types: [textType, "org.nspasteboard.ConcealedType"], sourceBundleIdentifier: nil,
                         settings: settings) == .concealed, "concealed marker skipped")
check(Capture.skipReason(types: [textType, "org.nspasteboard.TransientType"], sourceBundleIdentifier: nil,
                         settings: settings) == .concealed, "transient marker skipped")
var ignoring = Settings()
ignoring.ignoredApps = ["com.1password.1password"]
check(Capture.skipReason(types: [textType], sourceBundleIdentifier: "com.1password.1password", settings: ignoring)
      == .ignoredApp("com.1password.1password"), "ignored app skipped")
check(Capture.skipReason(types: [textType], sourceBundleIdentifier: "com.apple.Safari", settings: ignoring) == nil,
      "other app recorded")
check(Capture.skipReason(types: [], sourceBundleIdentifier: nil, settings: settings) == .empty, "empty skipped")

// MARK: store: record, duplicates, recent
let store = freshStore()
let start = Date(timeIntervalSince1970: 1_800_000_000)
let firstID = try! store.record(textClip("hello world"), at: start)
let secondID = try! store.record(textClip("second clip", app: "Notes"), at: start.addingTimeInterval(10))
check(firstID != secondID, "different clips get different ids")
var recent = try! store.recent(limit: 10)
check(recent.map(\.id) == [secondID, firstID], "recent is newest first")
let againID = try! store.record(textClip("hello world", app: "Terminal"), at: start.addingTimeInterval(20))
check(againID == firstID, "identical copy reuses the clip")
recent = try! store.recent(limit: 10)
check(recent.map(\.id) == [firstID, secondID], "identical copy moves to the top")
check(recent[0].copyCount == 2, "copy count increases")
check(recent[0].sourceAppName == "Terminal", "source app is the latest one")
check(recent[0].firstCopiedAt == start, "first copied date kept")
check(try! store.items(for: firstID) == textClip("hello world").items, "items round-trip")

// MARK: store: large data goes to a blob file and round-trips
let large = Data((0..<(ClipStore.blobThreshold + 10)).map { UInt8($0 % 251) })
let largeClip = CapturedClip(items: [[Representation(type: NSPasteboard.PasteboardType.png.rawValue, data: large),
                                      Representation(type: textType, data: Data("caption".utf8))]])
let largeID = try! store.record(largeClip, at: start.addingTimeInterval(30))
let blobDirectory = store.directory.appendingPathComponent("blobs")
check((try! FileManager.default.contentsOfDirectory(atPath: blobDirectory.path)).count == 1, "large data written to one blob file")
check(try! store.items(for: largeID) == largeClip.items, "large clip round-trips with type order")
let largeCopy = CapturedClip(items: [[Representation(type: NSPasteboard.PasteboardType.png.rawValue, data: large)]])
let largeCopyID = try! store.record(largeCopy, at: start.addingTimeInterval(31))
check((try! FileManager.default.contentsOfDirectory(atPath: blobDirectory.path)).count == 1, "same large data shares one blob file")

// MARK: store: search
check(try! store.search("world", limit: 10).map(\.id) == [firstID], "trigram search finds a word")
check(try! store.search("llo wor", limit: 10).map(\.id) == [firstID], "trigram search finds a substring across words")
check(try! store.search("HELLO", limit: 10).map(\.id) == [firstID], "search ignores case")
check(try! store.search("lo", limit: 10).map(\.id) == [firstID], "two-character search uses LIKE")
check(try! store.search("100%", limit: 10).isEmpty, "LIKE wildcards are escaped")
check(try! store.search("\"quoted", limit: 10).isEmpty, "quote in query does not break the search")
check(try! store.search("", limit: 2).count == 2, "empty search returns recent clips")
check(try! store.search("caption", limit: 10).map(\.id) == [largeID], "text of a mixed clip is searchable")

// MARK: store: statistics
var statistics = try! store.statistics()
check(statistics.clipCount == 4, "statistics count")
check(statistics.clipBytes == 11 + 11 + large.count + 7 + large.count, "statistics bytes sum clip sizes")
check(statistics.oldestCopiedAt == start, "statistics oldest")
check(statistics.latest?.id == largeCopyID, "statistics latest")
check(statistics.diskBytes > large.count, "disk bytes include the blob file")

// MARK: store: retention deletes the least recently copied and their unused blob files
check(try! store.enforceLimit(3) == 1, "limit deletes one clip")
check(try! store.items(for: secondID).isEmpty, "least recently copied clip deleted")
check(try! store.search("second", limit: 10).isEmpty, "deleted clip removed from search")
try! store.delete(largeID)
check((try! FileManager.default.contentsOfDirectory(atPath: blobDirectory.path)).count == 1, "blob kept while another clip uses it")
try! store.delete(largeCopyID)
check((try! FileManager.default.contentsOfDirectory(atPath: blobDirectory.path)).isEmpty, "blob deleted with its last clip")
statistics = try! store.statistics()
check(statistics.clipCount == 1 && statistics.latest?.id == firstID, "one clip left")
try! store.touch(firstID, at: start.addingTimeInterval(100))
check(try! store.recent(limit: 1).first?.lastCopiedAt == start.addingTimeInterval(100), "touch moves the clip")

// MARK: store: delete all
let clearStore = freshStore()
try! clearStore.record(textClip("keep me"))
try! clearStore.record(largeClip)
try! clearStore.deleteAll()
check(try! clearStore.statistics().clipCount == 0, "delete all removes every clip")
check(try! clearStore.search("keep", limit: 10).isEmpty, "delete all clears search")
check((try! FileManager.default.contentsOfDirectory(atPath: clearStore.directory.appendingPathComponent("blobs").path)).isEmpty,
      "delete all removes blob files")
try! clearStore.record(textClip("after clear"))
check(try! clearStore.recent(limit: 10).map(\.preview) == ["after clear"], "store works after delete all")

// MARK: store reopens the same file
let reopened = try! ClipStore(directory: store.directory)
check(try! reopened.recent(limit: 10).map(\.id) == [firstID], "history survives reopening")

// MARK: format
let now = Date(timeIntervalSince1970: 1_800_000_000)
check(Format.age(from: now, to: now) == "now", "age now")
check(Format.age(from: now.addingTimeInterval(-45), to: now) == "45s", "age seconds")
check(Format.age(from: now.addingTimeInterval(-180), to: now) == "3m", "age minutes")
check(Format.age(from: now.addingTimeInterval(-7200), to: now) == "2h", "age hours")
check(Format.age(from: now.addingTimeInterval(-3 * 86_400), to: now) == "3d", "age days")
check(Format.age(from: now.addingTimeInterval(60), to: now) == "now", "future date is now")
check(Format.bytes(512) == "512 B", "bytes")
check(Format.bytes(1536) == "1.5 KB", "kilobytes")
check(Format.bytes(20 * 1024 * 1024) == "20.0 MB", "megabytes")

// MARK: monitor and recall on a private pasteboard (never the general pasteboard)
let pasteboard = NSPasteboard(name: NSPasteboard.Name("simple-clipboard-tests-\(UUID().uuidString)"))
let monitorStore = freshStore()
var monitorSettings = Settings()
let monitor = ClipboardMonitor(pasteboard: pasteboard, store: monitorStore, settings: { monitorSettings })
var changes = 0
monitor.onChange = { changes += 1 }
monitor.poll()
check(changes == 0, "no change, no work")
pasteboard.clearContents()
pasteboard.setString("from the test", forType: .string)
monitor.poll()
check(changes == 1, "change detected")
check(try! monitorStore.recent(limit: 10).map(\.preview) == ["from the test"], "copy recorded")
if case .recorded(let clip)? = monitor.current?.state { check(clip.preview == "from the test", "current clip") } else {
    check(false, "current state is recorded")
}
pasteboard.clearContents()
let concealed = NSPasteboardItem()
concealed.setString("secret", forType: .string)
concealed.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
pasteboard.writeObjects([concealed])
monitor.poll()
check(monitor.current?.state == .skipped(.concealed), "concealed copy skipped")
check(try! monitorStore.search("secret", limit: 10).isEmpty, "concealed text not stored")
monitorSettings.capturePaused = true
pasteboard.clearContents()
pasteboard.setString("while paused", forType: .string)
monitor.poll()
check(monitor.current?.state == .skipped(.paused), "paused copy skipped")
monitorSettings.capturePaused = false
monitorSettings.maximumClipMegabytes = 1
pasteboard.clearContents()
pasteboard.setString(String(repeating: "x", count: 1024 * 1024 + 1), forType: .string)
monitor.poll()
if case .skipped(.tooLarge)? = monitor.current?.state { check(true, "") } else { check(false, "large copy skipped") }
pasteboard.clearContents()
pasteboard.setString(String(repeating: "y", count: 1000), forType: .string)
monitor.poll()
if case .recorded? = monitor.current?.state { check(true, "") } else { check(false, "copy under the limit recorded") }
monitorSettings.historyLimit = 2
for text in ["one", "two", "three"] {
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
    monitor.poll()
}
check(try! monitorStore.recent(limit: 10).map(\.preview) == ["three", "two"], "history limit applied on capture")

// Recall in clipboard mode writes every type back and is not recorded again.
let rich = CapturedClip(items: [[Representation(type: textType, data: Data("rich".utf8)),
                                 Representation(type: "public.rtf", data: Data("{\\rtf1 rich}".utf8))]])
let richID = try! monitorStore.record(rich)
let outcome = Recall.perform(items: try! monitorStore.items(for: richID), mode: .clipboard, pasteboard: pasteboard)
check(outcome == .onClipboard, "clipboard mode outcome")
check(pasteboard.string(forType: .string) == "rich", "recalled text on the pasteboard")
check(pasteboard.data(forType: NSPasteboard.PasteboardType("public.rtf")) == Data("{\\rtf1 rich}".utf8), "recalled rtf on the pasteboard")
monitor.noteOwnWrite(clip: try! monitorStore.recent(limit: 1)[0])
let countBefore = try! monitorStore.statistics().clipCount
monitor.poll()
check(try! monitorStore.statistics().clipCount == countBefore, "own recall write not recorded again")

pasteboard.releaseGlobally()
print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
