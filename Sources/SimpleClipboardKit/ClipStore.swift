import AppKit
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// What lists and menus show for one clip. The clip data stays on disk.
struct ClipSummary: Equatable {
    var id: Int64
    var kind: String
    var preview: String
    var byteSize: Int
    var firstCopiedAt: Date
    var lastCopiedAt: Date
    var copyCount: Int
    var sourceAppName: String?
    var contentPreview: String = ""
}

struct StoreStatistics: Equatable {
    var clipCount: Int
    /// Sum of the clip sizes as copied.
    var clipBytes: Int
    /// Database, write-ahead log and blob files on disk.
    var diskBytes: Int
    var oldestCopiedAt: Date?
    var latest: ClipSummary?
}

/// Clip history in SQLite. Representations larger than `blobThreshold` go to content-addressed files in `blobs/`,
/// so the database stays small. Reads go through a memory-mapped database file, which the OS can reclaim.
/// Thread-safe: every public method takes a lock.
final class ClipStore {
    static let blobThreshold = 128 * 1024
    /// Characters of plain text indexed for search per clip.
    static let searchTextLimit = 64 * 1024
    /// Preview decoding/scanning never exceeds this UTF-8 prefix, even for a single very long line.
    static let contentPreviewByteLimit = 64 * 1024
    private static let maintenanceBatchSize = 100

    let directory: URL
    private let database: SQLiteDatabase
    private let lock = NSLock()
    private var blobDirectory: URL { directory.appendingPathComponent("blobs", isDirectory: true) }
    private var databaseURL: URL { directory.appendingPathComponent("clips.sqlite") }

    /// Default ~/Library/Application Support/simple-clipboard. SIMPLE_CLIPBOARD_DATA overrides it.
    static func defaultDirectory(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let path = environment["SIMPLE_CLIPBOARD_DATA"], !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("simple-clipboard", isDirectory: true)
    }

