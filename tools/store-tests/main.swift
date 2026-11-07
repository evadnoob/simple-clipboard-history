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
let previewID = try! store.record(textClip("line one\n\nline three\nline four\nline five\nline six"), at: start.addingTimeInterval(15))
let contentPreview = try! store.recent(limit: 10).first(where: { $0.id == previewID })!.contentPreview
check(contentPreview == "line one\n\nline three\nline four\nline five", "content preview keeps five actual lines including blanks")

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
check(statistics.clipCount == 5, "statistics count")
check(statistics.clipBytes == 11 + 11 + large.count + 7 + large.count + textClip("line one\n\nline three\nline four\nline five\nline six").byteSize, "statistics bytes sum clip sizes")
check(statistics.oldestCopiedAt == start, "statistics oldest")
check(statistics.latest?.id == largeCopyID, "statistics latest")
check(statistics.diskBytes > large.count, "disk bytes include the blob file")

// MARK: store: retention deletes the least recently copied and their unused blob files
check(try! store.enforceLimit(3) == 2, "limit deletes least recently copied clips")
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

// MARK: durable captured-copy activity uses absolute-hour buckets, independent of clip lifetime
let activityStore = freshStore()
let base = Date(timeIntervalSince1970: 1_800_000_000)
let activityID = try! activityStore.record(textClip("repeat"), at: base)
_ = try! activityStore.record(textClip("repeat"), at: base.addingTimeInterval(17))
check(try! activityStore.recent(limit: 1).first?.id == activityID, "repeated copy remains deduplicated")
check(try! activityStore.copyActivity(from: base, through: base).first?.copies == 2, "duplicate captures increment hourly activity")
let activityCutoffStore = freshStore()
let cutoffDate = Date(timeIntervalSince1970: 1_900_000_000)
let cutoffHour = floor(cutoffDate.timeIntervalSince1970 / 3600) * 3600
_ = try! activityCutoffStore.record(textClip("cutoff"), at: Date(timeIntervalSince1970: cutoffHour - 240 * 3600))
_ = try! activityCutoffStore.record(textClip("now"), at: Date(timeIntervalSince1970: cutoffHour))
check(try! activityCutoffStore.copyActivity(from: Date(timeIntervalSince1970: cutoffHour - 240 * 3600), through: Date(timeIntervalSince1970: cutoffHour)).map(\.copies) == [1, 1],
      "exact ten-day hourly cutoff bucket remains inclusive")
let exactHour = base.addingTimeInterval(3600)
_ = try! activityStore.record(textClip("next hour"), at: exactHour)
let buckets = try! activityStore.copyActivity(from: base, through: exactHour)
check(buckets.map(\.copies) == [2, 1], "hour boundary starts a distinct fixed bucket")
check(try! activityStore.copyActivity(from: exactHour, through: exactHour.addingTimeInterval(-1)).isEmpty,
      "inverted activity query is empty")
try! activityStore.delete(activityID)
check(try! activityStore.copyActivity(from: base, through: base).first?.copies == 2, "deleting clips preserves activity")
try! activityStore.deleteAll()
check(try! activityStore.copyActivity(from: base, through: exactHour).map(\.copies) == [2, 1], "clearing history preserves activity")
_ = try! activityStore.record(textClip("old"), at: base.addingTimeInterval(-11 * 86400))
_ = try! activityStore.record(textClip("future"), at: base.addingTimeInterval(86400))
check(try! activityStore.copyActivity(from: base.addingTimeInterval(-10 * 86400), through: base).map(\.copies) == [2],
      "query prunes activity older than ten-day horizon")
check(try! activityStore.copyActivity(from: base, through: base).map(\.copies) == [2], "future fixture is excluded from bounded query")
_ = try! activityStore.record(textClip("size eviction"), at: base.addingTimeInterval(7200))
_ = try! activityStore.enforceRetention(countLimit: 0, maximumBytes: 0)
check(try! activityStore.copyActivity(from: base.addingTimeInterval(7200), through: base.addingTimeInterval(7200)).first?.copies == 1,
      "count and byte eviction preserve activity")
