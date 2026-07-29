import Foundation

/// 剪切板二进制内容的本地文件存储。
///
/// 负责在 `binaryPayloadsDirectory` 下读写图片、RTF、HTML 等二进制数据,
/// 不涉及数据库元数据(由 `ClipboardRepository` 维护)。
/// 文件名约定:`<recordID>.<format>`,`storagePath` 即该相对文件名。
public final class BinaryContentStore: @unchecked Sendable {
    private let rootDirectory: URL
    private let fileManager: FileManager

    public init(rootDirectory: URL, fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    /// 写入二进制数据,返回相对存储路径。目录不存在时自动创建。
    @discardableResult
    public func write(
        _ data: Data,
        for recordID: ClipboardItem.ID,
        format: ClipboardPayloadFormat
    ) throws -> String {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let relativePath = Self.fileName(for: recordID, format: format)
        try data.write(to: resolveURL(relativePath), options: .atomic)
        return relativePath
    }

    /// 按存储路径读取二进制数据。文件不存在时抛出底层错误。
    public func read(_ storagePath: String) throws -> Data {
        try Data(contentsOf: validatedURL(storagePath))
    }

    /// 返回经过相对文件名校验的 payload URL,供基础设施层流式或按需读取。
    ///
    /// 该入口不绕过 `storagePath` 的路径穿越防护,也不向 UI 暴露本地路径。
    func fileURL(for storagePath: String) throws -> URL {
        try validatedURL(storagePath)
    }

    /// 删除指定存储路径的文件。文件不存在视为成功。
    public func delete(_ storagePath: String) throws {
        let url = try validatedURL(storagePath)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    /// 删除该记录的所有 payload 文件(按 recordID 前缀匹配),单个失败不中断其余删除。
    public func deleteAll(for recordID: ClipboardItem.ID) throws {
        let contents = (try? fileManager.contentsOfDirectory(at: rootDirectory, includingPropertiesForKeys: nil)) ?? []
        let prefix = "\(recordID.uuidString)."
        for url in contents where url.lastPathComponent.hasPrefix(prefix) {
            try? fileManager.removeItem(at: url)
        }
    }

    public func resolveURL(_ storagePath: String) -> URL {
        guard Self.isSafeRelativeFileName(storagePath) else {
            return rootDirectory.appendingPathComponent(Self.invalidPathSentinel)
        }
        return rootDirectory.appendingPathComponent(storagePath, isDirectory: false)
    }

    public func exists(_ storagePath: String) -> Bool {
        guard Self.isSafeRelativeFileName(storagePath) else {
            return false
        }
        return fileManager.fileExists(atPath: resolveURL(storagePath).path)
    }

    private static func fileName(for recordID: ClipboardItem.ID, format: ClipboardPayloadFormat) -> String {
        "\(recordID.uuidString).\(format.rawValue)"
    }

    private func validatedURL(_ storagePath: String) throws -> URL {
        guard Self.isSafeRelativeFileName(storagePath) else {
            throw AppError.invalidArgument(name: "storagePath")
        }
        return rootDirectory.appendingPathComponent(storagePath, isDirectory: false)
    }

    private static let invalidPathSentinel = "__invalid_clipboard_payload_path__"

    private static func isSafeRelativeFileName(_ storagePath: String) -> Bool {
        guard !storagePath.isEmpty,
              storagePath == (storagePath as NSString).lastPathComponent,
              !storagePath.contains(".."),
              !storagePath.hasPrefix("/") else {
            return false
        }
        return true
    }
}
