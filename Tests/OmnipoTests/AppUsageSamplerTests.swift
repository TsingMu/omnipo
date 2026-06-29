import Foundation
import XCTest
@testable import Omnipo

@MainActor
final class AppUsageSamplerTests: XCTestCase {

    func test_secondSampleReturnsCPUAndMemorySortedByUsage() async {
        let appProvider = AppProvider(apps: [
            app(pid: 101, name: "Notes", bundleIdentifier: "com.apple.Notes"),
            app(pid: 102, name: "Xcode", bundleIdentifier: "com.apple.dt.Xcode")
        ])
        let resources = ResourceProvider(samples: [
            101: [
                resource(pid: 101, cpu: 100_000_000, memory: 400),
                resource(pid: 101, cpu: 200_000_000, memory: 500)
            ],
            102: [
                resource(pid: 102, cpu: 100_000_000, memory: 800),
                resource(pid: 102, cpu: 500_000_000, memory: 900)
            ]
        ])
        let clock = Clock(dates: [
            Date(timeIntervalSince1970: 0),
            Date(timeIntervalSince1970: 1)
        ])
        let sampler = makeSampler(
            appProvider: appProvider,
            resources: resources,
            clock: clock,
            processorCount: 1
        )

        _ = await sampler.sampleAppUsage()
        let availability = await sampler.sampleAppUsage()

        XCTAssertEqual(availability.records.map(\.displayName), ["Xcode", "Notes"])
        XCTAssertEqual(availability.records.first?.cpuPercent ?? -1, 0.4, accuracy: 1e-9)
        XCTAssertEqual(availability.records.first?.memoryBytes, 900)
        XCTAssertNil(availability.records.first?.networkBytesInPerSec)
        XCTAssertNil(availability.records.first?.networkBytesOutPerSec)
    }

    func test_emptyAppListReturnsEmptyAvailableSnapshot() async {
        let sampler = makeSampler(appProvider: AppProvider(apps: []))

        let availability = await sampler.sampleAppUsage()

        XCTAssertTrue(availability.records.isEmpty)
        XCTAssertNil(availability.unavailableReason)
    }

    func test_singleAppResourceFailureDoesNotDropOtherApps() async {
        let appProvider = AppProvider(apps: [
            app(pid: 201, name: "Safari", bundleIdentifier: "com.apple.Safari"),
            app(pid: 202, name: "Preview", bundleIdentifier: "com.apple.Preview")
        ])
        let resources = ResourceProvider(samples: [
            201: [resource(pid: 201, cpu: 10, memory: 100)]
        ])
        let sampler = makeSampler(appProvider: appProvider, resources: resources)

        let availability = await sampler.sampleAppUsage()

        XCTAssertEqual(availability.records.map(\.displayName), ["Safari"])
        XCTAssertNil(availability.unavailableReason)
    }

    func test_appsWithSameBundleIdentifierKeepDistinctProcessIDs() async {
        let appProvider = AppProvider(apps: [
            app(pid: 211, name: "Helper", bundleIdentifier: "com.example.Helper"),
            app(pid: 212, name: "Helper", bundleIdentifier: "com.example.Helper")
        ])
        let resources = ResourceProvider(samples: [
            211: [resource(pid: 211, cpu: 10, memory: 100)],
            212: [resource(pid: 212, cpu: 20, memory: 200)]
        ])
        let sampler = makeSampler(appProvider: appProvider, resources: resources)

        let availability = await sampler.sampleAppUsage()

        XCTAssertEqual(Set(availability.records.map(\.id)), ["pid-211", "pid-212"])
        XCTAssertEqual(availability.records.count, 2)
    }

    func test_allResourceFailuresReturnUnavailable() async {
        let appProvider = AppProvider(apps: [
            app(pid: 301, name: "Safari", bundleIdentifier: "com.apple.Safari")
        ])
        let sampler = makeSampler(appProvider: appProvider, resources: ResourceProvider(samples: [:]))

        let availability = await sampler.sampleAppUsage()

        XCTAssertEqual(availability.unavailableReason, .resourceUsageUnavailable)
        XCTAssertTrue(availability.records.isEmpty)
    }

    func test_processListFailureReturnsUnavailable() async {
        let sampler = makeSampler(appProvider: AppProvider(apps: nil))

        let availability = await sampler.sampleAppUsage()

        XCTAssertEqual(availability.unavailableReason, .processListUnavailable)
    }

    func test_nonAppBundlesAreIgnored() async {
        let appProvider = AppProvider(apps: [
            app(pid: 401, name: "launchd", bundleIdentifier: nil, isAppBundle: false)
        ])
        let sampler = makeSampler(appProvider: appProvider)

        let availability = await sampler.sampleAppUsage()

        XCTAssertTrue(availability.records.isEmpty)
        XCTAssertNil(availability.unavailableReason)
    }