    init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("blobs", isDirectory: true),
                                                withIntermediateDirectories: true)
        database = try SQLiteDatabase(path: directory.appendingPathComponent("clips.sqlite").path)
        try database.execute("""
            PRAGMA journal_mode = WAL;
            PRAGMA synchronous = NORMAL;
            PRAGMA foreign_keys = ON;
            PRAGMA mmap_size = 67108864;
            PRAGMA cache_size = -1024;
            CREATE TABLE IF NOT EXISTS clips (
                id INTEGER PRIMARY KEY,
                content_hash TEXT NOT NULL UNIQUE,
                first_copied_at REAL NOT NULL,
                last_copied_at REAL NOT NULL,
                copy_count INTEGER NOT NULL DEFAULT 1,
                source_app_name TEXT,
                source_bundle_identifier TEXT,
                kind TEXT NOT NULL,
                preview TEXT NOT NULL,
                content_preview TEXT NOT NULL DEFAULT '',
                byte_size INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS clips_last_copied_at ON clips (last_copied_at);
            CREATE INDEX IF NOT EXISTS clips_first_copied_at ON clips (first_copied_at);
            CREATE TABLE IF NOT EXISTS copy_activity (
                hour INTEGER PRIMARY KEY, copies INTEGER NOT NULL CHECK (copies > 0)
            );
            CREATE TABLE IF NOT EXISTS representations (
                clip_id INTEGER NOT NULL REFERENCES clips (id) ON DELETE CASCADE,
                item_index INTEGER NOT NULL,
                position INTEGER NOT NULL,
                type TEXT NOT NULL,
                data BLOB,
                blob_file TEXT,
                byte_size INTEGER NOT NULL,
                PRIMARY KEY (clip_id, item_index, position)
            ) WITHOUT ROWID;
            CREATE INDEX IF NOT EXISTS representations_blob_file ON representations (blob_file)
                WHERE blob_file IS NOT NULL;
            CREATE VIRTUAL TABLE IF NOT EXISTS clip_search USING fts5 (body, tokenize = 'trigram');
            """)
        let columns = try database.query("PRAGMA table_info(clips)") { $0.text(1) ?? "" }
        if !columns.contains("content_preview") {
            try database.execute("ALTER TABLE clips ADD COLUMN content_preview TEXT NOT NULL DEFAULT ''")
        }
        // Persisted counters avoid a full history SUM on every capture. Triggers also cover cascaded deletes.
        try database.transaction {
            try database.execute("""
            CREATE TABLE IF NOT EXISTS clip_totals (
                singleton INTEGER PRIMARY KEY CHECK (singleton = 1), clip_count INTEGER NOT NULL, clip_bytes INTEGER NOT NULL
            );
            CREATE TRIGGER IF NOT EXISTS clips_total_insert AFTER INSERT ON clips BEGIN
                UPDATE clip_totals SET clip_count = clip_count + 1, clip_bytes = clip_bytes + NEW.byte_size;
            END;
            CREATE TRIGGER IF NOT EXISTS clips_total_delete AFTER DELETE ON clips BEGIN
                UPDATE clip_totals SET clip_count = clip_count - 1, clip_bytes = clip_bytes - OLD.byte_size;
            END;
            CREATE TRIGGER IF NOT EXISTS clips_total_resize AFTER UPDATE OF byte_size ON clips BEGIN
                UPDATE clip_totals SET clip_bytes = clip_bytes + NEW.byte_size - OLD.byte_size;
            END;
            CREATE TABLE IF NOT EXISTS store_metadata (key TEXT PRIMARY KEY, value INTEGER NOT NULL);
            """)
            // A legacy upgrade needs one metadata-only aggregate; ordinary reopen must not rescan history.
            let seeded = try database.query("SELECT 1 FROM clip_totals WHERE singleton = 1") { $0.integer(0) }
            if seeded.isEmpty {
                try database.run("INSERT INTO clip_totals SELECT 1, count(*), coalesce(sum(byte_size), 0) FROM clips")
            }
        }
    }

    /// Migrates at most 100 previews, releasing the store lock between calls. Returns true when complete.
    /// Call off the launch path; summaries retain their empty preview fallback until their batch commits.
    /// The cursor commits with its previews, so a failed batch can safely resume after reopening.
    @discardableResult
    func backfillContentPreviewBatch() throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        return try database.transaction {
            let complete = try database.query("SELECT value FROM store_metadata WHERE key = 'content_preview_v1'") { $0.integer(0) }.first
            guard complete != 1 else { return true }
            let cursor = try database.query("SELECT value FROM store_metadata WHERE key = 'content_preview_cursor'") { $0.integer(0) }.first
            let ids = try database.query(
                "SELECT id FROM clips \(cursor == nil ? "" : "WHERE id > ?") ORDER BY id LIMIT \(Self.maintenanceBatchSize)",
                cursor.map { [.integer($0)] } ?? []) { $0.integer(0) }
            guard let last = ids.last else {
                try database.run("INSERT OR REPLACE INTO store_metadata VALUES ('content_preview_v1', 1)")
                try database.run("DELETE FROM store_metadata WHERE key = 'content_preview_cursor'")
                return true
            }
            for id in ids {
                let preview = try legacyContentPreview(id)
                try database.run("UPDATE clips SET content_preview = ? WHERE id = ?", [.text(preview), .integer(id)])
            }
            try database.run("INSERT OR REPLACE INTO store_metadata VALUES ('content_preview_cursor', ?)", [.integer(last)])
            return false
        }
    }

    private func legacyContentPreview(_ id: Int64) throws -> String {
        let statement = try database.prepare("""
            SELECT item_index, substr(data, 1, ?), blob_file FROM representations
            WHERE clip_id = ? AND type = 'public.utf8-plain-text' ORDER BY item_index, position
            """)
        try statement.bind([.integer(Int64(Self.contentPreviewByteLimit)), .integer(id)])
        var prefix = Data()
        var lastItem: Int64?
        while prefix.count < Self.contentPreviewByteLimit, try statement.step() {
            let item = statement.integer(0)
            if item == lastItem { continue }
            if lastItem != nil { prefix.append(10) }
            lastItem = item
            let remaining = Self.contentPreviewByteLimit - prefix.count
            if let file = statement.text(2) {
                // Preview bytes are nonessential: missing/unreadable blobs must not hide the history.
                // Keep this catch local to file IO so SQLite read/update failures still propagate.
                do {
                    let handle = try FileHandle(forReadingFrom: blobDirectory.appendingPathComponent(file))
                    defer { try? handle.close() }
                    prefix.append(try handle.read(upToCount: remaining) ?? Data())
                } catch { continue }
            } else {
                prefix.append((statement.blob(1) ?? Data()).prefix(remaining))
            }
        }
        // Lossy prefix decoding retains valid text if the byte budget splits a UTF-8 scalar.
        return Self.contentLines(String(decoding: prefix, as: UTF8.self))
    }

    // MARK: writing

    /// Records a copy. An identical earlier copy moves to the top instead of being stored twice.
    @discardableResult
    func record(_ clip: CapturedClip, at date: Date = Date()) throws -> Int64 {
        lock.lock(); defer { lock.unlock() }
        let hash = clip.contentHash
        return try database.transaction {
            let existing = try database.query("SELECT id FROM clips WHERE content_hash = ?", [.text(hash)]) {
                $0.integer(0)
            }
            if let id = existing.first {
                try database.run("""
                    UPDATE clips SET last_copied_at = ?, copy_count = copy_count + 1,
                        source_app_name = ?, source_bundle_identifier = ? WHERE id = ?
                    """, [.real(date.timeIntervalSince1970), .optionalText(clip.sourceAppName),
                          .optionalText(clip.sourceBundleIdentifier), .integer(id)])
                try incrementActivity(at: date)
                return id
            }
            try database.run("""
                INSERT INTO clips (content_hash, first_copied_at, last_copied_at, source_app_name,
                    source_bundle_identifier, kind, preview, content_preview, byte_size) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, [.text(hash), .real(date.timeIntervalSince1970), .real(date.timeIntervalSince1970),
                      .optionalText(clip.sourceAppName), .optionalText(clip.sourceBundleIdentifier),
                      .text(clip.kind), .text(clip.preview), .text(Self.capturedContentPreview(clip)), .integer(Int64(clip.byteSize))])
            let id = database.lastInsertedRowID
            for (itemIndex, item) in clip.items.enumerated() {
                for (position, representation) in item.enumerated() {
                    var data: SQLiteValue = .blob(representation.data)
                    var blobFile: SQLiteValue = .null
                    if representation.data.count > Self.blobThreshold {
                        blobFile = .text(try writeBlob(representation.data))
                        data = .null
                    }
                    try database.run("""
                        INSERT INTO representations (clip_id, item_index, position, type, data, blob_file, byte_size)
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                        """, [.integer(id), .integer(Int64(itemIndex)), .integer(Int64(position)),
                              .text(representation.type), data, blobFile, .integer(Int64(representation.data.count))])
                }
            }
            if let text = clip.plainText {
                try database.run("INSERT INTO clip_search (rowid, body) VALUES (?, ?)",
                                 [.integer(id), .text(String(text.prefix(Self.searchTextLimit)))])
            }
            try incrementActivity(at: date)
            return id
        }
    }

    private func incrementActivity(at date: Date) throws {
        let hour = Int64(floor(date.timeIntervalSince1970 / 3600))
        try database.run("INSERT INTO copy_activity(hour, copies) VALUES (?, 1) ON CONFLICT(hour) DO UPDATE SET copies = copies + 1", [.integer(hour)])
        let cutoff = hour - 10 * 24
        try database.run("DELETE FROM copy_activity WHERE hour < ?", [.integer(cutoff)])
    }

    /// Bounded rolling window of absolute UTC-hour buckets; start and end are inclusive bucket boundaries.
    func copyActivity(from start: Date, through end: Date) throws -> [(hour: Int64, copies: Int)] {
        lock.lock(); defer { lock.unlock() }
        let requestedFirst = Int64(floor(start.timeIntervalSince1970 / 3600))
        let last = Int64(floor(end.timeIntervalSince1970 / 3600))
        guard requestedFirst <= last else { return [] }
        let horizonStart = last - 10 * 24
        let first = max(requestedFirst, horizonStart)
        // Queries enforce the retention horizon even when capture has been idle for a long time.
        try database.run("DELETE FROM copy_activity WHERE hour < ?", [.integer(horizonStart)])
        return try database.query("SELECT hour, copies FROM copy_activity WHERE hour BETWEEN ? AND ? ORDER BY hour", [.integer(first), .integer(last)]) { ($0.integer(0), Int($0.integer(1))) }
    }

    /// Moves a clip to the top, for example after it was recalled.
    func touch(_ id: Int64, at date: Date = Date()) throws {
        lock.lock(); defer { lock.unlock() }
        try database.run("UPDATE clips SET last_copied_at = ? WHERE id = ?", [.real(date.timeIntervalSince1970), .integer(id)])
    }

    func delete(_ id: Int64) throws {
        lock.lock(); defer { lock.unlock() }
        try deleteLocked([id])
    }

    /// Deletes every clip and blob file.
    func deleteAll() throws {
        lock.lock(); defer { lock.unlock() }
        try database.transaction {
            try database.run("DELETE FROM clips")
            try database.run("DELETE FROM clip_search")
        }
        let files = (try? FileManager.default.contentsOfDirectory(at: blobDirectory, includingPropertiesForKeys: nil)) ?? []
        for file in files { try? FileManager.default.removeItem(at: file) }
        try database.execute("PRAGMA wal_checkpoint(TRUNCATE); VACUUM;")
    }

    /// Enforces count and total representation-byte limits, removing oldest clips first.
    @discardableResult
    func enforceRetention(countLimit: Int, maximumBytes: Int, now: Date = Date()) throws -> Int {
        lock.lock(); defer { lock.unlock() }
        var removed = 0
        let totals = try retentionTotals()
        var count = totals.count
        var bytes = totals.bytes
        while count > max(0, countLimit) || bytes > Int64(max(0, maximumBytes)) {
            let rows = try database.query("SELECT id, byte_size FROM clips ORDER BY last_copied_at, id LIMIT ?",
                                          [.integer(Int64(Self.maintenanceBatchSize))]) { ($0.integer(0), $0.integer(1)) }
            guard !rows.isEmpty else { break }
            var ids: [Int64] = []
            for (id, size) in rows {
                guard count > max(0, countLimit) || bytes > Int64(max(0, maximumBytes)) else { break }
                ids.append(id)
                count -= 1
                bytes -= size
            }
            try deleteLocked(ids)
            removed += ids.count
        }
        return removed
    }

    private func retentionTotals() throws -> (count: Int, bytes: Int64) {
        try database.query("SELECT clip_count, clip_bytes FROM clip_totals WHERE singleton = 1") {
            (Int($0.integer(0)), $0.integer(1))
        }.first ?? (0, 0)
    }

    /// Deletes the least recently copied clips beyond `limit`. Returns how many were deleted.
    @discardableResult
    func enforceLimit(_ limit: Int) throws -> Int {
        lock.lock(); defer { lock.unlock() }
        var excess = max(0, try retentionTotals().count - max(0, limit))
        var removed = 0
        while excess > 0 {
            let ids = try database.query("SELECT id FROM clips ORDER BY last_copied_at, id LIMIT ?",
                                         [.integer(Int64(min(excess, Self.maintenanceBatchSize)))]) { $0.integer(0) }
            guard !ids.isEmpty else { break }
            try deleteLocked(ids)
            excess -= ids.count
            removed += ids.count
        }
        return removed
    }

    private func deleteLocked(_ ids: [Int64]) throws {
        guard !ids.isEmpty else { return }
        var orphanCandidates = Set<String>()
        try database.transaction {
            for id in ids {
                let files = try database.query(
                    "SELECT blob_file FROM representations WHERE clip_id = ? AND blob_file IS NOT NULL",
                    [.integer(id)]) { $0.text(0) }
                orphanCandidates.formUnion(files.compactMap { $0 })
                try database.run("DELETE FROM clips WHERE id = ?", [.integer(id)])
                try database.run("DELETE FROM clip_search WHERE rowid = ?", [.integer(id)])
            }
        }
        for file in orphanCandidates {
            let stillUsed = try database.query("SELECT 1 FROM representations WHERE blob_file = ? LIMIT 1",
                                               [.text(file)]) { $0.integer(0) }
            if stillUsed.isEmpty { try? FileManager.default.removeItem(at: blobDirectory.appendingPathComponent(file)) }
        }
    }

    /// Content-addressed, so the same large data copied twice is stored once.
    private func writeBlob(_ data: Data) throws -> String {
        let name = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let url = blobDirectory.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path) { try data.write(to: url, options: .atomic) }
        return name
    }

    // MARK: reading

    private static let summaryColumns = """
        id, kind, preview, content_preview, byte_size, first_copied_at, last_copied_at, copy_count, source_app_name
        """

    private static func capturedContentPreview(_ clip: CapturedClip) -> String {
        var prefix = Data()
        var hasTextItem = false
        for item in clip.items {
            guard prefix.count < contentPreviewByteLimit else { break }
            guard let representation = item.first(where: { $0.type == "public.utf8-plain-text" }) else { continue }
            if hasTextItem { prefix.append(10) }
            hasTextItem = true
            prefix.append(representation.data.prefix(contentPreviewByteLimit - prefix.count))
        }
        return contentLines(String(decoding: prefix, as: UTF8.self))
    }

    /// Five consecutive lines, 500 Characters each. CRLF is one Character/newline in Swift.
    /// A line longer than the 64 KiB scan budget can hide later lines; no whole-input splitting is done.
    static func contentLines(_ text: String) -> String {
        let bounded = String(decoding: text.utf8.prefix(contentPreviewByteLimit), as: UTF8.self)
        var lines: [String] = []
        var line = ""
        var characters = 0
        for character in bounded {
            if character.isNewline {
                lines.append(line)
                if lines.count == 5 { return lines.joined(separator: "\n") }
                line = ""
                characters = 0
            } else if characters < 500 {
                line.append(character)
                characters += 1
            }
        }
        lines.append(line)
        return lines.joined(separator: "\n")
    }

    private static func summary(_ row: SQLiteStatement) -> ClipSummary {
        ClipSummary(id: row.integer(0), kind: row.text(1) ?? "", preview: row.text(2) ?? "",
                    byteSize: Int(row.integer(4)), firstCopiedAt: Date(timeIntervalSince1970: row.real(5)),
                    lastCopiedAt: Date(timeIntervalSince1970: row.real(6)), copyCount: Int(row.integer(7)),
                    sourceAppName: row.text(8), contentPreview: row.text(3) ?? "")
    }

    func recent(limit: Int) throws -> [ClipSummary] {
        lock.lock(); defer { lock.unlock() }
        return try database.query("SELECT \(Self.summaryColumns) FROM clips ORDER BY last_copied_at DESC, id DESC LIMIT ?",
                                  [.integer(Int64(limit))], Self.summary)
    }

    /// Substring search over clip text, most recently copied first. Queries shorter than 3 characters use LIKE,
    /// because the trigram index needs 3.
    func search(_ query: String, limit: Int) throws -> [ClipSummary] {
        lock.lock(); defer { lock.unlock() }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return try database.query("SELECT \(Self.summaryColumns) FROM clips ORDER BY last_copied_at DESC, id DESC LIMIT ?",
                                      [.integer(Int64(limit))], Self.summary)
        }
        if trimmed.count < 3 {
            return try database.query("""
                SELECT \(Self.summaryColumns) FROM clips WHERE id IN
                    (SELECT rowid FROM clip_search WHERE body LIKE ? ESCAPE '\\')
                ORDER BY last_copied_at DESC, id DESC LIMIT ?
                """, [.text("%" + Self.escapeLike(trimmed) + "%"), .integer(Int64(limit))], Self.summary)
        }
        let phrase = "\"" + trimmed.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        return try database.query("""
            SELECT \(Self.summaryColumns) FROM clips WHERE id IN
                (SELECT rowid FROM clip_search WHERE clip_search MATCH ?)
            ORDER BY last_copied_at DESC, id DESC LIMIT ?
            """, [.text(phrase), .integer(Int64(limit))], Self.summary)
    }

    private static func escapeLike(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    /// A bounded thumbnail for an image representation. Blob-backed images are decoded from their file URL,
    /// so the original representation is never copied into memory just to draw a picker row.
    func thumbnail(for id: Int64, maximumPixelSize: Int) throws -> NSImage? {
        guard maximumPixelSize > 0 else { return nil }
        lock.lock(); defer { lock.unlock() }
        let rows = try database.query("""
            SELECT type, data, blob_file FROM representations
            WHERE clip_id = ? ORDER BY item_index, position
            """, [.integer(id)]) { ($0.text(0) ?? "", $0.blob(1), $0.text(2)) }
        for (type, data, blobFile) in rows where UTType(type)?.conforms(to: .image) == true {
            let source: CGImageSource?
            if let blobFile {
                source = CGImageSourceCreateWithURL(blobDirectory.appendingPathComponent(blobFile) as CFURL, nil)
            } else if let data {
                source = CGImageSourceCreateWithData(data as CFData, nil)
            } else { continue }
            guard let source,
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                  ] as CFDictionary) else { continue }
            return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }
        return nil
    }

    /// The stored pasteboard items of one clip, read from the database and blob files.
    func items(for id: Int64) throws -> [[Representation]] {
        lock.lock(); defer { lock.unlock() }
        let rows = try database.query("""
            SELECT item_index, type, data, blob_file FROM representations WHERE clip_id = ?
            ORDER BY item_index, position
            """, [.integer(id)]) { row in
            (Int(row.integer(0)), row.text(1) ?? "", row.blob(2), row.text(3))
        }
        var items: [[Representation]] = []
        for (itemIndex, type, data, blobFile) in rows {
            let bytes: Data
            if let blobFile {
                bytes = try Data(contentsOf: blobDirectory.appendingPathComponent(blobFile), options: .mappedIfSafe)
            } else {
                bytes = data ?? Data()
            }
            while items.count <= itemIndex { items.append([]) }
            items[itemIndex].append(Representation(type: type, data: bytes))
        }
        return items.filter { !$0.isEmpty }
    }

    func statistics() throws -> StoreStatistics {
        lock.lock(); defer { lock.unlock() }
        let totals = try database.query("""
            SELECT clip_count, clip_bytes, (SELECT min(first_copied_at) FROM clips)
            FROM clip_totals WHERE singleton = 1
            """) {
            row in (Int(row.integer(0)), Int(row.integer(1)), row.isNull(2) ? nil : Date(timeIntervalSince1970: row.real(2)))
        }.first ?? (0, 0, nil)
        let latest = try database.query("SELECT \(Self.summaryColumns) FROM clips ORDER BY last_copied_at DESC, id DESC LIMIT 1",
                                        [], Self.summary).first
        return StoreStatistics(clipCount: totals.0, clipBytes: totals.1, diskBytes: diskBytes(),
                               oldestCopiedAt: totals.2, latest: latest)
    }

    private func diskBytes() -> Int {
        var total = 0
        for suffix in ["", "-wal", "-shm"] {
            let path = databaseURL.path + suffix
            total += ((try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int) ?? 0
        }
        let files = (try? FileManager.default.contentsOfDirectory(at: blobDirectory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        for file in files { total += (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
        return total
    }
}