let activityDB = try! SQLiteDatabase(path: activityStore.directory.appendingPathComponent("clips.sqlite").path)
try! activityDB.execute("CREATE TRIGGER fail_activity BEFORE INSERT ON copy_activity BEGIN SELECT RAISE(ABORT, 'injected activity failure'); END;")
do {
    try activityStore.record(textClip("rollback"), at: base.addingTimeInterval(10800))
    check(false, "activity failure aborts record")
} catch { check(true, "activity failure aborts record") }
check(try! activityStore.recent(limit: 10).isEmpty, "activity failure rolls back clip insertion")
check(try! activityStore.copyActivity(from: base.addingTimeInterval(10800), through: base.addingTimeInterval(10800)).isEmpty,
      "activity failure rolls back aggregate insertion")
try! activityDB.execute("DROP TRIGGER fail_activity")
_ = try! activityStore.record(textClip("first success"), at: base.addingTimeInterval(10800))
let duplicateFailDB = try! SQLiteDatabase(path: activityStore.directory.appendingPathComponent("clips.sqlite").path)
try! duplicateFailDB.execute("CREATE TRIGGER fail_activity_update BEFORE UPDATE ON copy_activity BEGIN SELECT RAISE(ABORT, 'injected activity failure'); END;")
do {
    try activityStore.record(textClip("first success"), at: base.addingTimeInterval(10801))
    check(false, "duplicate activity failure aborts record")
} catch { check(true, "duplicate activity failure aborts record") }
check(try! activityStore.recent(limit: 1).first?.copyCount == 1, "duplicate activity failure rolls back clip update")
check(try! activityStore.copyActivity(from: base.addingTimeInterval(10800), through: base.addingTimeInterval(10800)).first?.copies == 1,
      "duplicate activity failure rolls back aggregate update")

// MARK: store reopens the same file
let reopened = try! ClipStore(directory: store.directory)
check(try! reopened.recent(limit: 10).map(\.id) == [firstID], "history survives reopening")

// MARK: contentLines bounded extraction regressions
check(ClipStore.contentLines("") == "", "empty preview remains empty")
check(ClipStore.contentLines("a\r\nb\r\nc\r\nd\r\ne\r\nf") == "a\nb\nc\nd\ne", "CRLF counts once")
check(ClipStore.contentLines("\r\n\r\nx\r\n\r\nz\r\nignored") == "\n\nx\n\nz", "CRLF blank lines preserved")
check(ClipStore.contentLines("a\rb\u{0085}c\u{2028}d\u{2029}e\nf") == "a\nb\nc\nd\ne", "Unicode and CR line separators")
check(ClipStore.contentLines("a\n") == "a\n", "trailing blank line preserved")
let longLine = String(repeating: "é", count: 700)
check(ClipStore.contentLines(Array(repeating: longLine, count: 6).joined(separator: "\n")) ==
      Array(repeating: String(repeating: "é", count: 500), count: 5).joined(separator: "\n"), "500 Characters per actual line")
let boundaryPrefix = "a\nb\nc\nd\n" + String(repeating: "x", count: ClipStore.contentPreviewByteLimit - 9)
check(ClipStore.contentLines(boundaryPrefix + "😀\nignored") == "a\nb\nc\nd\n" + String(repeating: "x", count: 500),
      "split UTF8 scalar at budget does not erase preview")
check(ClipStore.contentLines(String(repeating: "x", count: ClipStore.contentPreviewByteLimit + 1) + "\nlater") == String(repeating: "x", count: 500),
      "scan budget omits lines after pathological first line")
let defaultSummary = ClipSummary(id: 1, kind: "text", preview: "legacy", byteSize: 6, firstCopiedAt: start,
                                 lastCopiedAt: start, copyCount: 1, sourceAppName: nil)
check(defaultSummary.contentPreview == "", "summary default preserves original initializer labels")

let contentStore = freshStore()
let recordCRLF = try! contentStore.record(textClip("1\r\n\r\n3\r\n4\r\n5\r\n6"))
check(try! contentStore.recent(limit: 1).first?.contentPreview == "1\n\n3\n4\n5", "record stores actual CRLF content lines")
let recordBoundary = try! contentStore.record(textClip(boundaryPrefix + "😀"))
check(try! contentStore.recent(limit: 1).first?.contentPreview == "a\nb\nc\nd\n" + String(repeating: "x", count: 500),
      "record preview decoding is bounded and keeps a split UTF8 prefix")
