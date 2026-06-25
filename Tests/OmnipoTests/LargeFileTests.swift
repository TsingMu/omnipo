import XCTest
@testable import Omnipo

final class LargeFileTests: XCTestCase {

    private func record(
        _ name: String,
        _ size: Int64,
        path: String = "/vol/file",
        volume: String = "Macintosh HD"
    ) -> LargeFileRecord {
        LargeFileRecord(
            name: name,
            displayPath: path,
            sizeBytes: size,
            sourceVolumeIdentifier: volume
        )
    }

    // MARK: - LargeFileRecord

    func test_record_clampsNegativeSizeToZero() {
        let r = record("a", -100)
        XCTAssertEqual(r.sizeBytes, 0)
    }

    func test_record_preservesOptionalLastModified() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let withDate = LargeFileRecord(
            name: "a",
            displayPath: "/x",
            sizeBytes: 10,
            lastModifiedAt: date,
            sourceVolumeIdentifier: "v"
        )
        let withoutDate = record("a", 10)
        XCTAssertEqual(withDate.lastModifiedAt, date)
        XCTAssertNil(withoutDate.lastModifiedAt)
    }

    func test_record_hasStableIdPerInstance() {
        let a = record("a", 1)
        let b = record("a", 1)
        XCTAssertEqual(a.id, a.id)
        XCTAssertNotEqual(a.id, b.id, "id defaults to a fresh UUID per record")
    }

    // MARK: - LargeFileUnavailableReason

    func test_unavailableReasons_haveUniqueStableCodes() {
        let codes = Set(LargeFileUnavailableReason.allCases.map(\.stableCode))
        XCTAssertEqual(codes.count, LargeFileUnavailableReason.allCases.count)
    }

    func test_unavailableReasons_haveNonEmptyUserDescriptions() {
        for reason in LargeFileUnavailableReason.allCases {
            XCTAssertFalse(reason.userDescription.isEmpty)
        }
    }

    // MARK: - LargeFileAvailability

    func test_availability_idleAccessorsReturnEmpty() {
        XCTAssertTrue(LargeFileAvailability.idle.records.isEmpty)
        XCTAssertNil(LargeFileAvailability.idle.unavailableReason)
        XCTAssertFalse(LargeFileAvailability.idle.isLoading)
    }

    func test_availability_loadingIsLoading() {
        XCTAssertTrue(LargeFileAvailability.loading.isLoading)
    }

    func test_availability_availableExposesRecords() {
        let records = [record("a", 100), record("b", 50)]
        let state: LargeFileAvailability = .available(records)
        XCTAssertEqual(state.records.count, 2)
        XCTAssertNil(state.unavailableReason)
        XCTAssertFalse(state.isLoading)
    }

    func test_availability_unavailableExposesReason() {
        let state: LargeFileAvailability = .unavailable(reason: .permissionLimited)
        XCTAssertEqual(state.unavailableReason, .permissionLimited)
        XCTAssertTrue(state.records.isEmpty)
    }

    func test_sortedBySizeDescending_sortsBySizeThenName() {
        let records = [
            record("small", 100),
            record("big", 1_000),
            record("medium", 500),
            record("alpha-tie", 500)
        ]
        let state: LargeFileAvailability = .available(records).sortedBySizeDescending()

        XCTAssertEqual(state.records.map(\.name), ["big", "alpha-tie", "medium", "small"])
    }

    func test_sortedBySizeDescending_preservesNonAvailableState() {
        let idle = LargeFileAvailability.idle.sortedBySizeDescending()
        XCTAssertEqual(idle, .idle)

        let unavailable = LargeFileAvailability.unavailable(reason: .unknown).sortedBySizeDescending()
        XCTAssertEqual(unavailable, .unavailable(reason: .unknown))
    }

    func test_limited_truncatesAvailableRecords() {
        let records = (0..<10).map { record("f\($0)", Int64($0)) }
        let state: LargeFileAvailability = .available(records).limited(to: 3)
        XCTAssertEqual(state.records.count, 3)
    }

    func test_limited_returnsAllWhenUnderLimit() {
        let records = [record("a", 1), record("b", 2)]
        let state: LargeFileAvailability = .available(records).limited(to: 5)
        XCTAssertEqual(state.records.count, 2)
    }

    func test_limited_withZeroOrNegativeReturnsEmptyAvailable() {
        let records = [record("a", 1)]
        let state: LargeFileAvailability = .available(records).limited(to: 0)
        XCTAssertTrue(state.records.isEmpty)
    }

    func test_limited_preservesNonAvailableState() {
        let idle = LargeFileAvailability.idle.limited(to: 5)
        XCTAssertEqual(idle, .idle)
    }
}
