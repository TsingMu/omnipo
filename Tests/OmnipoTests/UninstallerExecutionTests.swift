import XCTest
@testable import Omnipo

final class UninstallerExecutionTests: XCTestCase {
    private var tempRoots: [URL] = []

    override func tearDown() async throws {
        for root in tempRoots {
            try? FileManager.default.removeItem(at: root)
        }
        tempRoots.removeAll()
    }

    func test_applicationOnlyPlan_containsOnlyApplicationBundle() async throws {
        let app = sampleApplication()
        let service = DefaultUninstallerService(
            associatedFileRoots: []
        )

        let result = await service.buildPlan(for: app, mode: .removeApplicationOnly)
        let plan = try result.get()

        XCTAssertEqual(plan.mode, .removeApplicationOnly)
        XCTAssertEqual(plan.items.map(\.category), [.applicationBundle])
        XCTAssertEqual(plan.selectedItemIDs.count, 1)
        XCTAssertEqual(plan.selectedTotalSizeBytes, app.bundleSizeBytes)
    }

    func test_fullRemovalPlan_includesAssociatedFiles() async throws {
        let root = try makeRoot(name: "full")
        let cacheRoot = try makeCategoryRoot(root: root, name: "Caches")
        try writeFile(at: cacheRoot.appendingPathComponent("com.example.sample"), path: "blob", size: 12)
        let app = sampleApplication()
        let service = DefaultUninstallerService(
            associatedFileRoots: [AssociatedFileScanRoot(category: .cache, url: cacheRoot)]
        )

        let result = await service.buildPlan(for: app, mode: .removeApplicationAndAssociatedFiles)
        let plan = try result.get()

        XCTAssertEqual(plan.items.map(\.category), [.applicationBundle, .cache])
        XCTAssertTrue(plan.selectedItemIDs.contains { $0.contains("com.example.sample") })
        XCTAssertEqual(plan.selectedTotalSizeBytes, app.bundleSizeBytes + 12)
    }

    func test_planSelection_recalculatesSizeAndRisk() async throws {
        let app = sampleApplication()
        let bundle = DefaultUninstallerService.applicationBundleItem(for: app)
        let support = AppAssociatedFile(
            id: "support",
            category: .applicationSupport,
            displayName: "Support",
            url: URL(fileURLWithPath: "/tmp/Support"),
            sizeBytes: 30,
            ownershipConfidence: .medium,
            riskLevel: .medium
        )
        let plan = AppUninstallPlan(
            application: app,
            mode: .removeApplicationAndAssociatedFiles,
            items: [bundle, support]
        )

        let selected = plan.selecting(itemIDs: ["support"])

        XCTAssertEqual(selected.selectedItemIDs, ["support"])
        XCTAssertEqual(selected.selectedTotalSizeBytes, 30)
        XCTAssertEqual(selected.riskSummary.mediumRiskCount, 1)
    }

    func test_runningApplicationBundleIsSkippedInPlanAndExecution() async throws {
        let app = sampleApplication(isRunning: true)
        let service = DefaultUninstallerService(
            deletionExecutor: RecordingDeletionExecutor(),
            associatedFileRoots: []
        )

        let plan = try await service.buildPlan(for: app, mode: .removeApplicationOnly).get()
        XCTAssertEqual(plan.items.first?.unavailableReason, .runningApplication)
        XCTAssertTrue(plan.selectedItems.isEmpty)

        let result = try await service.execute(plan: plan).get()
        XCTAssertTrue(result.itemResults.isEmpty)
    }

    func test_systemProtectedBundleIsNotDefaultSelected() {
        let item = DefaultUninstallerService.applicationBundleItem(
            for: sampleApplication(isSystemProtected: true)
        )

        XCTAssertEqual(item.unavailableReason, .systemProtected)
        XCTAssertFalse(item.isUserSelectable)
        XCTAssertFalse(item.isDefaultSelected)
    }

    func test_sandboxTrashExecutor_trashesOnlyAuthorizedItems() async throws {
        let root = try makeRoot(name: "trash")
        let allowedURL = root.appendingPathComponent("allowed")
        let outsideURL = URL(fileURLWithPath: "/tmp/outside-\(UUID().uuidString)")
        try Data(count: 1).write(to: allowedURL)
        try Data(count: 1).write(to: outsideURL)
        defer { try? FileManager.default.removeItem(at: outsideURL) }

        let trashed = URLRecorder()
        let executor = SandboxTrashDeletionExecutor(
            authorizedRoots: [root],
            trashHandler: { url in
                trashed.append(url)
                return url
            }
        )
        let allowed = associatedFile(id: "allowed", url: allowedURL)
        let outside = associatedFile(id: "outside", url: outsideURL)

        let results = await executor.delete([allowed, outside])

        XCTAssertEqual(trashed.values, [allowedURL])
        XCTAssertEqual(results.map(\.status), [.succeeded, .insufficientPermission])
    }