check(recordCRLF != recordBoundary, "different multiline records have distinct identities")
let invalidUTF8 = Data([0x61, 0xff, 0xc3, 0x28, 0x0a, 0x62, 0x80])
let invalidPreview = "a��(\nb�"
try! contentStore.record(CapturedClip(items: [[Representation(type: textType, data: invalidUTF8)]]))
check(try! contentStore.recent(limit: 1).first?.contentPreview == invalidPreview,
      "arbitrary invalid UTF8 record preview preserves valid bytes with replacement characters")

// MARK: legacy DB migration: empty previews must terminate, across multiple batches and reopen
let legacyDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("legacy-\(UUID().uuidString)")
let legacyBlobs = legacyDirectory.appendingPathComponent("blobs")
try! FileManager.default.createDirectory(at: legacyBlobs, withIntermediateDirectories: true)
let legacyDB = try! SQLiteDatabase(path: legacyDirectory.appendingPathComponent("clips.sqlite").path)
try! legacyDB.execute("""
    CREATE TABLE clips (
        id INTEGER PRIMARY KEY, content_hash TEXT NOT NULL UNIQUE,
        first_copied_at REAL NOT NULL, last_copied_at REAL NOT NULL, copy_count INTEGER NOT NULL DEFAULT 1,
        source_app_name TEXT, source_bundle_identifier TEXT, kind TEXT NOT NULL, preview TEXT NOT NULL, byte_size INTEGER NOT NULL
    );
    CREATE TABLE representations (
        clip_id INTEGER NOT NULL REFERENCES clips(id) ON DELETE CASCADE, item_index INTEGER NOT NULL,
        position INTEGER NOT NULL, type TEXT NOT NULL, data BLOB, blob_file TEXT, byte_size INTEGER NOT NULL,
        PRIMARY KEY (clip_id, item_index, position)
    ) WITHOUT ROWID;
    """)
let sparseBlob = legacyBlobs.appendingPathComponent("synthetic-plain-text")
_ = FileManager.default.createFile(atPath: sparseBlob.path, contents: nil)
let sparseHandle = try! FileHandle(forWritingTo: sparseBlob)
try! sparseHandle.write(contentsOf: Data("blob one\r\n\r\nblob three\r\nblob four\r\nblob five\r\nignored".utf8))
try! sparseHandle.truncate(atOffset: 64 * 1024 * 1024)
try! sparseHandle.close()
// A directory is an existing path that cannot be read as blob bytes, regardless of test-user permissions.
let unreadableBlob = legacyBlobs.appendingPathComponent("unreadable-blob", isDirectory: true)
try! FileManager.default.createDirectory(at: unreadableBlob, withIntermediateDirectories: true)
do {
    let handle = try FileHandle(forReadingFrom: unreadableBlob)
    defer { try? handle.close() }
    _ = try handle.read(upToCount: 10)
    check(false, "unreadable blob fixture rejects file IO")
} catch { check(true, "unreadable blob fixture rejects file IO") }
try! legacyDB.transaction {
    for id in 1...240 {
        try legacyDB.run("INSERT INTO clips (id, content_hash, first_copied_at, last_copied_at, kind, preview, byte_size) VALUES (?, ?, 1, 1, 'text', 'old', 0)",
                         [.integer(Int64(id)), .text("legacy-\(id)")])
        if id == 5 { continue } // A clip with no plain-text representation.
        let text: String
        switch id {
        case 3: text = "one\r\ntwo\r\nthree\r\nfour\r\nfive\r\nsix"
        case 4: text = "\n\n\n\n\nlast"
        case 6: text = boundaryPrefix + "😀"
        default: text = ""
        }
        let blobName: String? = [2: "synthetic-plain-text", 8: "missing-blob", 9: "unreadable-blob"][id]
        let bytes = id == 10 ? invalidUTF8 : Data(text.utf8)
        try legacyDB.run("INSERT INTO representations VALUES (?, 0, 0, ?, ?, ?, ?)",
                         [.integer(Int64(id)), .text(textType), blobName == nil ? .blob(bytes) : .null,
                          .optionalText(blobName), .integer(id == 2 ? 64 * 1024 * 1024 : Int64(bytes.count))])
    }
    // Multiple items join with actual blank content lines, just like CapturedClip.plainText.
    try legacyDB.run("INSERT INTO representations VALUES (7, 1, 0, ?, ?, NULL, 4)", [.text(textType), .blob(Data("next".utf8))])
}
let legacyStore = try! ClipStore(directory: legacyDirectory)
check(try! legacyStore.recent(limit: 300).allSatisfy { $0.contentPreview.isEmpty }, "initialization does not migrate legacy payloads")
check((try! legacyDB.query("SELECT value FROM store_metadata WHERE key LIKE 'content_preview%'") { $0.integer(0) }).isEmpty,
      "initialization does not advance migration cursor or completion marker")
