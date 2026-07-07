import XCTest
import SQLite3
@testable import Omnipo

final class PermissionAuditModelsTests: XCTestCase {

    func test_permissionCategories_coverExpectedOrderAndPresentation() {
        XCTAssertEqual(
            PermissionCategory.allCases,
            [.camera, .microphone, .photos, .contacts, .calendar, .reminders, .accessibility, .fullDiskAccess]
        )

        for (expectedOrder, category) in PermissionCategory.allCases.enumerated() {
            XCTAssertFalse(category.displayName.isEmpty)
            XCTAssertFalse(category.symbolName.isEmpty)
            XCTAssertEqual(category.sortOrder, expectedOrder)
        }
    }

    func test_permissionUnavailableReasons_haveUniqueStableCodes() {
        let codes = Set(PermissionUnavailableReason.allCases.map(\.stableCode))
        XCTAssertEqual(codes.count, PermissionUnavailableReason.allCases.count)
    }

    func test_permissionUnavailableReasons_haveNonEmptyDescriptions() {
        for reason in PermissionUnavailableReason.allCases {
            XCTAssertFalse(reason.userDescription.isEmpty)
        }
    }

    func test_permissionGrantStatus_unavailableAccessors() {
        let unavailable: PermissionGrantStatus = .unavailable(reason: .permissionLimited)
        XCTAssertTrue(unavailable.isUnavailable)
        XCTAssertEqual(unavailable.unavailableReason, .permissionLimited)
        XCTAssertEqual(unavailable.displayName, "不可读取")

        XCTAssertFalse(PermissionGrantStatus.authorized.isUnavailable)
        XCTAssertNil(PermissionGrantStatus.denied.unavailableReason)
    }

    func test_appPermissionGrant_normalizesIdentifiersAndDisplayName() {
        let grant = AppPermissionGrant(
            bundleIdentifier: "  ",
            displayName: " ",
            category: .camera,
            status: .authorized,
            source: " "
        )

        XCTAssertEqual(grant.bundleIdentifier, "unknown.bundle")
        XCTAssertEqual(grant.displayName, "unknown.bundle")
        XCTAssertEqual(grant.source, "unknown")
        XCTAssertEqual(grant.id, "camera::unknown.bundle")
        XCTAssertNil(grant.iconIdentifier)
    }

    func test_appPermissionGrant_usesExplicitIDWhenProvided() {
        let grant = AppPermissionGrant(
            id: "grant-1",
            bundleIdentifier: "com.apple.Safari",
            displayName: "Safari",
            category: .microphone,
            status: .denied,
            source: "tcc"
        )

        XCTAssertEqual(grant.id, "grant-1")
    }

    func test_permissionAuditSummary_clampsCounts() {
        let summary = PermissionAuditSummary(
            totalGrantCount: -2,
            authorizedGrantCount: 8,
            unavailableGrantCount: 3
        )

        XCTAssertEqual(summary.totalGrantCount, 0)
        XCTAssertEqual(summary.authorizedGrantCount, 0)
        XCTAssertEqual(summary.unavailableGrantCount, 0)
    }

    func test_permissionAuditResult_sortsGrantsAndBuildsSummary() {
        let grants = [
            AppPermissionGrant(
                bundleIdentifier: "com.apple.Terminal",
                displayName: "Terminal",
                category: .microphone,
                status: .unavailable(reason: .permissionLimited),
                source: "tcc"
            ),
            AppPermissionGrant(
                bundleIdentifier: "com.apple.Safari",
                displayName: "Safari",
                category: .camera,
                status: .authorized,
                source: "tcc"
            ),
            AppPermissionGrant(
                bundleIdentifier: "com.apple.Notes",
                displayName: "Notes",
                category: .camera,
                status: .denied,
                source: "tcc"
            )
        ]

        let result = PermissionAuditResult(
            grants: grants,
            unavailableCategories: [.fullDiskAccess: .unsupportedOnCurrentSystem]
        )

        XCTAssertEqual(result.grants.map(\.displayName), ["Notes", "Safari", "Terminal"])
        XCTAssertEqual(result.summary.totalGrantCount, 3)
        XCTAssertEqual(result.summary.authorizedGrantCount, 1)
        XCTAssertEqual(result.summary.unavailableGrantCount, 1)
        XCTAssertFalse(result.isEmpty)
    }

