import Foundation
import SQLite3

/// 剪切板记录仓储:在 `ClipboardDatabase` 之上提供记录级 CRUD。
///
/// 重复 `contentHash` 不新增记录,而是更新使用次数和最近更新时间。
public final class ClipboardRepository: @unchecked Sendable {
    private let database: ClipboardDatabase

    public init(database: ClipboardDatabase) {
        self.database = database
    }

    /// 插入一条记录;重复 `contentHash` 会更新既有记录并返回更新后的记录。
    @discardableResult
    public func insert(_ item: ClipboardItem) throws -> ClipboardItem {
        try database.withConnection { db in
            var statement: OpaquePointer?
            let sql = """
            INSERT INTO clipboard_items
                (id, content_hash, content_type, text_preview, source_application_id,
                 is_favorite, is_deleted, times_used, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw AppError.systemFailure(code: "clipboard_insert_prepare")
            }
            defer { sqlite3_finalize(statement) }

            bindText(statement, 1, item.id.uuidString)
            bindText(statement, 2, item.contentHash)
            bindText(statement, 3, item.contentType.rawValue)
            bindText(statement, 4, item.textPreview)
            bindText(statement, 5, item.sourceApplicationID)
            sqlite3_bind_int(statement, 6, item.isFavorite ? 1 : 0)
            sqlite3_bind_int(statement, 7, item.isDeleted ? 1 : 0)
            sqlite3_bind_int(statement, 8, Int32(clamping: item.timesUsed))
            sqlite3_bind_double(statement, 9, item.createdAt.timeIntervalSince1970)
            sqlite3_bind_double(statement, 10, item.updatedAt.timeIntervalSince1970)

            switch sqlite3_step(statement) {
            case SQLITE_DONE:
                return item
            case SQLITE_CONSTRAINT:
                try updateDuplicate(db: db, with: item)
                return try fetchItem(withContentHash: item.contentHash, db: db)
            default:
                throw AppError.systemFailure(code: "clipboard_insert_step")
            }
        }
    }

    /// 按 `query` 过滤、搜索、分页查询,默认按 `updated_at` 降序返回。
    public func records(matching query: ClipboardQuery) throws -> [ClipboardItem] {
        try database.withConnection { db in
            var sql = """
            SELECT id, content_hash, content_type, text_preview, source_application_id,
                   is_favorite, is_deleted, times_used, created_at, updated_at
            FROM clipboard_items
            WHERE 1 = 1
            """
            if !query.includeDeleted { sql += " AND is_deleted = 0" }
            if query.favoritesOnly { sql += " AND is_favorite = 1" }
            if query.contentType != nil { sql += " AND content_type = ?" }
            if !query.searchText.isEmpty { sql += " AND text_preview LIKE ?" }
            sql += " ORDER BY updated_at DESC LIMIT ? OFFSET ?;"

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw AppError.systemFailure(code: "clipboard_query_prepare")
            }
            defer { sqlite3_finalize(statement) }

            var index: Int32 = 1
            if let type = query.contentType {
                bindText(statement, index, type.rawValue)
                index += 1
            }
            if !query.searchText.isEmpty {
                bindText(statement, index, "%\(query.searchText)%")
                index += 1
            }
            sqlite3_bind_int(statement, index, Int32(clamping: query.limit)); index += 1
            sqlite3_bind_int(statement, index, Int32(clamping: query.offset))

            var rows: [ClipboardItem] = []
            var stepResult = sqlite3_step(statement)
            while stepResult == SQLITE_ROW {
                rows.append(try readItem(statement))
                stepResult = sqlite3_step(statement)
            }
            guard stepResult == SQLITE_DONE else {
                throw AppError.systemFailure(code: "clipboard_query_step")
            }
            return rows
        }
    }

    /// 切换收藏。仅对未软删记录生效。
    /// - Returns: 是否实际命中并更新了一条记录。
    @discardableResult
    public func setFavorite(_ isFavorite: Bool, for id: ClipboardItem.ID) throws -> Bool {
        try database.withConnection { db in
            var statement: OpaquePointer?
            let sql = """
            UPDATE clipboard_items
            SET is_favorite = ?, updated_at = ?
            WHERE id = ? AND is_deleted = 0;
            """
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw AppError.systemFailure(code: "clipboard_favorite_prepare")
            }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int(statement, 1, isFavorite ? 1 : 0)
            sqlite3_bind_double(statement, 2, Date().timeIntervalSince1970)
            bindText(statement, 3, id.uuidString)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw AppError.systemFailure(code: "clipboard_favorite_step")
            }
            return sqlite3_changes(db) > 0
        }
    }

    /// 软删除(置 `is_deleted = 1`)。已软删记录返回 `false`。
    @discardableResult
    public func softDelete(_ id: ClipboardItem.ID) throws -> Bool {
        try database.withConnection { db in
            var statement: OpaquePointer?
            let sql = """
            UPDATE clipboard_items
            SET is_deleted = 1, updated_at = ?
            WHERE id = ? AND is_deleted = 0;
            """
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw AppError.systemFailure(code: "clipboard_softdelete_prepare")
            }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_double(statement, 1, Date().timeIntervalSince1970)
            bindText(statement, 2, id.uuidString)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw AppError.systemFailure(code: "clipboard_softdelete_step")
            }
            return sqlite3_changes(db) > 0
        }
    }

    /// 计数。默认排除软删记录。
    public func count(includeDeleted: Bool = false) throws -> Int {
        try database.withConnection { db in
            let sql = includeDeleted
                ? "SELECT COUNT(*) FROM clipboard_items;"
                : "SELECT COUNT(*) FROM clipboard_items WHERE is_deleted = 0;"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw AppError.systemFailure(code: "clipboard_count_prepare")
            }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw AppError.systemFailure(code: "clipboard_count_step")
            }
            return Int(sqlite3_column_int(statement, 0))
        }
    }

    // MARK: - Binary Payloads

    /// 写入二进制 payload 元数据。
    /// - Returns: 成功返回该 payload;若 `(recordID, format)` 已存在或外键约束失败,返回 `nil`。
    @discardableResult
    public func insertPayload(_ payload: ClipboardBinaryPayload) throws -> ClipboardBinaryPayload? {
        try database.withConnection { db in
            var statement: OpaquePointer?
            let sql = """
            INSERT INTO clipboard_binary_payloads
                (record_id, storage_path, original_format, file_size, created_at)
            VALUES (?, ?, ?, ?, ?);
            """
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw AppError.systemFailure(code: "clipboard_payload_insert_prepare")
            }
            defer { sqlite3_finalize(statement) }
            bindText(statement, 1, payload.recordID.uuidString)
            bindText(statement, 2, payload.storagePath)
            bindText(statement, 3, payload.format.rawValue)
            sqlite3_bind_int64(statement, 4, Int64(payload.fileSize))
            sqlite3_bind_double(statement, 5, payload.createdAt.timeIntervalSince1970)

            switch sqlite3_step(statement) {
            case SQLITE_DONE:
                return payload
            case SQLITE_CONSTRAINT:
                return nil
            default:
                throw AppError.systemFailure(code: "clipboard_payload_insert_step")
            }
        }
    }

    /// 按 recordID 查询全部 payload 元数据,按格式排序。
    public func payloads(for recordID: ClipboardItem.ID) throws -> [ClipboardBinaryPayload] {
        try database.withConnection { db in
            let sql = """
            SELECT record_id, storage_path, original_format, file_size, created_at
            FROM clipboard_binary_payloads
            WHERE record_id = ?
            ORDER BY original_format;
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw AppError.systemFailure(code: "clipboard_payload_query_prepare")
            }
            defer { sqlite3_finalize(statement) }
            bindText(statement, 1, recordID.uuidString)

            var rows: [ClipboardBinaryPayload] = []
            var stepResult = sqlite3_step(statement)
            while stepResult == SQLITE_ROW {
                rows.append(try readPayload(statement))
                stepResult = sqlite3_step(statement)
            }
            guard stepResult == SQLITE_DONE else {
                throw AppError.systemFailure(code: "clipboard_payload_query_step")
            }
            return rows
        }
    }

    /// 删除该 recordID 的全部 payload 元数据。返回实际删除行数。
    @discardableResult
    public func deletePayloads(for recordID: ClipboardItem.ID) throws -> Int {
        try database.withConnection { db in
            var statement: OpaquePointer?
            let sql = "DELETE FROM clipboard_binary_payloads WHERE record_id = ?;"
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw AppError.systemFailure(code: "clipboard_payload_delete_prepare")
            }
            defer { sqlite3_finalize(statement) }
            bindText(statement, 1, recordID.uuidString)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw AppError.systemFailure(code: "clipboard_payload_delete_step")
            }
            return Int(sqlite3_changes(db))
        }
    }

    private func readPayload(_ statement: OpaquePointer) throws -> ClipboardBinaryPayload {
        func string(_ index: Int32) -> String? {
            guard sqlite3_column_type(statement, index) != SQLITE_NULL,
                  let cString = sqlite3_column_text(statement, index) else {
                return nil
            }
            return String(cString: cString)
        }

        guard let idString = string(0), let recordID = UUID(uuidString: idString) else {
            throw AppError.systemFailure(code: "clipboard_payload_row_record")
        }
        guard let storagePath = string(1) else {
            throw AppError.systemFailure(code: "clipboard_payload_row_path")
        }
        guard let formatRaw = string(2), let format = ClipboardPayloadFormat(rawValue: formatRaw) else {
            throw AppError.systemFailure(code: "clipboard_payload_row_format")
        }

        return ClipboardBinaryPayload(
            recordID: recordID,
            format: format,
            storagePath: storagePath,
            fileSize: Int(sqlite3_column_int64(statement, 3)),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
        )
    }

    // MARK: - Helpers

    private func updateDuplicate(db: OpaquePointer, with item: ClipboardItem) throws {
        var statement: OpaquePointer?
        let sql = """
        UPDATE clipboard_items
        SET content_type = ?,
            text_preview = ?,
            source_application_id = ?,
            is_deleted = 0,
            times_used = times_used + ?,
            updated_at = ?
        WHERE content_hash = ?;
        """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw AppError.systemFailure(code: "clipboard_dedupe_prepare")
        }
        defer { sqlite3_finalize(statement) }

        bindText(statement, 1, item.contentType.rawValue)
        bindText(statement, 2, item.textPreview)
        bindText(statement, 3, item.sourceApplicationID)
        sqlite3_bind_int(statement, 4, Int32(max(1, item.timesUsed)))
        sqlite3_bind_double(statement, 5, item.updatedAt.timeIntervalSince1970)
        bindText(statement, 6, item.contentHash)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw AppError.systemFailure(code: "clipboard_dedupe_step")
        }
        guard sqlite3_changes(db) > 0 else {
            throw AppError.systemFailure(code: "clipboard_dedupe_missing")
        }
    }

    private func fetchItem(withContentHash contentHash: String, db: OpaquePointer) throws -> ClipboardItem {
        var statement: OpaquePointer?
        let sql = """
        SELECT id, content_hash, content_type, text_preview, source_application_id,
               is_favorite, is_deleted, times_used, created_at, updated_at
        FROM clipboard_items
        WHERE content_hash = ?
        LIMIT 1;
        """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw AppError.systemFailure(code: "clipboard_dedupe_fetch_prepare")
        }
        defer { sqlite3_finalize(statement) }

        bindText(statement, 1, contentHash)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw AppError.systemFailure(code: "clipboard_dedupe_fetch_step")
        }
        return try readItem(statement)
    }

    private func bindText(_ statement: OpaquePointer, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func readItem(_ statement: OpaquePointer) throws -> ClipboardItem {
        func string(_ index: Int32) -> String? {
            guard sqlite3_column_type(statement, index) != SQLITE_NULL,
                  let cString = sqlite3_column_text(statement, index) else {
                return nil
            }
            return String(cString: cString)
        }

        guard let idString = string(0), let id = UUID(uuidString: idString) else {
            throw AppError.systemFailure(code: "clipboard_row_id")
        }
        guard let contentHash = string(1) else {
            throw AppError.systemFailure(code: "clipboard_row_hash")
        }
        let contentType = (string(2).flatMap(ClipboardContentType.init(rawValue:))) ?? .plainText

        return ClipboardItem(
            id: id,
            contentHash: contentHash,
            contentType: contentType,
            textPreview: string(3),
            sourceApplicationID: string(4),
            isFavorite: sqlite3_column_int(statement, 5) != 0,
            isDeleted: sqlite3_column_int(statement, 6) != 0,
            timesUsed: Int(sqlite3_column_int(statement, 7)),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 8)),
            updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 9))
        )
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