check(try! legacyStore.statistics().clipCount == 240 && legacyStore.statistics().clipBytes == 0, "legacy counter seed matches metadata")
check(try! legacyStore.copyActivity(from: Date(timeIntervalSince1970: 0), through: Date(timeIntervalSince1970: 10_000)).isEmpty,
      "legacy history rows are not guessed into copy activity")
check(try! legacyStore.backfillContentPreviewBatch() == false, "first bounded batch leaves more work")
check((try! legacyDB.query("SELECT value FROM store_metadata WHERE key = 'content_preview_cursor'") { $0.integer(0) }) == [100],
      "one batch commits exactly 100 ids")
let midMigrationReopen = try! ClipStore(directory: legacyDirectory)
check((try! legacyDB.query("SELECT value FROM store_metadata WHERE key = 'content_preview_cursor'") { $0.integer(0) }) == [100],
      "reopen leaves partially migrated history untouched")
check(try! midMigrationReopen.backfillContentPreviewBatch() == false, "second bounded batch resumes cursor")
check(try! midMigrationReopen.backfillContentPreviewBatch() == false, "short final payload batch commits")
check(try! midMigrationReopen.backfillContentPreviewBatch() == true, "empty keyset marks completion")
let legacyPreviews = Dictionary(uniqueKeysWithValues: try! legacyStore.recent(limit: 300).map { ($0.id, $0.contentPreview) })
check(legacyPreviews.count == 240, "legacy migration crosses two 100-row batch boundaries")
check(legacyPreviews[1] == "", "legacy empty text migration terminates")
check(legacyPreviews[2] == "blob one\n\nblob three\nblob four\nblob five", "legacy large blob uses bounded prefix with CRLF")
check(legacyPreviews[3] == "one\ntwo\nthree\nfour\nfive", "legacy inline CRLF")
check(legacyPreviews[4] == "\n\n\n\n", "legacy blank-only preview remains valid")
check(legacyPreviews[5] == "", "legacy missing representation terminates")
check(legacyPreviews[6] == "a\nb\nc\nd\n" + String(repeating: "x", count: 500), "legacy split UTF8 prefix retained")
check(legacyPreviews[7] == "\nnext", "legacy multiple plain-text items preserve blank content")
check(legacyPreviews[8] == "", "actual missing referenced blob does not abort migration")
check(legacyPreviews[9] == "", "actual unreadable referenced blob does not abort migration")
check(legacyPreviews[10] == invalidPreview, "legacy arbitrary invalid UTF8 decoded loss-tolerantly")
check((try! legacyDB.query("SELECT blob_file FROM representations WHERE clip_id IN (8,9) ORDER BY clip_id") { $0.text(0) }) == ["missing-blob", "unreadable-blob"],
      "unavailable blob references and representations remain intact")
check((try! legacyDB.query("SELECT value FROM store_metadata WHERE key = 'content_preview_v1'") { $0.integer(0) }) == [1], "backfill completion persisted")
// A trigger makes an accidental repeat of the backfill fail instead of silently succeeding.
try! legacyDB.execute("CREATE TRIGGER forbid_preview_repeat BEFORE UPDATE OF content_preview ON clips BEGIN SELECT RAISE(ABORT, 'backfill repeated'); END;")
let legacyReopened = try! ClipStore(directory: legacyDirectory)
check(try! legacyReopened.recent(limit: 300).count == 240, "completed migration reopens without rewriting empty previews")
check(try! legacyReopened.backfillContentPreviewBatch(), "completed marker skips preview updates including unavailable blobs on reopen")
check(try! legacyReopened.statistics().clipCount == 240 && legacyReopened.statistics().clipBytes == 0, "seeded counters survive reopen")
check(FileManager.default.fileExists(atPath: sparseBlob.path), "backfill leaves blob reference intact")
try! legacyDB.execute("""
    DROP TRIGGER forbid_preview_repeat;
    DELETE FROM store_metadata WHERE key = 'content_preview_v1';
    INSERT INTO store_metadata VALUES ('content_preview_cursor', 200);
    UPDATE clips SET content_preview = 'resume pending' WHERE id > 200;
    CREATE TRIGGER forbid_cursor_revisit BEFORE UPDATE OF content_preview ON clips WHEN OLD.id <= 200
        BEGIN SELECT RAISE(ABORT, 'cursor revisited'); END;
    """)
