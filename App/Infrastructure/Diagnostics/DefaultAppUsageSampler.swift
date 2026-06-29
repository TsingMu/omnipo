import AppKit
import Darwin
import Foundation

public actor DefaultAppUsageSampler: AppUsageSampling {
    public struct RunningApplication: Sendable, Equatable {
        public let pid: pid_t
        public let displayName: String
        public let bundleIdentifier: String?
        public let isAppBundle: Bool

        public init(
            pid: pid_t,
            displayName: String,
            bundleIdentifier: String? = nil,
            isAppBundle: Bool
        ) {
            self.pid = pid
            self.displayName = displayName
            self.bundleIdentifier = bundleIdentifier
            self.isAppBundle = isAppBundle
        }
    }

    public struct ProcessResourceSnapshot: Sendable, Equatable {
        public let pid: pid_t
        public let totalCPUTimeNanoseconds: UInt64
        public let residentMemoryBytes: Int64

        public init(
            pid: pid_t,
            totalCPUTimeNanoseconds: UInt64,
            residentMemoryBytes: Int64
        ) {
            self.pid = pid
            self.totalCPUTimeNanoseconds = totalCPUTimeNanoseconds
            self.residentMemoryBytes = max(0, residentMemoryBytes)
        }
    }

    public typealias RunningApplicationsProvider = @MainActor @Sendable () async -> [RunningApplication]?
    public typealias ProcessResourceProvider = @Sendable (pid_t) -> ProcessResourceSnapshot?
    public typealias DateProvider = @Sendable () -> Date

    private struct PreviousSample: Sendable {
        let cpuTimeNanoseconds: UInt64
        let capturedAt: Date
    }

    private let logger: any LoggingService
    private let runningApplicationsProvider: RunningApplicationsProvider
    private let processResourceProvider: ProcessResourceProvider
    private let nowProvider: DateProvider
    private let processorCount: Int

    private var previousByPID: [pid_t: PreviousSample] = [:]
    private var generation: UInt64 = 0

    private static let machTimebaseInfo: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    public init(logger: any LoggingService) {
        self.logger = logger
        self.runningApplicationsProvider = Self.readRunningApplications
        self.processResourceProvider = Self.readProcessResource
        self.nowProvider = { Date() }
        self.processorCount = max(1, ProcessInfo.processInfo.processorCount)
    }

    init(
        logger: any LoggingService,
        runningApplicationsProvider: @escaping RunningApplicationsProvider,
        processResourceProvider: @escaping ProcessResourceProvider,
        nowProvider: @escaping DateProvider,
        processorCount: Int
    ) {
        self.logger = logger
        self.runningApplicationsProvider = runningApplicationsProvider
        self.processResourceProvider = processResourceProvider
        self.nowProvider = nowProvider
        self.processorCount = max(1, processorCount)
    }

    public func sampleAppUsage() async -> AppUsageAvailability {
        generation &+= 1
        let capturedGeneration = generation

        guard !Task.isCancelled else {
            logger.log(Self.logCancelled())
            return .unavailable(reason: .unknown)
        }

        guard let runningApplications = await runningApplicationsProvider() else {
            logger.log(Self.logProcessListUnavailable())
            return .unavailable(reason: .processListUnavailable)
        }

        guard capturedGeneration == generation else {
            return .loading
        }

        let appCandidates = runningApplications.filter(Self.isDisplayableApplication)
        guard !appCandidates.isEmpty else {
            previousByPID.removeAll()
            return .available(AppUsageSnapshot(records: []))
        }

        let capturedAt = nowProvider()
        var records: [AppUsageRecord] = []
        var failedResourceCount = 0
        var activePIDs = Set<pid_t>()

        for app in appCandidates {
            guard !Task.isCancelled else {
                logger.log(Self.logCancelled())
                return .unavailable(reason: .unknown)
            }
            guard let resource = processResourceProvider(app.pid) else {
                failedResourceCount += 1
                continue
            }

            activePIDs.insert(app.pid)
            let cpuPercent = Self.cpuPercent(
                previous: previousByPID[app.pid],
                current: resource,
                capturedAt: capturedAt,
                processorCount: processorCount
            )
            previousByPID[app.pid] = PreviousSample(
                cpuTimeNanoseconds: resource.totalCPUTimeNanoseconds,
                capturedAt: capturedAt
            )

            records.append(AppUsageRecord(
                id: "pid-\(app.pid)",
                displayName: app.displayName,
                bundleIdentifier: app.bundleIdentifier,
                iconIdentifier: app.bundleIdentifier,
                cpuPercent: cpuPercent,
                memoryBytes: resource.residentMemoryBytes,
                networkBytesInPerSec: nil,
                networkBytesOutPerSec: nil,
                usageAmount: cpuPercent ?? 0
            ))
        }

        previousByPID = previousByPID.filter { activePIDs.contains($0.key) }

        if records.isEmpty, failedResourceCount > 0 {
            logger.log(Self.logResourceUnavailable())
            return .unavailable(reason: .resourceUsageUnavailable)
        }

        if failedResourceCount > 0 {
            logger.log(Self.logResourcePartialUnavailable())
        }

        return .available(AppUsageSnapshot(capturedAt: capturedAt, records: records))
    }

    public nonisolated static func cpuPercent(
        previous: ProcessResourceSnapshot?,
        current: ProcessResourceSnapshot,
        previousCapturedAt: Date?,
        capturedAt: Date,
        processorCount: Int
    ) -> Double? {
        guard let previous, let previousCapturedAt else { return nil }
        return cpuPercent(
            previous: PreviousSample(
                cpuTimeNanoseconds: previous.totalCPUTimeNanoseconds,
                capturedAt: previousCapturedAt
            ),
            current: current,
            capturedAt: capturedAt,
            processorCount: processorCount
        )
    }

    private static func cpuPercent(
        previous: PreviousSample?,
        current: ProcessResourceSnapshot,
        capturedAt: Date,
        processorCount: Int
    ) -> Double? {
        _ = processorCount
        guard let previous else { return nil }
        guard current.totalCPUTimeNanoseconds >= previous.cpuTimeNanoseconds else { return nil }

        let elapsedSeconds = capturedAt.timeIntervalSince(previous.capturedAt)
        guard elapsedSeconds > 0 else { return nil }

        let deltaNanoseconds = current.totalCPUTimeNanoseconds - previous.cpuTimeNanoseconds
        let deltaSeconds = Double(deltaNanoseconds) / 1_000_000_000
        let normalized = deltaSeconds / elapsedSeconds
        guard normalized.isFinite else { return nil }
        return max(0, normalized)
    }

    private static func isDisplayableApplication(_ app: RunningApplication) -> Bool {
        app.pid > 0 && app.isAppBundle && app.displayName.nonEmptyValue != nil
    }

    @MainActor
    private static func readRunningApplications() async -> [RunningApplication]? {
        NSWorkspace.shared.runningApplications.compactMap { app in
            let bundleURL = app.bundleURL
            let isAppBundle = bundleURL?.pathExtension.lowercased() == "app"
            let displayName = app.localizedName
                ?? bundleURL?.deletingPathExtension().lastPathComponent
                ?? app.bundleIdentifier
                ?? ""
            return RunningApplication(
                pid: app.processIdentifier,
                displayName: displayName,
                bundleIdentifier: app.bundleIdentifier,
                isAppBundle: isAppBundle
            )
        }
    }

    private static func readProcessResource(pid: pid_t) -> ProcessResourceSnapshot? {
        var info = proc_taskinfo()
        let expectedSize = MemoryLayout<proc_taskinfo>.stride
        let result = proc_pidinfo(
            Int32(pid),
            PROC_PIDTASKINFO,
            0,
            &info,
            Int32(expectedSize)
        )

        guard Int(result) >= expectedSize else { return nil }

        let totalCPUTimeNanoseconds = Self.addClamping(
            Self.machAbsoluteTimeToNanoseconds(info.pti_total_user),
            Self.machAbsoluteTimeToNanoseconds(info.pti_total_system)
        )

        return ProcessResourceSnapshot(
            pid: pid,
            totalCPUTimeNanoseconds: totalCPUTimeNanoseconds,
            residentMemoryBytes: Int64(clamping: info.pti_resident_size)
        )
    }

    nonisolated static func machAbsoluteTimeToNanoseconds(
        _ ticks: UInt64,
        numer: UInt32? = nil,
        denom: UInt32? = nil
    ) -> UInt64 {
        let numer = numer ?? Self.machTimebaseInfo.numer
        let denom = denom ?? Self.machTimebaseInfo.denom
        guard denom > 0 else { return ticks }

        let denominator = UInt64(denom)
        let numerator = UInt64(numer)
        let quotient = ticks / denominator
        let remainder = ticks % denominator

        let (whole, wholeOverflow) = quotient.multipliedReportingOverflow(by: numerator)
        let (partial, partialOverflow) = remainder.multipliedReportingOverflow(by: numerator)
        guard !wholeOverflow, !partialOverflow else { return UInt64.max }

        let (total, totalOverflow) = whole.addingReportingOverflow(partial / denominator)
        return totalOverflow ? UInt64.max : total
    }

    private static func addClamping(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? UInt64.max : sum
    }

    private static func logProcessListUnavailable() -> LogEvent {
        LogEvent(
            level: .warning,
            category: .application,
            message: "appUsage.processListUnavailable",
            stableCode: "W_APP_USAGE_PROCESS_LIST_UNAVAILABLE",
            sanitizedContext: ["code": "W_APP_USAGE_PROCESS_LIST_UNAVAILABLE", "reason": "process-list-unavailable"]
        )
    }

    private static func logResourceUnavailable() -> LogEvent {
        LogEvent(
            level: .warning,
            category: .application,
            message: "appUsage.resourceUnavailable",
            stableCode: "W_APP_USAGE_RESOURCE_UNAVAILABLE",
            sanitizedContext: ["code": "W_APP_USAGE_RESOURCE_UNAVAILABLE", "reason": "resource-unavailable"]
        )
    }

    private static func logResourcePartialUnavailable() -> LogEvent {
        LogEvent(
            level: .debug,
            category: .application,
            message: "appUsage.resourcePartialUnavailable",
            stableCode: "D_APP_USAGE_RESOURCE_PARTIAL_UNAVAILABLE",
            sanitizedContext: ["code": "D_APP_USAGE_RESOURCE_PARTIAL_UNAVAILABLE", "reason": "resource-partial-unavailable"]
        )
    }

    private static func logCancelled() -> LogEvent {
        LogEvent(
            level: .debug,
            category: .application,
            message: "appUsage.sampleCancelled",
            stableCode: "D_APP_USAGE_SAMPLE_CANCELLED",
            sanitizedContext: ["code": "D_APP_USAGE_SAMPLE_CANCELLED", "reason": "sample-cancelled"]
        )
    }
}

private extension String {
    var nonEmptyValue: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