    func test_permissionAuditResult_emptyStateIncludesUnavailableCategories() {
        let result = PermissionAuditResult(
            grants: [],
            unavailableCategories: [.accessibility: .databaseUnreadable]
        )

        XCTAssertFalse(result.isEmpty)
    }

    func test_permissionAuditTypes_roundTripCodable() throws {
        let result = PermissionAuditResult(
            grants: [
                AppPermissionGrant(
                    bundleIdentifier: "com.apple.Safari",
                    displayName: "Safari",
                    category: .camera,
                    status: .authorized,
                    source: "tcc",
                    lastUpdatedAt: Date(timeIntervalSince1970: 1_783_353_600)
                )
            ],
            unavailableCategories: [.microphone: .databaseUnreadable]
        )

        let data = try JSONEncoder().encode(result)
        let restored = try JSONDecoder().decode(PermissionAuditResult.self, from: data)

        XCTAssertEqual(restored, result)
    }

    func test_permissionAuditQuery_defaultsToUnfilteredState() {
        let query = PermissionAuditQuery()

        XCTAssertEqual(query.searchText, "")
        XCTAssertNil(query.category)
    }

    func test_permissionAuditAggregator_filtersByCategoryAndSearchText() async {
        let aggregator = PermissionAuditAggregator(
            providers: [
                StubPermissionCategoryProvider(
                    category: .camera,
                    result: PermissionProviderResult(
                        category: .camera,
                        grants: [
                            AppPermissionGrant(
                                bundleIdentifier: "com.example.CameraApp",
                                displayName: "Camera App",
                                category: .camera,
                                status: .authorized,
                                source: "test"
                            )
                        ]
                    )
                ),
                StubPermissionCategoryProvider(
                    category: .microphone,
                    result: PermissionProviderResult(
                        category: .microphone,
                        grants: [
                            AppPermissionGrant(
                                bundleIdentifier: "com.example.Recorder",
                                displayName: "Recorder",
                                category: .microphone,
                                status: .denied,
                                source: "test"
                            )
                        ]
                    )
                )
            ]
        )

        let result = await aggregator.audit(
            matching: PermissionAuditQuery(searchText: "camera", category: .camera)
        )

        XCTAssertEqual(result.grants.map(\.bundleIdentifier), ["com.example.CameraApp"])
        XCTAssertTrue(result.unavailableCategories.isEmpty)
    }

    func test_permissionAuditAggregator_preservesPartialUnavailableCategory() async {
        let aggregator = PermissionAuditAggregator(
            providers: [
                StubPermissionCategoryProvider(
                    category: .camera,
                    result: PermissionProviderResult(
                        category: .camera,
                        grants: [
                            AppPermissionGrant(
                                bundleIdentifier: "com.example.CameraApp",
                                displayName: "Camera App",
                                category: .camera,
                                status: .authorized,
                                source: "test"
                            )
                        ]
                    )
                ),
                StubPermissionCategoryProvider(
                    category: .fullDiskAccess,
                    result: PermissionProviderResult(
                        category: .fullDiskAccess,
                        unavailableReason: .databaseUnreadable
                    )
                )
            ]
        )

        let result = await aggregator.audit(matching: PermissionAuditQuery())

        XCTAssertEqual(result.grants.count, 1)
        XCTAssertEqual(result.unavailableCategories, [.fullDiskAccess: .databaseUnreadable])
        XCTAssertEqual(result.summary.unavailableGrantCount, 0)
    }

    func test_defaultPermissionAuditService_logsOnlySanitizedAuditContext() async {
        let logger = RecordingPermissionAuditLogger()
        let service = DefaultPermissionAuditService(
            aggregator: PermissionAuditAggregator(
                providers: [
                    StubPermissionCategoryProvider(
                        category: .camera,
                        result: PermissionProviderResult(
                            category: .camera,
                            grants: [
                                AppPermissionGrant(
                                    bundleIdentifier: "com.example.PrivateApp",
                                    displayName: "Private App",
                                    category: .camera,
                                    status: .authorized,
                                    source: "test"
                                )
                            ],
                            unavailableReason: .permissionLimited
                        )
                    )
                ]
            ),
            logger: logger
        )

        _ = await service.auditPermissions(matching: PermissionAuditQuery(category: .camera))

        let events = logger.events()
        XCTAssertEqual(events.map(\.stableCode), ["I_PERMISSION_AUDIT_STARTED", "I_PERMISSION_AUDIT_FINISHED"])
        for event in events {
            XCTAssertFalse(event.sanitizedContext.values.contains("com.example.PrivateApp"))
            XCTAssertFalse(event.sanitizedContext.values.contains("Private App"))
            XCTAssertTrue(Set(event.sanitizedContext.keys).isSubset(of: PrivacyRedaction.allowedContextKeys))
        }
    }