try! legacyDB.execute("""
    CREATE TRIGGER interrupt_preview_batch BEFORE UPDATE OF content_preview ON clips WHEN OLD.id = 215
        BEGIN SELECT RAISE(ABORT, 'interrupted batch'); END;
    """)
do {
    let interruptedStore = try ClipStore(directory: legacyDirectory)
    try interruptedStore.backfillContentPreviewBatch()
    check(false, "backfill interruption surfaces error")
} catch {
    check("\(error)".contains("interrupted batch"), "backfill interruption surfaces error")
}
check((try! legacyDB.query("SELECT value FROM store_metadata WHERE key = 'content_preview_cursor'") { $0.integer(0) }) == [200],
      "failed backfill batch does not advance durable cursor")
check((try! legacyDB.query("SELECT content_preview FROM clips WHERE id = 201") { $0.text(0) }) == ["resume pending"],
      "failed backfill batch rolls back partial preview updates")
try! legacyDB.execute("DROP TRIGGER interrupt_preview_batch")
let resumedLegacy = try! ClipStore(directory: legacyDirectory)
check(try! resumedLegacy.backfillContentPreviewBatch() == false, "interrupted batch resumes after reopen")
check(try! resumedLegacy.recent(limit: 1).first?.contentPreview == "", "persisted keyset cursor resumes after interrupted migration")

// MARK: production background scheduling: each batch yields a main-thread read/refresh opportunity
try! legacyDB.execute("""
    DROP TRIGGER forbid_cursor_revisit;
    DELETE FROM store_metadata WHERE key LIKE 'content_preview%';
    UPDATE clips SET content_preview = '';
    """)
let migrationPasteboard = NSPasteboard(name: NSPasteboard.Name("preview-tests-\(UUID().uuidString)"))
let migrationQueue = DispatchQueue(label: "preview-tests", qos: .utility)
migrationQueue.suspend()
var migrationSettings = Settings()
let backgroundMonitor = ClipboardMonitor(pasteboard: migrationPasteboard, store: resumedLegacy,
                                          settings: { migrationSettings }, previewQueue: migrationQueue)
var stopAfterFirstBatch = true
var firstBatchRefreshed = false
var migrationFinished = false
var refreshesOnMain = true
var observedCursors: [Int64] = []
backgroundMonitor.onChange = { [weak backgroundMonitor] in
    refreshesOnMain = refreshesOnMain && Thread.isMainThread
    // These UI-style reads must run between batches, without the migration lock held.
    _ = try! resumedLegacy.recent(limit: 10)
    let cursor = try! legacyDB.query("SELECT value FROM store_metadata WHERE key = 'content_preview_cursor'") { $0.integer(0) }.first
    if let cursor, observedCursors.last != cursor { observedCursors.append(cursor) }
    if cursor == 100 && stopAfterFirstBatch {
        firstBatchRefreshed = true
        backgroundMonitor?.stop()
    }
    if (try! legacyDB.query("SELECT value FROM store_metadata WHERE key = 'content_preview_v1'") { $0.integer(0) }) == [1] {
        migrationFinished = true
        backgroundMonitor?.stop()
    }
}
func waitForMain(_ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(5)
    while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
    return condition()
}
backgroundMonitor.start()
check((try! legacyDB.query("SELECT value FROM store_metadata WHERE key LIKE 'content_preview%'") { $0.integer(0) }).isEmpty,
      "monitor start enqueues migration without processing legacy history inline")
migrationQueue.resume()
check(waitForMain { firstBatchRefreshed }, "utility batch refresh reaches main thread")
check(observedCursors == [100], "stop during refresh prevents scheduling a second batch")
check((try! legacyDB.query("SELECT value FROM store_metadata WHERE key = 'content_preview_cursor'") { $0.integer(0) }) == [100],
      "background batch persists cursor before UI refresh")
stopAfterFirstBatch = false
backgroundMonitor.start()
check(waitForMain { migrationFinished }, "restart schedules remaining bounded batches through completion")
check(observedCursors == [100, 200, 240], "each background batch yields an observable durable cursor")
check(refreshesOnMain, "all background migration notifications arrive on main thread")
check(try! resumedLegacy.recent(limit: 300).first(where: { $0.id == 10 })?.contentPreview == invalidPreview,
      "background migration populates summaries without changing preview API")
