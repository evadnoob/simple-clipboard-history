import Foundation
import SQLite3

struct SQLiteError: Error, CustomStringConvertible {
    let code: Int32
    let message: String
    var description: String { "sqlite error \(code): \(message)" }
}

/// A thin wrapper over the system SQLite library. Not thread-safe; callers serialize access.
final class SQLiteDatabase {
    private var handle: OpaquePointer?

    init(path: String) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
        let code = sqlite3_open_v2(path, &handle, flags, nil)
        if code != SQLITE_OK {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open"
            sqlite3_close(handle)
            throw SQLiteError(code: code, message: message)
        }
        sqlite3_busy_timeout(handle, 2000)
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let code = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
        if code != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errorMessage)
            throw SQLiteError(code: code, message: message)
        }
    }

    func prepare(_ sql: String) throws -> SQLiteStatement {
        var statement: OpaquePointer?
        let code = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard code == SQLITE_OK, let statement else { throw error(code) }
        return SQLiteStatement(statement: statement, database: self)
    }

    /// Runs one statement with the given parameters and no result rows.
    func run(_ sql: String, _ parameters: [SQLiteValue] = []) throws {
        let statement = try prepare(sql)
        try statement.bind(parameters)
        while try statement.step() {}
    }

    /// Runs a query and maps every row.
    func query<T>(_ sql: String, _ parameters: [SQLiteValue] = [], _ map: (SQLiteStatement) -> T) throws -> [T] {
        let statement = try prepare(sql)
        try statement.bind(parameters)
        var rows: [T] = []
        while try statement.step() { rows.append(map(statement)) }
        return rows
    }

    var lastInsertedRowID: Int64 { sqlite3_last_insert_rowid(handle) }
    var changes: Int { Int(sqlite3_changes(handle)) }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    fileprivate func error(_ code: Int32) -> SQLiteError {
        SQLiteError(code: code, message: String(cString: sqlite3_errmsg(handle)))
    }
}

enum SQLiteValue {
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)
    case null

    static func optionalText(_ text: String?) -> SQLiteValue { text.map { .text($0) } ?? .null }
}

private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class SQLiteStatement {
    private let statement: OpaquePointer
    private let database: SQLiteDatabase

    fileprivate init(statement: OpaquePointer, database: SQLiteDatabase) {
        self.statement = statement
        self.database = database
    }

    deinit {
        sqlite3_finalize(statement)
    }

    func bind(_ parameters: [SQLiteValue]) throws {
        for (offset, value) in parameters.enumerated() {
            let index = Int32(offset + 1)
            let code: Int32
            switch value {
            case .integer(let number): code = sqlite3_bind_int64(statement, index, number)
            case .real(let number): code = sqlite3_bind_double(statement, index, number)
            case .text(let text): code = sqlite3_bind_text(statement, index, text, -1, transient)
            case .blob(let data):
                code = data.withUnsafeBytes { buffer in
                    sqlite3_bind_blob64(statement, index, buffer.baseAddress ?? UnsafeRawPointer(bitPattern: 1),
                                        sqlite3_uint64(data.count), transient)
                }
            case .null: code = sqlite3_bind_null(statement, index)
            }
            if code != SQLITE_OK { throw database.error(code) }
        }
    }

    /// Returns true while there is a row to read.
    func step() throws -> Bool {
        let code = sqlite3_step(statement)
        switch code {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default: throw database.error(code)
        }
    }

    func integer(_ column: Int32) -> Int64 { sqlite3_column_int64(statement, column) }
    func real(_ column: Int32) -> Double { sqlite3_column_double(statement, column) }
    func isNull(_ column: Int32) -> Bool { sqlite3_column_type(statement, column) == SQLITE_NULL }

    func text(_ column: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: pointer)
    }

    func blob(_ column: Int32) -> Data? {
        guard !isNull(column) else { return nil }
        let count = Int(sqlite3_column_bytes(statement, column))
        guard count > 0, let pointer = sqlite3_column_blob(statement, column) else { return Data() }
        return Data(bytes: pointer, count: count)
    }
}
