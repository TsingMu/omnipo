import Foundation

/// 使用系统卷元数据提供启动卷容量摘要。
///
/// 服务内部以 actor 隔离共享状态,并通过 single-flight 复用同一轮读取任务;
/// 仅使用卷级公开元数据,不递归扫描目录或读取文件内容。
public actor SystemDiskUsageService: DiskUsageService {
    enum LoadError: Error, Sendable {
        case metadataNotReady
        case unsupportedVolume
    }

    struct VolumeMetadata: Sendable, Equatable {
        let volumeName: String
        let volumeIdentifier: String
        let totalBytes: Int64
        let availableBytes: Int64
    }

    private let logger: any LoggingService
    private let metadataLoader: @Sendable () async throws -> VolumeMetadata
    private let dateProvider: @Sendable () -> Date
    private let largeFileRootsProvider: @Sendable () async -> [URL]
    private let largeFileRootsRelease: @Sendable () async -> Void
    private var inFlight: (id: UUID, task: Task<DiskCapacityAvailability, Never>)?
    private var inFlightLargeFiles: (id: UUID, task: Task<LargeFileAvailability, Never>)?

    public init(logger: any LoggingService) {
        self.logger = logger
        self.metadataLoader = Self.loadSystemVolumeMetadata
        self.dateProvider = Date.init
        self.largeFileRootsProvider = { LargeFileScanner.defaultRoots() }
        self.largeFileRootsRelease = {}
    }

    /// 注入自定义大文件根 provider(例如 AuthorizedRootManager)。
    public init(
        logger: any LoggingService,
        largeFileRootsProvider: @escaping @Sendable () async -> [URL],
        largeFileRootsRelease: @escaping @Sendable () async -> Void = {}
    ) {
        self.logger = logger
        self.metadataLoader = Self.loadSystemVolumeMetadata
        self.dateProvider = Date.init
        self.largeFileRootsProvider = largeFileRootsProvider
        self.largeFileRootsRelease = largeFileRootsRelease
    }

    init(
        logger: any LoggingService,
        metadataLoader: @escaping @Sendable () async throws -> VolumeMetadata,
        dateProvider: @escaping @Sendable () -> Date = Date.init,
        largeFileRootsProvider: @escaping @Sendable () async -> [URL] = { LargeFileScanner.defaultRoots() },
        largeFileRootsRelease: @escaping @Sendable () async -> Void = {}
    ) {
        self.logger = logger
        self.metadataLoader = metadataLoader
        self.dateProvider = dateProvider
        self.largeFileRootsProvider = largeFileRootsProvider
        self.largeFileRootsRelease = largeFileRootsRelease
    }

    public func loadStartupVolumeCapacity(
        trigger: DiskCapacityLoadTrigger
    ) async -> DiskCapacityAvailability {
        if let inFlight {
            logger.log(Self.logJoinedSingleFlight(trigger: trigger))
            return await inFlight.task.value
        }

        let id = UUID()
        let metadataLoader = self.metadataLoader
        let dateProvider = self.dateProvider
        let logger = self.logger
        let task = Task<DiskCapacityAvailability, Never> {
            do {
                let metadata = try await metadataLoader()
                let snapshot = DiskCapacitySnapshot(
                    volumeName: metadata.volumeName,
                    volumeIdentifier: metadata.volumeIdentifier,
                    usedBytes: metadata.totalBytes - metadata.availableBytes,
                    availableBytes: metadata.availableBytes,
                    totalBytes: metadata.totalBytes,
                    capturedAt: dateProvider()
                )
                logger.log(Self.logLoaded(trigger: trigger))
                return .available(snapshot)
            } catch let error as LoadError {
                let reason = Self.map(loadError: error)
                logger.log(Self.logUnavailable(trigger: trigger, reason: reason))
                return .unavailable(reason: reason)
            } catch {
                let reason = Self.map(unexpectedError: error)
                logger.log(Self.logUnavailable(trigger: trigger, reason: reason))
                return .unavailable(reason: reason)
            }
        }

        inFlight = (id: id, task: task)
        let result = await task.value
        if inFlight?.id == id {
            inFlight = nil
        }
        return result
    }

    public func loadLargeFiles(
        limit: Int,
        trigger: LargeFileLoadTrigger
    ) async -> LargeFileAvailability {
        // 取消并等待旧扫描释放授权后再开始下一轮,避免同一 security scope 被并发复用。
        while let previous = inFlightLargeFiles {
            previous.task.cancel()
            _ = await previous.task.value
            if inFlightLargeFiles?.id == previous.id {
                inFlightLargeFiles = nil
            }
        }

        let id = UUID()
        let logger = self.logger
        let metadataLoader = self.metadataLoader
        let rootsProvider = self.largeFileRootsProvider
        let rootsRelease = self.largeFileRootsRelease
        let cancellation = LargeFileScanCancellationFlag()
        let task = Task<LargeFileAvailability, Never> { () -> LargeFileAvailability in
            await withTaskCancellationHandler {
                // 卷标识先用最近一次容量结果,缺失时同步读一次元数据。
                let volumeIdentifier = await Self.resolveVolumeIdentifier(
                    metadataLoader: metadataLoader
                )
                // 根目录解析(MainActor 内的 AuthorizedRootManager)。
                let roots = await rootsProvider()

                let result: LargeFileAvailability
                if roots.isEmpty || cancellation.isCancelled {
                    result = .unavailable(reason: .scanNotStarted)
                } else {
                    // 扫描是 sync I/O,放到 detached task 避免阻塞 actor；共享标志让取消可中断枚举。
                    result = await Task.detached(priority: .utility) {
                        LargeFileScanner.scan(
                            roots: roots,
                            limit: limit,
                            volumeIdentifier: volumeIdentifier,
                            isCancelled: { cancellation.isCancelled }
                        )
                    }.value
                }

                // provider 可能已经激活 security scope；所有成功、失败和取消路径都在返回前释放。
                await rootsRelease()

                if cancellation.isCancelled || Task.isCancelled {
                    logger.log(Self.logLargeFileCancelled(trigger: trigger))
                    return .unavailable(reason: .scanNotStarted)
                }
                switch result {
                case .available:
                    logger.log(Self.logLargeFileLoaded(trigger: trigger))
                case .unavailable(let reason):
                    logger.log(Self.logLargeFileUnavailable(trigger: trigger, reason: reason))
                case .idle, .loading:
                    break
                }
                return result
            } onCancel: {
                cancellation.cancel()
            }
        }

        inFlightLargeFiles = (id: id, task: task)
        let result = await task.value
        if inFlightLargeFiles?.id == id {
            inFlightLargeFiles = nil
        }
        return result
    }

    private static func resolveVolumeIdentifier(
        metadataLoader: @Sendable () async throws -> VolumeMetadata
    ) async -> String {
        if let meta = try? await metadataLoader() {
            return meta.volumeIdentifier
        }
        return "startup-volume"
    }

    private static func loadSystemVolumeMetadata() async throws -> VolumeMetadata {
        let homeURL = FileManager.default.homeDirectoryForCurrentUser

        let attributes = try FileManager.default.attributesOfFileSystem(
            forPath: homeURL.path(percentEncoded: false)
        )

        guard
            let totalNumber = attributes[FileAttributeKey.systemSize] as? NSNumber,
            let availableNumber = attributes[FileAttributeKey.systemFreeSize] as? NSNumber
        else {
            throw LoadError.metadataNotReady
        }

        let totalBytes = totalNumber.int64Value
        let availableBytes = availableNumber.int64Value
        guard totalBytes > 0, availableBytes >= 0 else {
            throw LoadError.unsupportedVolume
        }

        let volumeValues = try homeURL.resourceValues(
            forKeys: Set([
                URLResourceKey.volumeLocalizedNameKey,
                URLResourceKey.volumeNameKey
            ])
        )
        let volumeName = volumeValues.volumeLocalizedName
            ?? volumeValues.volumeName
            ?? "Startup Disk"
        let systemNumber = (attributes[FileAttributeKey.systemNumber] as? NSNumber)?.int64Value

        return VolumeMetadata(
            volumeName: volumeName,
            volumeIdentifier: stableVolumeIdentifier(
                forHomeURL: homeURL,
                systemNumber: systemNumber
            ),
            totalBytes: totalBytes,
            availableBytes: min(availableBytes, totalBytes)
        )
    }

    private static func stableVolumeIdentifier(
        forHomeURL homeURL: URL,
        systemNumber: Int64?
    ) -> String {
        if let systemNumber, systemNumber >= 0 {
            return "fs-\(systemNumber)"
        }

        let path = homeURL.standardizedFileURL.path(percentEncoded: false)
        if path == "/" || path.hasPrefix("/Users/") {
            return "startup-root"
        }
        let name = homeURL.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            return "startup-volume"
        }
        return "volume-\(name)"
    }

    static func map(loadError: LoadError) -> DiskCapacityUnavailableReason {
        switch loadError {
        case .metadataNotReady:
            return .metadataNotReady
        case .unsupportedVolume:
            return .unsupportedVolume
        }
    }

    private static func map(unexpectedError underlyingError: Error) -> DiskCapacityUnavailableReason {
        let nsError = underlyingError as NSError
        if nsError.domain == NSCocoaErrorDomain {
            return .resourceUnavailable
        }
        return .unknown
    }

    private static func logLoaded(trigger: DiskCapacityLoadTrigger) -> LogEvent {
        LogEvent(
            level: .info,
            category: .application,
            message: "disk.capacity.loaded",
            stableCode: "I_DISK_CAPACITY_LOADED",
            sanitizedContext: [
                "code": "I_DISK_CAPACITY_LOADED",
                "reason": "success",
                "trigger": trigger.rawValue
            ]
        )
    }

    private static func logUnavailable(
        trigger: DiskCapacityLoadTrigger,
        reason: DiskCapacityUnavailableReason
    ) -> LogEvent {
        let stableCode: String = switch reason {
        case .metadataNotReady: "W_DISK_METADATA_NOT_READY"
        case .resourceUnavailable: "W_DISK_RESOURCE_UNAVAILABLE"
        case .unsupportedVolume: "W_DISK_UNSUPPORTED_VOLUME"
        case .unknown: "E_DISK_UNKNOWN"
        }

        return LogEvent(
            level: reason == .unknown ? .error : .warning,
            category: .application,
            message: "disk.capacity.unavailable",
            stableCode: stableCode,
            sanitizedContext: [
                "code": stableCode,
                "reason": reason.stableCode,
                "trigger": trigger.rawValue
            ]
        )
    }

    private static func logJoinedSingleFlight(trigger: DiskCapacityLoadTrigger) -> LogEvent {
        LogEvent(
            level: .debug,
            category: .application,
            message: "disk.capacity.singleFlight.joined",
            stableCode: "I_DISK_SINGLE_FLIGHT",
            sanitizedContext: [
                "code": "I_DISK_SINGLE_FLIGHT",
                "reason": "joined-existing-load",
                "trigger": trigger.rawValue
            ]
        )
    }

    private static func logLargeFileLoaded(trigger: LargeFileLoadTrigger) -> LogEvent {
        LogEvent(
            level: .info,
            category: .application,
            message: "disk.largeFile.loaded",
            stableCode: "I_LARGE_FILE_LOADED",
            sanitizedContext: [
                "code": "I_LARGE_FILE_LOADED",
                "reason": "success",
                "trigger": trigger.rawValue
            ]
        )
    }

    private static func logLargeFileUnavailable(
        trigger: LargeFileLoadTrigger,
        reason: LargeFileUnavailableReason
    ) -> LogEvent {
        let stableCode: String = switch reason {
        case .scanNotStarted: "W_LARGE_FILE_SCAN_NOT_STARTED"
        case .resourceUnavailable: "W_LARGE_FILE_RESOURCE_UNAVAILABLE"
        case .permissionLimited: "W_LARGE_FILE_PERMISSION_LIMITED"
        case .unknown: "E_LARGE_FILE_UNKNOWN"
        }
        return LogEvent(
            level: reason == .unknown ? .error : .warning,
            category: .application,
            message: "disk.largeFile.unavailable",
            stableCode: stableCode,
            sanitizedContext: [
                "code": stableCode,
                "reason": reason.stableCode,
                "trigger": trigger.rawValue
            ]
        )
    }

    private static func logLargeFileCancelled(trigger: LargeFileLoadTrigger) -> LogEvent {
        LogEvent(
            level: .debug,
            category: .application,
            message: "disk.largeFile.cancelled",
            stableCode: "I_LARGE_FILE_CANCELLED",
            sanitizedContext: [
                "code": "I_LARGE_FILE_CANCELLED",
                "reason": "superseded",
                "trigger": trigger.rawValue
            ]
        )
    }
}

private final class LargeFileScanCancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func cancel() {
        lock.lock()
        value = true
        lock.unlock()
    }
}