    func test_tccReadOnlySnapshotProvider_readsAuthValueSchemaWithoutMutatingDatabase() throws {
        let databaseURL = try makeTemporaryTCCDatabase(
            createSQL: """
            CREATE TABLE access (
                service TEXT NOT NULL,
                client TEXT NOT NULL,
                client_type INTEGER,
                auth_value INTEGER,
                last_modified INTEGER
            );
            """,
            inserts: [
                """
                INSERT INTO access (service, client, client_type, auth_value, last_modified)
                VALUES ('kTCCServiceCamera', 'com.example.CameraApp', 0, 2, 1700000000);
                """,
                """
                INSERT INTO access (service, client, client_type, auth_value, last_modified)
                VALUES ('kTCCServiceCamera', 'com.example.BlockedApp', 0, 0, 1700000001);
                """
            ]
        )
        let beforeAttributes = try FileManager.default.attributesOfItem(atPath: databaseURL.path)
        let provider = TCCReadOnlySnapshotProvider(databaseURLs: [databaseURL])

        let result = provider.snapshot(for: "kTCCServiceCamera")

        guard case .success(let entries) = result else {
            return XCTFail("Expected readable TCC snapshot")
        }
        XCTAssertEqual(entries.map(\.client), ["com.example.CameraApp", "com.example.BlockedApp"])
        XCTAssertEqual(entries.map(\.status), [.authorized, .denied])
        XCTAssertEqual(entries.first?.lastUpdatedAt, Date(timeIntervalSince1970: 1_700_000_000))

        let afterAttributes = try FileManager.default.attributesOfItem(atPath: databaseURL.path)
        XCTAssertEqual(beforeAttributes[.modificationDate] as? Date, afterAttributes[.modificationDate] as? Date)
        XCTAssertEqual(try countTCCRows(at: databaseURL), 2)
    }

    func test_tccReadOnlySnapshotProvider_readsLegacyAllowedSchema() throws {
        let databaseURL = try makeTemporaryTCCDatabase(
            createSQL: """
            CREATE TABLE access (
                service TEXT NOT NULL,
                client TEXT NOT NULL,
                allowed INTEGER
            );
            """,
            inserts: [
                """
                INSERT INTO access (service, client, allowed)
                VALUES ('kTCCServiceMicrophone', 'com.example.LegacyApp', 1);
                """
            ]
        )
        let provider = TCCReadOnlySnapshotProvider(databaseURLs: [databaseURL])

        let result = provider.snapshot(for: "kTCCServiceMicrophone")

        guard case .success(let entries) = result else {
            return XCTFail("Expected readable legacy TCC snapshot")
        }
        XCTAssertEqual(entries.map(\.status), [.authorized])
        XCTAssertEqual(entries.map(\.clientType), [0])
    }

    func test_tccReadOnlySnapshotProvider_mapsUnsupportedSchemaToUnavailableReason() throws {
        let databaseURL = try makeTemporaryTCCDatabase(
            createSQL: """
            CREATE TABLE access (
                service TEXT NOT NULL,
                client TEXT NOT NULL
            );
            """,
            inserts: []
        )
        let provider = TCCReadOnlySnapshotProvider(databaseURLs: [databaseURL])

        let result = provider.snapshot(for: "kTCCServiceCamera")

        XCTAssertEqual(result.failureReason, .unsupportedOnCurrentSystem)
    }

    func test_tccPermissionProvider_returnsUnavailableResultForSnapshotFailure() async {
        let provider = TCCPermissionCategoryProvider(
            category: .camera,
            snapshotProvider: FailingTCCSnapshotProvider(reason: .databaseUnreadable),
            applicationResolver: StubPermissionApplicationResolver()
        )

        let result = await provider.loadGrants()

        XCTAssertEqual(result.category, .camera)
        XCTAssertTrue(result.grants.isEmpty)
        XCTAssertEqual(result.unavailableReason, .databaseUnreadable)
    }

