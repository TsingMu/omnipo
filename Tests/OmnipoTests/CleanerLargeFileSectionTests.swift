import XCTest
@testable import Omnipo

/// 磁盘分析页大文件区块的状态测试。
///
/// 不依赖 SwiftUI 渲染框架;通过 `LargeFileAvailability` → `LargeFileSectionModel`
/// 的纯函数映射验证 UI 将看到的展示参数,与 `CleanerLargeFileSection` 内部 switch 同源。
final class CleanerLargeFileSectionTests: XCTestCase {

    private func record(_ name: String, _ size: Int64) -> LargeFileRecord {
        LargeFileRecord(
            name: name,
            displayPath: "/vol/\(name)",
            sizeBytes: size,
            sourceVolumeIdentifier: "fs-1"
        )
    }

    func test_idle_mapsToIdlePlaceholder() {
        let model = LargeFileSectionModel.from(.idle)
        XCTAssertEqual(model.kind, .idle)
        XCTAssertTrue(model.records.isEmpty)
        XCTAssertNil(model.unavailableReason)
    }

    func test_loading_mapsToLoadingPlaceholder() {
        let model = LargeFileSectionModel.from(.loading)
        XCTAssertEqual(model.kind, .loading)
        XCTAssertTrue(model.records.isEmpty)
        XCTAssertNil(model.unavailableReason)
    }

    func test_available_mapsToRecords() {
        let availability: LargeFileAvailability = .available([record("a", 100), record("b", 50)])
        let model = LargeFileSectionModel.from(availability)
        XCTAssertEqual(model.kind, .available)
        XCTAssertEqual(model.records.count, 2)
        XCTAssertNil(model.unavailableReason)
    }

    func test_emptyAvailable_mapsToEmptyAvailable() {
        let model = LargeFileSectionModel.from(.available([]))
        XCTAssertEqual(model.kind, .emptyAvailable)
        XCTAssertTrue(model.records.isEmpty)
    }

    func test_unavailable_carriesReason() {
        let model = LargeFileSectionModel.from(.unavailable(reason: .permissionLimited))
        XCTAssertEqual(model.kind, .unavailable)
        XCTAssertEqual(model.unavailableReason, .permissionLimited)
    }

    func test_unavailable_doesNotFabricateRecords() {
        let allReasons: [LargeFileUnavailableReason] = [.scanNotStarted, .resourceUnavailable, .permissionLimited, .unknown]
        for reason in allReasons {
            let model = LargeFileSectionModel.from(.unavailable(reason: reason))
            XCTAssertEqual(model.kind, .unavailable, "reason \(reason) should map to unavailable")
            XCTAssertTrue(model.records.isEmpty, "reason \(reason) must not fabricate records")
        }
    }

    func test_available_preservesOrderFromService() {
        // 服务层已保证降序;UI 不再重排,模型原样传递。
        let availability: LargeFileAvailability = .available([record("big", 1_000), record("small", 100)])
        let model = LargeFileSectionModel.from(availability)
        XCTAssertEqual(model.records.map(\.name), ["big", "small"])
    }
}

/// 大文件区块的展示模型,纯函数从 `LargeFileAvailability` 派生。
///
/// 用于把 SwiftUI 视图决定逻辑从渲染中拆出,便于单元测试;
/// `CleanerLargeFileSection` 内部 switch 与本模型的 kind 一一对应。
public struct LargeFileSectionModel: Equatable {
    public enum Kind: Equatable {
        case idle
        case loading
        case available
        case emptyAvailable
        case unavailable
    }

    public let kind: Kind
    public let records: [LargeFileRecord]
    public let unavailableReason: LargeFileUnavailableReason?

    private init(kind: Kind, records: [LargeFileRecord], unavailableReason: LargeFileUnavailableReason?) {
        self.kind = kind
        self.records = records
        self.unavailableReason = unavailableReason
    }

    public static func from(_ availability: LargeFileAvailability) -> LargeFileSectionModel {
        switch availability {
        case .idle:
            return LargeFileSectionModel(kind: .idle, records: [], unavailableReason: nil)
        case .loading:
            return LargeFileSectionModel(kind: .loading, records: [], unavailableReason: nil)
        case .available(let records):
            let kind: Kind = records.isEmpty ? .emptyAvailable : .available
            return LargeFileSectionModel(kind: kind, records: records, unavailableReason: nil)
        case .unavailable(let reason):
            return LargeFileSectionModel(kind: .unavailable, records: [], unavailableReason: reason)
        }
    }
}
