import CryptoKit
import Foundation

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
                byte_size INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS clips_last_copied_at ON clips (last_copied_at);
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
                return id
            }
            try database.run("""
                INSERT INTO clips (content_hash, first_copied_at, last_copied_at, source_app_name,
                    source_bundle_identifier, kind, preview, byte_size) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, [.text(hash), .real(date.timeIntervalSince1970), .real(date.timeIntervalSince1970),
                      .optionalText(clip.sourceAppName), .optionalText(clip.sourceBundleIdentifier),
                      .text(clip.kind), .text(clip.preview), .integer(Int64(clip.byteSize))])
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
            return id
        }
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

    /// Deletes the least recently copied clips beyond `limit`. Returns how many were deleted.
    @discardableResult
    func enforceLimit(_ limit: Int) throws -> Int {
        lock.lock(); defer { lock.unlock() }
        let ids = try database.query("SELECT id FROM clips ORDER BY last_copied_at DESC LIMIT -1 OFFSET ?",
                                     [.integer(Int64(max(limit, 0)))]) { $0.integer(0) }
        try deleteLocked(ids)
        return ids.count
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
        id, kind, preview, byte_size, first_copied_at, last_copied_at, copy_count, source_app_name
        """

    private static func summary(_ row: SQLiteStatement) -> ClipSummary {
        ClipSummary(id: row.integer(0), kind: row.text(1) ?? "", preview: row.text(2) ?? "",
                    byteSize: Int(row.integer(3)), firstCopiedAt: Date(timeIntervalSince1970: row.real(4)),
                    lastCopiedAt: Date(timeIntervalSince1970: row.real(5)), copyCount: Int(row.integer(6)),
                    sourceAppName: row.text(7))
    }

    func recent(limit: Int) throws -> [ClipSummary] {
        lock.lock(); defer { lock.unlock() }
        return try database.query("SELECT \(Self.summaryColumns) FROM clips ORDER BY last_copied_at DESC LIMIT ?",
                                  [.integer(Int64(limit))], Self.summary)
    }

    /// Substring search over clip text, most recently copied first. Queries shorter than 3 characters use LIKE,
    /// because the trigram index needs 3.
    func search(_ query: String, limit: Int) throws -> [ClipSummary] {
        lock.lock(); defer { lock.unlock() }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return try database.query("SELECT \(Self.summaryColumns) FROM clips ORDER BY last_copied_at DESC LIMIT ?",
                                      [.integer(Int64(limit))], Self.summary)
        }
        if trimmed.count < 3 {
            return try database.query("""
                SELECT \(Self.summaryColumns) FROM clips WHERE id IN
                    (SELECT rowid FROM clip_search WHERE body LIKE ? ESCAPE '\\')
                ORDER BY last_copied_at DESC LIMIT ?
                """, [.text("%" + Self.escapeLike(trimmed) + "%"), .integer(Int64(limit))], Self.summary)
        }
        let phrase = "\"" + trimmed.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        return try database.query("""
            SELECT \(Self.summaryColumns) FROM clips WHERE id IN
                (SELECT rowid FROM clip_search WHERE clip_search MATCH ?)
            ORDER BY last_copied_at DESC LIMIT ?
            """, [.text(phrase), .integer(Int64(limit))], Self.summary)
    }

    private static func escapeLike(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
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
        let totals = try database.query("SELECT count(*), coalesce(sum(byte_size), 0), min(first_copied_at) FROM clips") {
            row in (Int(row.integer(0)), Int(row.integer(1)), row.isNull(2) ? nil : Date(timeIntervalSince1970: row.real(2)))
        }.first ?? (0, 0, nil)
        let latest = try database.query("SELECT \(Self.summaryColumns) FROM clips ORDER BY last_copied_at DESC LIMIT 1",
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