    func test_overlappingSamplesDoNotReturnStaleGeneration() async {
        let appProvider = DelayedAppProvider(apps: [
            app(pid: 501, name: "Safari", bundleIdentifier: "com.apple.Safari")
        ])
        let resources = ResourceProvider(samples: [
            501: [
                resource(pid: 501, cpu: 10, memory: 100),
                resource(pid: 501, cpu: 20, memory: 100)
            ]
        ])
        let sampler = DefaultAppUsageSampler(
            logger: RecordingLogger(),
            runningApplicationsProvider: { await appProvider.apps() },
            processResourceProvider: { resources.resource(for: $0) },
            nowProvider: { Date() },
            processorCount: 1
        )

        let first = Task { await sampler.sampleAppUsage() }
        try? await Task.sleep(nanoseconds: 20_000_000)
        let second = Task { await sampler.sampleAppUsage() }

        let firstAvailability = await first.value
        let secondAvailability = await second.value

        XCTAssertEqual(firstAvailability, .loading)
        XCTAssertFalse(secondAvailability.records.isEmpty)
    }

    func test_cpuPercentUsesActivityMonitorSingleCoreScale() {
        let previous = DefaultAppUsageSampler.ProcessResourceSnapshot(
            pid: 1,
            totalCPUTimeNanoseconds: 1_000_000_000,
            residentMemoryBytes: 0
        )
        let current = DefaultAppUsageSampler.ProcessResourceSnapshot(
            pid: 1,
            totalCPUTimeNanoseconds: 3_000_000_000,
            residentMemoryBytes: 0
        )

        let percent = DefaultAppUsageSampler.cpuPercent(
            previous: previous,
            current: current,
            previousCapturedAt: Date(timeIntervalSince1970: 0),
            capturedAt: Date(timeIntervalSince1970: 1),
            processorCount: 4
        )

        XCTAssertEqual(percent ?? -1, 2.0, accuracy: 1e-9)
    }

    func test_machAbsoluteTimeConversionUsesTimebase() {
        let nanoseconds = DefaultAppUsageSampler.machAbsoluteTimeToNanoseconds(
            2_400,
            numer: 125,
            denom: 3
        )

        XCTAssertEqual(nanoseconds, 100_000)
    }

    private func makeSampler(
        appProvider: AppProvider,
        resources: ResourceProvider = ResourceProvider(samples: [:]),
        clock: Clock = Clock(dates: [Date()]),
        processorCount: Int = 1
    ) -> DefaultAppUsageSampler {
        DefaultAppUsageSampler(
            logger: RecordingLogger(),
            runningApplicationsProvider: { await appProvider.apps() },
            processResourceProvider: { resources.resource(for: $0) },
            nowProvider: { clock.now() },
            processorCount: processorCount
        )
    }
}

private func app(
    pid: pid_t,
    name: String,
    bundleIdentifier: String?,
    isAppBundle: Bool = true
) -> DefaultAppUsageSampler.RunningApplication {
    DefaultAppUsageSampler.RunningApplication(
        pid: pid,
        displayName: name,
        bundleIdentifier: bundleIdentifier,
        isAppBundle: isAppBundle
    )
}

private func resource(
    pid: pid_t,
    cpu: UInt64,
    memory: Int64
) -> DefaultAppUsageSampler.ProcessResourceSnapshot {
    DefaultAppUsageSampler.ProcessResourceSnapshot(
        pid: pid,
        totalCPUTimeNanoseconds: cpu,
        residentMemoryBytes: memory
    )
}

@MainActor
private final class AppProvider {
    private let appsValue: [DefaultAppUsageSampler.RunningApplication]?

    init(apps: [DefaultAppUsageSampler.RunningApplication]?) {
        self.appsValue = apps
    }

    func apps() async -> [DefaultAppUsageSampler.RunningApplication]? {
        appsValue
    }
}

@MainActor
private final class DelayedAppProvider {
    private let appsValue: [DefaultAppUsageSampler.RunningApplication]
    private var callCount = 0

    init(apps: [DefaultAppUsageSampler.RunningApplication]) {
        self.appsValue = apps
    }

    func apps() async -> [DefaultAppUsageSampler.RunningApplication]? {
        callCount += 1
        if callCount == 1 {
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
        return appsValue
    }
}

private final class ResourceProvider: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [pid_t: [DefaultAppUsageSampler.ProcessResourceSnapshot]]

    init(samples: [pid_t: [DefaultAppUsageSampler.ProcessResourceSnapshot]]) {
        self.samples = samples
    }

    func resource(for pid: pid_t) -> DefaultAppUsageSampler.ProcessResourceSnapshot? {
        lock.withLock {
            guard var queue = samples[pid], !queue.isEmpty else { return nil }
            let first = queue.removeFirst()
            samples[pid] = queue
            return first
        }
    }
}

private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var dates: [Date]

    init(dates: [Date]) {
        self.dates = dates
    }

    func now() -> Date {
        lock.withLock {
            if dates.count > 1 {
                return dates.removeFirst()
            }
            return dates.first ?? Date()
        }
    }
}

private final class RecordingLogger: LoggingService {
    func log(_ event: LogEvent) {}
}