backgroundMonitor.stop()

try! legacyDB.execute("DELETE FROM store_metadata WHERE key LIKE 'content_preview%'")
let lifecycleQueue = DispatchQueue(label: "preview-lifecycle-tests", qos: .utility)
lifecycleQueue.suspend()
var lifecycleMonitor: ClipboardMonitor? = ClipboardMonitor(pasteboard: migrationPasteboard, store: resumedLegacy,
                                                          settings: { migrationSettings }, previewQueue: lifecycleQueue)
weak var weakLifecycleMonitor = lifecycleMonitor
lifecycleMonitor?.start()
lifecycleMonitor = nil
check(weakLifecycleMonitor == nil, "queued migration and timers do not retain monitor")
lifecycleQueue.resume()
lifecycleQueue.sync {}
check((try! legacyDB.query("SELECT value FROM store_metadata WHERE key LIKE 'content_preview%'") { $0.integer(0) }).isEmpty,
      "deallocated monitor performs no queued batch and cannot create a task loop")
migrationPasteboard.releaseGlobally()

// MARK: deterministic mixed age, count and byte retention
func counterMatchesHistory(_ store: ClipStore) -> Bool {
    let db = try! SQLiteDatabase(path: store.directory.appendingPathComponent("clips.sqlite").path)
    let values = try! db.query("SELECT clip_count, clip_bytes, (SELECT count(*) FROM clips), (SELECT coalesce(sum(byte_size),0) FROM clips) FROM clip_totals") {
        ($0.integer(0), $0.integer(1), $0.integer(2), $0.integer(3))
    }
    return values.first.map { $0.0 == $0.2 && $0.1 == $0.3 } ?? false
}
let retentionCases: [(String, Int, Int, Int)] = [
    ("age subtracts expired bytes before checking budget", 10, 40, 4),
    ("age plus byte budget", 10, 20, 2),
    ("age plus count budget", 3, 1000, 3),
    ("age plus count and bytes", 3, 25, 2),
    ("zero byte budget", 10, 0, 0),
    ("zero count budget", 0, 1000, 0),
    ("negative budgets treated as zero", -1, -1, 0)
]
for (label, limit, bytes, expectedCount) in retentionCases {
    let target = freshStore()
    _ = try! target.record(textClip(String(repeating: "e", count: 100)), at: start.addingTimeInterval(-31 * 86_400))
    var ids: [Int64] = []
    for index in 1...4 { ids.append(try! target.record(textClip(String(repeating: "\(index)", count: 10)), at: start)) }
    let removed = try! target.enforceRetention(countLimit: limit, maximumBytes: bytes, now: start)
    check(removed == 5 - expectedCount, "\(label): deletion count")
    check(try! target.recent(limit: 10).map(\.id) == Array(ids.suffix(expectedCount).reversed()), "\(label): deterministic id ties keep newest")
    check(try! target.statistics().clipCount == expectedCount, "\(label): item/byte limits produce expected count")
    check(counterMatchesHistory(target), "\(label): counters accurate")
    check(try! target.enforceRetention(countLimit: limit, maximumBytes: bytes, now: start) == 0, "\(label): repeated pass idempotent")
}
let cutoffStore = freshStore()
let cutoffID = try! cutoffStore.record(textClip("at cutoff"), at: start.addingTimeInterval(-30 * 86_400))
try! cutoffStore.record(textClip("before cutoff"), at: start.addingTimeInterval(-30 * 86_400 - 1))
check(try! cutoffStore.enforceRetention(countLimit: 10, maximumBytes: 100, now: start) == 0, "legacy retention value ignored")
check(try! cutoffStore.recent(limit: 10).map(\.id).contains(cutoffID) && (try! cutoffStore.statistics().clipCount) == 2, "old clips retained regardless of legacy cutoff")
let batchedStore = freshStore()
var batchIDs: [Int64] = []
for index in 0..<350 {
    let text = String(format: "%010d", index)
    batchIDs.append(try! batchedStore.record(textClip(text), at: index < 120 ? start.addingTimeInterval(-31 * 86_400) : start))
}
check(try! batchedStore.enforceRetention(countLimit: 105, maximumBytes: 900, now: start) == 260, "bounded count and byte eviction crosses multiple batches")
check(try! batchedStore.recent(limit: 400).map(\.id) == Array(batchIDs.suffix(90).reversed()), "batch retention preserves deterministic last 90")
check(counterMatchesHistory(batchedStore), "batch retention counter totals")
let batchReopened = try! ClipStore(directory: batchedStore.directory)
check(try! batchReopened.enforceRetention(countLimit: 90, maximumBytes: 900, now: start) == 0, "retention counters survive reopen")
try! batchReopened.record(textClip(String(format: "%010d", 349)), at: start)
check(counterMatchesHistory(batchReopened), "dedup does not add count or bytes")
try! batchReopened.touch(batchIDs.last!, at: start)
try! batchReopened.enforceLimit(2)
check(counterMatchesHistory(batchReopened), "count-only eviction maintains counters")
try! batchReopened.deleteAll()
check(counterMatchesHistory(batchReopened), "deleteAll maintains counters")
try! batchReopened.record(textClip("after deleteAll"), at: start)
check(counterMatchesHistory(batchReopened), "record after deleteAll maintains counters")