    func test_tccPermissionProvider_resolvesPathClientsWithoutLeakingPathAsIdentifier() async {
        let provider = TCCPermissionCategoryProvider(
            category: .accessibility,
            snapshotProvider: SuccessfulTCCSnapshotProvider(
                entries: [
                    TCCSnapshotEntry(
                        client: "/Applications/PrivateTool.app",
                        clientType: 1,
                        status: .authorized,
                        lastUpdatedAt: nil
                    )
                ]
            ),
            applicationResolver: SystemPermissionApplicationResolver()
        )

        let result = await provider.loadGrants()

        XCTAssertEqual(result.grants.first?.displayName, "PrivateTool.app")
        XCTAssertEqual(result.grants.first?.bundleIdentifier, "local.path.client.0")
        XCTAssertFalse(result.grants.first?.bundleIdentifier.contains("/Applications/") ?? true)
    }

    func test_systemPermissionApplicationResolver_prefersChineseLocalizedApplicationName() throws {
        let appURL = try makeTemporaryApplicationBundle(
            bundleIdentifier: "com.example.localized",
            rawDisplayName: "English Name",
            chineseDisplayName: "中文名称"
        )
        let resolver = SystemPermissionApplicationResolver()

        let identity = resolver.identity(
            forClient: appURL.path,
            clientType: 1,
            fallbackIndex: 0
        )

        XCTAssertEqual(identity.displayName, "中文名称")
        XCTAssertEqual(identity.iconIdentifier, "com.example.localized")
        XCTAssertEqual(identity.bundleIdentifier, "local.path.client.0")
    }

    func test_tccPermissionProvider_carriesBundleIdentifierForAppIconLookup() async {
        let provider = TCCPermissionCategoryProvider(
            category: .camera,
            snapshotProvider: SuccessfulTCCSnapshotProvider(
                entries: [
                    TCCSnapshotEntry(
                        client: "com.example.CameraApp",
                        clientType: 0,
                        status: .authorized,
                        lastUpdatedAt: nil
                    )
                ]
            ),
            applicationResolver: StubPermissionApplicationResolver()
        )

        let result = await provider.loadGrants()

        XCTAssertEqual(result.grants.first?.iconIdentifier, "com.example.CameraApp")
    }

    @MainActor
    func test_permissionAuditStore_loadsReadableAndUnavailableResult() async {
        let result = PermissionAuditResult(
            grants: [
                AppPermissionGrant(
                    bundleIdentifier: "com.example.CameraApp",
                    displayName: "Camera App",
                    category: .camera,
                    status: .authorized,
                    source: "test"
                )
            ],
            unavailableCategories: [.fullDiskAccess: .databaseUnreadable]
        )
        let store = PermissionAuditStore(
            service: StubPermissionAuditService(result: .success(result))
        )

        await store.loadIfNeeded()

        guard case .loaded(let loadedResult) = store.state else {
            return XCTFail("Expected loaded permission audit result")
        }
        XCTAssertEqual(loadedResult.grants.map(\.displayName), ["Camera App"])
        XCTAssertEqual(loadedResult.unavailableCategories, [.fullDiskAccess: .databaseUnreadable])
        XCTAssertEqual(loadedResult.summary.authorizedGrantCount, 1)
        XCTAssertTrue(store.isPermissionRequestPresented)

        store.dismissPermissionRequest()

        XCTAssertFalse(store.isPermissionRequestPresented)
    }

    @MainActor
    func test_permissionAuditStore_doesNotRequestAuthorizationForNonDatabaseUnavailableReasons() async {
        let result = PermissionAuditResult(
            grants: [],
            unavailableCategories: [.fullDiskAccess: .unsupportedOnCurrentSystem]
        )
        let store = PermissionAuditStore(
            service: StubPermissionAuditService(result: .success(result))
        )

        await store.loadIfNeeded()

        XCTAssertFalse(store.isPermissionRequestPresented)
    }
}

private struct StubPermissionCategoryProvider: PermissionCategoryProvider {
    let category: PermissionCategory
    let result: PermissionProviderResult

    func loadGrants() async -> PermissionProviderResult {
        result
    }
}

private struct FailingTCCSnapshotProvider: TCCSnapshotProviding {
    let reason: PermissionUnavailableReason

