import XCTest
@testable import Omnipo

final class ClipboardModelTests: XCTestCase {

    func test_clipboardContentType_roundTripsRawValues() throws {
        for type in ClipboardContentType.allCases {
            let data = try JSONEncoder().encode(type)
            let restored = try JSONDecoder().decode(ClipboardContentType.self, from: data)
            XCTAssertEqual(restored, type)
            XCTAssertFalse(type.displayName.isEmpty)
        }
    }

    func test_clipboardItem_defaultsAreConservative() {
        let item = ClipboardItem(contentHash: "hash", contentType: .plainText)

        XCTAssertFalse(item.isFavorite)
        XCTAssertFalse(item.isDeleted)
        XCTAssertEqual(item.timesUsed, 1)
        XCTAssertNil(item.textPreview)
        XCTAssertNil(item.sourceApplicationID)
    }

    func test_clipboardItem_roundTripsCodableFields() throws {
        let now = Date(timeIntervalSince1970: 1_772_515_200)
        let item = ClipboardItem(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            contentHash: "abc123",
            contentType: .html,
            textPreview: "<p>Hello</p>",
            sourceApplicationID: "com.example.Source",
            isFavorite: true,
            isDeleted: false,
            timesUsed: 3,
            createdAt: now,
            updatedAt: now.addingTimeInterval(10)
        )

        let data = try JSONEncoder().encode(item)
        let restored = try JSONDecoder().decode(ClipboardItem.self, from: data)

        XCTAssertEqual(restored, item)
    }

    func test_clipboardItem_clampsNegativeTimesUsed() {
        let item = ClipboardItem(
            contentHash: "hash",
            contentType: .image,
            timesUsed: -3
        )

        XCTAssertEqual(item.timesUsed, 0)
    }

    func test_clipboardQuery_clampsPagingInputs() {
        let query = ClipboardQuery(limit: -1, offset: -10)

        XCTAssertEqual(query.limit, 1)
        XCTAssertEqual(query.offset, 0)
    }
}