let sharedStore = freshStore()
let sharedOld = try! sharedStore.record(largeClip, at: start.addingTimeInterval(-31 * 86_400))
let sharedNew = try! sharedStore.record(largeCopy, at: start)
let smallNew = try! sharedStore.record(textClip("small"), at: start.addingTimeInterval(1))
let sharedFiles = sharedStore.directory.appendingPathComponent("blobs")
check(try! sharedStore.enforceRetention(countLimit: 2, maximumBytes: large.count + 5, now: start) == 1, "byte subtraction respects shared-blob logical sizes")
check(try! sharedStore.recent(limit: 10).map(\.id) == [smallNew, sharedNew], "shared blob surviving clips not overdeleted")
check((try! FileManager.default.contentsOfDirectory(atPath: sharedFiles.path)).count == 1, "age eviction preserves referenced blob")
check(try! sharedStore.items(for: sharedNew) == largeCopy.items, "shared blob readable after age eviction")
check(try! sharedStore.search("caption", limit: 10).isEmpty && sharedOld != sharedNew, "age eviction removes expired search row")
check(try! sharedStore.enforceRetention(countLimit: 2, maximumBytes: 5, now: start) == 1, "byte eviction removes last blob owner")
check((try! FileManager.default.contentsOfDirectory(atPath: sharedFiles.path)).isEmpty, "last retained blob reference removal deletes file")
check(counterMatchesHistory(sharedStore), "shared-blob logical counters consistent")

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

// MARK: startup/hourly/settings retention uses the same observable monitor path
let startupStore = freshStore()
try! startupStore.record(textClip("expired before startup"), at: Date().addingTimeInterval(-100 * 86_400))
let startupMonitor = ClipboardMonitor(pasteboard: pasteboard, store: startupStore, settings: { Settings() })
var startupChanges = 0
startupMonitor.onChange = { startupChanges += 1 }
startupMonitor.start()
check(try! startupStore.statistics().clipCount == 1, "startup maintenance retains old clips")
check(startupChanges == 1, "startup retention notifies UI even without pasteboard changes")
startupMonitor.start()
check(startupChanges == 1, "start is idempotent and does not install another timer pair")
startupMonitor.stop()
startupMonitor.start()
check(startupChanges == 2, "stop allows one clean restart")
startupMonitor.stop()