    func test_sandboxTrashExecutor_doesNotPermanentlyDeleteOnTrashFailure() async throws {
        let root = try makeRoot(name: "trash-failure")
        let url = root.appendingPathComponent("file")
        try Data(count: 1).write(to: url)
        let executor = SandboxTrashDeletionExecutor(
            authorizedRoots: [root],
            trashHandler: { _ in throw AppError.systemFailure(code: "boom") }
        )

        let results = await executor.delete([associatedFile(id: "file", url: url)])

        XCTAssertEqual(results.first?.status, .failed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func test_finderAutomationExecutor_defaultCanDeleteEligibleItems() async {
        let executor = FinderAutomationDeletionExecutor()
        let item = associatedFile(id: "app", url: URL(fileURLWithPath: "/Applications/Test.app"))

        let canDelete = await executor.canDelete(item)

        XCTAssertTrue(canDelete)
    }

    func test_finderAutomationExecutor_escapesAppleScriptPathLiterals() {
        let url = URL(fileURLWithPath: "/Applications/Test\"; delete POSIX file \"/tmp/no.app")

        let script = FinderAutomationDeletionExecutor.finderDeleteScript(for: [url])

        XCTAssertTrue(script.contains("tell application id \"com.apple.finder\""))
        XCTAssertTrue(script.contains("POSIX file \"/Applications/Test\\\"; delete POSIX file \\\"/tmp/no.app\""))
        XCTAssertFalse(script.contains("POSIX file \"/Applications/Test\"; delete"))
    }

    func test_finderAutomationExecutor_usesStructuredURLs() async {
        let url = URL(fileURLWithPath: "/Applications/Test; rm -rf no.app")
        let receivedURLs = URLRecorder()
        let executor = FinderAutomationDeletionExecutor(
            automationDeleteHandler: { urls in
                receivedURLs.set(urls)
                return Set(urls)
            }
        )
        let item = associatedFile(id: "dangerous", url: url)

        let results = await executor.delete([item])

        XCTAssertEqual(receivedURLs.values, [url])
        XCTAssertEqual(results.first?.status, .succeeded)
    }

    func test_serviceExecute_reportsPartialFailureFromExecutor() async throws {
        let app = sampleApplication()
        let bundle = DefaultUninstallerService.applicationBundleItem(for: app)
        let failingCache = AppAssociatedFile(
            id: "failing-cache",
            category: .cache,
            displayName: "Failing Cache",
            url: URL(fileURLWithPath: "/tmp/failing-cache"),
            ownershipConfidence: .high,
            riskLevel: .low
        )
        let plan = AppUninstallPlan(
            application: app,
            mode: .removeApplicationAndAssociatedFiles,
            items: [bundle, failingCache],
            selectedItemIDs: [bundle.id, failingCache.id]
        )
        let executor = RecordingDeletionExecutor(statuses: [
            bundle.id: .succeeded,
            failingCache.id: .failed
        ])
        let service = DefaultUninstallerService(
            deletionExecutor: executor,
            associatedFileRoots: []
        )

        let result = try await service.execute(plan: plan).get()

        XCTAssertEqual(result.succeededCount, 1)
        XCTAssertEqual(result.failedCount, 1)
        XCTAssertTrue(result.isPartialFailure)
    }

    private func sampleApplication(
        isSystemProtected: Bool = false,
        isRunning: Bool = false
    ) -> InstalledApplication {
        InstalledApplication(
            bundleIdentifier: "com.example.sample",
            displayName: "Sample",
            bundleURL: URL(fileURLWithPath: "/Applications/Sample.app", isDirectory: true),
            executableURL: URL(fileURLWithPath: "/Applications/Sample.app/Contents/MacOS/Sample"),
            bundleSizeBytes: 100,
            source: .applications,
            isSystemProtected: isSystemProtected,
            isRunning: isRunning
        )
    }

    private func associatedFile(id: String, url: URL) -> AppAssociatedFile {
        AppAssociatedFile(
            id: id,
            category: .cache,
            displayName: id,
            url: url,
            sizeBytes: 1,
            ownershipConfidence: .high,
            riskLevel: .low
        )
    }

    private func makeRoot(name: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("UninstallerExecution-\(UUID().uuidString)-\(name)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        tempRoots.append(url)
        return url
    }

    private func makeCategoryRoot(root: URL, name: String) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeFile(at root: URL, path: String, size: Int) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: size).write(to: url)
    }
}

private final class RecordingDeletionExecutor: DeletionExecutor, @unchecked Sendable {
    let kind: DeletionExecutorKind = .sandboxTrash
    private let statuses: [String: UninstallExecutionItemStatus]

    init(statuses: [String: UninstallExecutionItemStatus] = [:]) {
        self.statuses = statuses
    }

    func canDelete(_ item: AppAssociatedFile) async -> Bool {
        item.unavailableReason == nil
    }

    func delete(_ items: [AppAssociatedFile]) async -> [UninstallExecutionItemResult] {
        items.map { item in
            UninstallExecutionItemResult(
                item: item,
                status: statuses[item.id] ?? .succeeded
            )
        }
    }

    func cancel() async {}
}

private final class URLRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [URL] = []

    var values: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return storedValues
    }

    func append(_ url: URL) {
        lock.lock()
        storedValues.append(url)
        lock.unlock()
    }

    func set(_ urls: [URL]) {
        lock.lock()
        storedValues = urls
        lock.unlock()
    }
}
