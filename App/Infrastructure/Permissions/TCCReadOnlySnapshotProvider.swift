import Foundation
import SQLite3

protocol TCCSnapshotProviding: Sendable {
    func snapshot(for service: String) -> Result<[TCCSnapshotEntry], PermissionUnavailableReason>
}

struct TCCSnapshotEntry: Sendable, Equatable {
    let client: String
    let clientType: Int
    let status: PermissionGrantStatus
    let lastUpdatedAt: Date?
}

struct TCCReadOnlySnapshotProvider: TCCSnapshotProviding {
    private let databaseURLs: [URL]

    init(
        databaseURLs: [URL] = TCCDatabaseLocator.defaultDatabaseURLs()
    ) {
        self.databaseURLs = databaseURLs
    }

    func snapshot(for service: String) -> Result<[TCCSnapshotEntry], PermissionUnavailableReason> {
        let existingURLs = databaseURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard existingURLs.isEmpty == false else {
            return .failure(.resourceUnavailable)
        }

        var combinedEntries: [TCCSnapshotEntry] = []
        var sawUnreadableDatabase = false
        var sawUnsupportedSchema = false

        for url in existingURLs {
            switch readDatabase(at: url, service: service) {
            case .success(let entries):
                combinedEntries.append(contentsOf: entries)
            case .failure(.unsupportedOnCurrentSystem):
                sawUnsupportedSchema = true
            case .failure:
                sawUnreadableDatabase = true
            }
        }

        if combinedEntries.isEmpty == false {
            return .success(combinedEntries)
        }
        if sawUnsupportedSchema {
            return .failure(.unsupportedOnCurrentSystem)
        }
        if sawUnreadableDatabase {
            return .failure(.databaseUnreadable)
        }
        return .success([])
    }

    private func readDatabase(at url: URL, service: String) -> Result<[TCCSnapshotEntry], PermissionUnavailableReason> {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK, let db else {
            if let db {
                sqlite3_close(db)
            }
            return .failure(.databaseUnreadable)
        }
        defer { sqlite3_close(db) }

        guard let columns = accessTableColumns(in: db), columns.contains("service"), columns.contains("client") else {
            return .failure(.unsupportedOnCurrentSystem)
        }

        let statusExpression: String
        if columns.contains("auth_value") {
            statusExpression = "auth_value"
        } else if columns.contains("allowed") {
            statusExpression = "allowed"
        } else {
            return .failure(.unsupportedOnCurrentSystem)
        }

        let clientTypeExpression = columns.contains("client_type") ? "client_type" : "0"
        let lastModifiedExpression = columns.contains("last_modified") ? "last_modified" : "NULL"
        let sql = """
        SELECT client, \(clientTypeExpression), \(statusExpression), \(lastModifiedExpression)
        FROM access
        WHERE service = ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return .failure(.databaseUnreadable)
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_bind_text(statement, 1, service, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            return .failure(.databaseUnreadable)
        }

        var entries: [TCCSnapshotEntry] = []
        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_DONE {
                return .success(entries)
            }
            guard stepResult == SQLITE_ROW else {
                return .failure(.databaseUnreadable)
            }

            guard let client = Self.stringColumn(statement, index: 0) else {
                continue
            }
            let clientType = Int(sqlite3_column_int(statement, 1))
            let rawStatus = Int(sqlite3_column_int(statement, 2))
            let lastUpdatedAt: Date?
            if sqlite3_column_type(statement, 3) == SQLITE_NULL {
                lastUpdatedAt = nil
            } else {
                lastUpdatedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
            }
            entries.append(
                TCCSnapshotEntry(
                    client: client,
                    clientType: clientType,
                    status: Self.status(from: rawStatus, hasAuthValueColumn: columns.contains("auth_value")),
                    lastUpdatedAt: lastUpdatedAt
                )
            )
        }
    }

    private func accessTableColumns(in db: OpaquePointer) -> Set<String>? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(access);", -1, &statement, nil) == SQLITE_OK, let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        var columns: Set<String> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = Self.stringColumn(statement, index: 1) {
                columns.insert(name)
            }
        }
        return columns
    }

    private static func status(from rawValue: Int, hasAuthValueColumn: Bool) -> PermissionGrantStatus {
        if hasAuthValueColumn {
            switch rawValue {
            case 0: return .denied
            case 1: return .unknown
            case 2: return .authorized
            case 3: return .restricted
            default: return .unknown
            }
        }

        switch rawValue {
        case 0: return .denied
        case 1: return .authorized
        default: return .unknown
        }
    }

    private static func stringColumn(_ statement: OpaquePointer, index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let cString = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: cString)
    }
}

enum TCCDatabaseLocator {
    static func defaultDatabaseURLs() -> [URL] {
        [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db"),
            URL(fileURLWithPath: "/Library/Application Support/com.apple.TCC/TCC.db")
        ]
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