let failureStore = freshStore()
let failureDate = min(start.addingTimeInterval(-31 * 86_400), Date().addingTimeInterval(-100 * 86_400))
let expiredFailureID = try! failureStore.record(textClip("expired failure"), at: failureDate)
let failureDB = try! SQLiteDatabase(path: failureStore.directory.appendingPathComponent("clips.sqlite").path)
try! failureDB.execute("CREATE TRIGGER fail_retention BEFORE DELETE ON clips BEGIN SELECT RAISE(ABORT, 'injected retention failure'); END;")
var failureSettings = Settings()
failureSettings.historyLimit = 0
let failureMonitor = ClipboardMonitor(pasteboard: pasteboard, store: failureStore, settings: { failureSettings })
var failureChanges = 0
failureMonitor.onChange = { failureChanges += 1 }
check(failureMonitor.enforceRetention(now: start) == 0, "failed retention returns no successful deletions")
if case .failed(let message)? = failureMonitor.current?.state {
    check(message.contains("Retention failed:") && message.contains("injected retention failure"), "retention error surfaced in monitor state")
} else { check(false, "retention error surfaced in monitor state") }
check(failureChanges == 1, "failed retention notifies UI")
check(counterMatchesHistory(failureStore), "failed delete transaction preserves counters")
check(try! failureStore.recent(limit: 10).map(\.id) == [expiredFailureID], "failed retention preserves history")
failureMonitor.start()
if case .failed? = failureMonitor.current?.state { check(true, "startup failure visible") } else { check(false, "startup failure visible") }
check(failureChanges == 2, "startup failure not swallowed")
failureMonitor.stop()
try! failureDB.execute("DROP TRIGGER fail_retention")
// This is the same entry point the hourly timer and settings-change closure call.
check(failureMonitor.enforceRetention(now: start) == 1 && failureChanges == 3, "count limit evicts old row and refreshes UI")
check(failureMonitor.current == nil, "successful maintenance retry clears failure when no clipboard event exists")
try! failureStore.record(textClip("fresh hourly"), at: start)
check(failureMonitor.enforceRetention(now: start.addingTimeInterval(31 * 86_400)) == 1 && failureChanges == 4,
      "maintenance enforces count without age deletion")
try! failureStore.record(textClip("settings one"), at: start)
let settingsSurvivor = try! failureStore.record(textClip("settings two"), at: start)
failureSettings.historyLimit = 1
check(failureMonitor.enforceRetention(now: start) == 1 && failureChanges == 5, "settings-change retention applies new count and refreshes UI")
check(try! failureStore.recent(limit: 10).map(\.id) == [settingsSurvivor], "settings count pass keeps newest tied id")
try! failureDB.execute("CREATE TRIGGER fail_capture_retention BEFORE DELETE ON clips BEGIN SELECT RAISE(ABORT, 'capture retention failed'); END;")
pasteboard.clearContents()
pasteboard.setString("new failing capture", forType: .string)
failureMonitor.poll()
if case .failed(let message)? = failureMonitor.current?.state {
    check(message.contains("capture retention failed"), "capture retention failure surfaced")
} else { check(false, "capture retention failure surfaced") }
check(failureChanges == 6, "capture retention failure notifies UI")
let genuineCaptureFailure = failureMonitor.current
failureMonitor.enforceRetention(now: start)
try! failureDB.execute("DROP TRIGGER fail_capture_retention")
failureMonitor.enforceRetention(now: start)
check(failureMonitor.current == genuineCaptureFailure, "maintenance recovery preserves a genuine clipboard capture failure")

// A later clipboard event during a maintenance failure must win over any previously saved event.
failureSettings.capturePaused = true
pasteboard.clearContents()
pasteboard.setString("paused before maintenance", forType: .string)
failureMonitor.poll()
let priorClipboardEvent = failureMonitor.current
try! failureStore.record(textClip("expired again"), at: start.addingTimeInterval(-31 * 86_400))
try! failureDB.execute("CREATE TRIGGER fail_retry BEFORE DELETE ON clips BEGIN SELECT RAISE(ABORT, 'retry failure'); END;")
failureMonitor.enforceRetention(now: start)
failureMonitor.enforceRetention(now: start)
try! failureDB.execute("DROP TRIGGER fail_retry")
failureMonitor.enforceRetention(now: start)
check(failureMonitor.current == priorClipboardEvent, "repeated maintenance failures recover the exact prior clipboard event")
try! failureStore.record(textClip("expired third"), at: start.addingTimeInterval(-31 * 86_400))
try! failureDB.execute("CREATE TRIGGER fail_retry BEFORE DELETE ON clips BEGIN SELECT RAISE(ABORT, 'retry failure'); END;")
failureMonitor.enforceRetention(now: start)
pasteboard.clearContents()
pasteboard.setString("new paused event", forType: .string)
failureMonitor.poll()
let latestClipboardCount = pasteboard.changeCount
try! failureDB.execute("DROP TRIGGER fail_retry")
failureMonitor.enforceRetention(now: start)
check(failureMonitor.current?.state == .skipped(.paused) && failureMonitor.current?.changeCount == latestClipboardCount,
      "maintenance recovery restores latest clipboard event rather than stale pre-error state")

pasteboard.releaseGlobally()
print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
