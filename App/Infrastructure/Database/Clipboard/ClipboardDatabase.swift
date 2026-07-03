import Foundation
import SQLite3

public final class ClipboardDatabase: @unchecked Sendable {
    public static let currentVersion = 1

    private let location: ClipboardStorageLocation
    private let lock = NSLock()
    private var connection: OpaquePointer?

    public init(location: ClipboardStorageLocation) throws {
        self.location = location
        try location.prepare()
        try open()
        try execute("PRAGMA foreign_keys = ON;")
    }

    deinit {
        lock.lock()
        let db = connection
        connection = nil
        lock.unlock()
        if let db {
            sqlite3_close(db)
        }
    }

    public func initialize() throws {
        try execute(Self.schemaSQL)
        try execute(
            """
            INSERT OR IGNORE INTO clipboard_schema_migrations(version, applied_at)
            VALUES (\(Self.currentVersion), strftime('%Y-%m-%dT%H:%M:%fZ', 'now'));
            """
        )
    }

    public func currentSchemaVersion() throws -> Int {
        try queryInt("SELECT COALESCE(MAX(version), 0) FROM clipboard_schema_migrations;")
    }

    public func tableExists(_ tableName: String) throws -> Bool {
        guard !tableName.isEmpty else { return false }
        return try queryInt(
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?;",
            bindings: [tableName]
        ) > 0
    }

    private func open() throws {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(location.databaseURL.path, &db, flags, nil)
        guard result == SQLITE_OK, let db else {
            if let db {
                sqlite3_close(db)
            }
            throw AppError.systemFailure(code: "sqlite_open")
        }
        connection = db
    }

    private func execute(_ sql: String) throws {
        try withConnection { db in
            var errorMessage: UnsafeMutablePointer<CChar>?
            let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
            if let errorMessage {
                sqlite3_free(errorMessage)
            }
            guard result == SQLITE_OK else {
                throw AppError.systemFailure(code: "sqlite_exec")
            }
        }
    }

    private func queryInt(_ sql: String, bindings: [String] = []) throws -> Int {
        try withConnection { db in
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw AppError.systemFailure(code: "sqlite_prepare")
            }
            defer { sqlite3_finalize(statement) }

            for (index, value) in bindings.enumerated() {
                let bindIndex = Int32(index + 1)
                guard sqlite3_bind_text(statement, bindIndex, value, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
                    throw AppError.systemFailure(code: "sqlite_bind")
                }
            }

            let result = sqlite3_step(statement)
            guard result == SQLITE_ROW else {
                if result == SQLITE_DONE {
                    return 0
                }
                throw AppError.systemFailure(code: "sqlite_step")
            }
            return Int(sqlite3_column_int(statement, 0))
        }
    }

    internal func withConnection<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        guard let connection else {
            throw AppError.invalidState(detail: "clipboard_database_closed")
        }
        return try body(connection)
    }

    private static let schemaSQL = """
    CREATE TABLE IF NOT EXISTS clipboard_schema_migrations (
        version INTEGER PRIMARY KEY,
        applied_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS clipboard_items (
        id TEXT PRIMARY KEY,
        content_hash TEXT NOT NULL UNIQUE,
        content_type TEXT NOT NULL,
        text_preview TEXT,
        source_application_id TEXT,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        times_used INTEGER NOT NULL DEFAULT 1,
        created_at REAL NOT NULL,
        updated_at REAL NOT NULL
    );

    CREATE INDEX IF NOT EXISTS idx_clipboard_items_updated_at
    ON clipboard_items(updated_at DESC);

    CREATE INDEX IF NOT EXISTS idx_clipboard_items_content_type
    ON clipboard_items(content_type);

    CREATE INDEX IF NOT EXISTS idx_clipboard_items_is_favorite
    ON clipboard_items(is_favorite);

    CREATE INDEX IF NOT EXISTS idx_clipboard_items_is_deleted
    ON clipboard_items(is_deleted);

    CREATE TABLE IF NOT EXISTS clipboard_binary_payloads (
        record_id TEXT NOT NULL,
        storage_path TEXT NOT NULL,
        original_format TEXT NOT NULL,
        file_size INTEGER NOT NULL,
        created_at REAL NOT NULL,
        PRIMARY KEY(record_id, original_format),
        FOREIGN KEY(record_id) REFERENCES clipboard_items(id) ON DELETE CASCADE
    );
    """
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