    func snapshot(for service: String) -> Result<[TCCSnapshotEntry], PermissionUnavailableReason> {
        .failure(reason)
    }
}

private struct SuccessfulTCCSnapshotProvider: TCCSnapshotProviding {
    let entries: [TCCSnapshotEntry]

    func snapshot(for service: String) -> Result<[TCCSnapshotEntry], PermissionUnavailableReason> {
        .success(entries)
    }
}

private struct StubPermissionApplicationResolver: PermissionApplicationResolving {
    func identity(forClient client: String, clientType: Int, fallbackIndex: Int) -> PermissionApplicationIdentity {
        PermissionApplicationIdentity(bundleIdentifier: client, displayName: client, iconIdentifier: client)
    }
}

private final class StubPermissionAuditService: PermissionAuditService, @unchecked Sendable {
    let result: Result<PermissionAuditResult, AppError>

    init(result: Result<PermissionAuditResult, AppError>) {
        self.result = result
    }

    func auditPermissions(matching query: PermissionAuditQuery) async -> Result<PermissionAuditResult, AppError> {
        result
    }
}

private extension Result where Failure == PermissionUnavailableReason {
    var failureReason: PermissionUnavailableReason? {
        if case .failure(let reason) = self {
            return reason
        }
        return nil
    }
}

private final class RecordingPermissionAuditLogger: LoggingService, @unchecked Sendable {
    private var recordedEvents: [LogEvent] = []
    private let lock = NSLock()

    func log(_ event: LogEvent) {
        lock.lock()
        defer { lock.unlock() }
        recordedEvents.append(event)
    }

    func events() -> [LogEvent] {
        lock.lock()
        defer { lock.unlock() }
        return recordedEvents
    }
}

private func makeTemporaryTCCDatabase(createSQL: String, inserts: [String]) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let databaseURL = directory.appendingPathComponent("TCC.db")

    var db: OpaquePointer?
    guard sqlite3_open_v2(databaseURL.path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let db else {
        throw AppError.systemFailure(code: "test_sqlite_open")
    }
    defer { sqlite3_close(db) }

    try executeSQL(createSQL, db: db)
    for insert in inserts {
        try executeSQL(insert, db: db)
    }
    return databaseURL
}

private func makeTemporaryApplicationBundle(
    bundleIdentifier: String,
    rawDisplayName: String,
    chineseDisplayName: String
) throws -> URL {
    let appURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: false)
        .appendingPathExtension("app")
    let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
    let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
    let chineseResourcesURL = resourcesURL.appendingPathComponent("zh-Hans.lproj", isDirectory: true)
    try FileManager.default.createDirectory(at: chineseResourcesURL, withIntermediateDirectories: true)

    let infoPlist: NSDictionary = [
        "CFBundleIdentifier": bundleIdentifier,
        "CFBundleName": rawDisplayName,
        "CFBundleDisplayName": rawDisplayName,
        "CFBundlePackageType": "APPL"
    ]
    infoPlist.write(to: contentsURL.appendingPathComponent("Info.plist"), atomically: true)

    let localizedInfo: NSDictionary = [
        "CFBundleDisplayName": chineseDisplayName,
        "CFBundleName": chineseDisplayName
    ]
    localizedInfo.write(to: chineseResourcesURL.appendingPathComponent("InfoPlist.strings"), atomically: true)

    return appURL
}

private func countTCCRows(at databaseURL: URL) throws -> Int {
    var db: OpaquePointer?
    guard sqlite3_open_v2(databaseURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
        throw AppError.systemFailure(code: "test_sqlite_open_readonly")
    }
    defer { sqlite3_close(db) }

    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM access;", -1, &statement, nil) == SQLITE_OK, let statement else {
        throw AppError.systemFailure(code: "test_sqlite_prepare_count")
    }
    defer { sqlite3_finalize(statement) }

    guard sqlite3_step(statement) == SQLITE_ROW else {
        throw AppError.systemFailure(code: "test_sqlite_step_count")
    }
    return Int(sqlite3_column_int(statement, 0))
}

private func executeSQL(_ sql: String, db: OpaquePointer) throws {
    var errorMessage: UnsafeMutablePointer<Int8>?
    guard sqlite3_exec(db, sql, nil, nil, &errorMessage) == SQLITE_OK else {
        sqlite3_free(errorMessage)
        throw AppError.systemFailure(code: "test_sqlite_exec")
    }
}
