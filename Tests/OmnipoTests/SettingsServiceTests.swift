import XCTest
@testable import Omnipo

final class SettingsServiceTests: XCTestCase {

    func test_readUnsavedSetting_returnsDefaultValue() {
        let service = UserDefaultsSettingsService.testing(suiteName: "omnipo.tests.defaults.\(UUID().uuidString)")

        XCTAssertTrue(service.readBool(forKey: .launchDashboardAtStart))
        XCTAssertFalse(service.readBool(forKey: .reopenLastDestination))
        XCTAssertEqual(service.readDouble(forKey: .preferredSidebarWidth), 220)
        XCTAssertEqual(service.readString(forKey: .lastOpenedDestinationKey), "dashboard")
    }

    func test_writeAndRead_reflectsPersistedValue() {
        let service = UserDefaultsSettingsService.testing(suiteName: "omnipo.tests.defaults.\(UUID().uuidString)")

        service.write(false, forKey: .launchDashboardAtStart)
        service.write(true, forKey: .reopenLastDestination)
        service.write(280.5, forKey: .preferredSidebarWidth)
        service.write("cleaner", forKey: .lastOpenedDestinationKey)

        XCTAssertFalse(service.readBool(forKey: .launchDashboardAtStart))
        XCTAssertTrue(service.readBool(forKey: .reopenLastDestination))
        XCTAssertEqual(service.readDouble(forKey: .preferredSidebarWidth), 280.5)
        XCTAssertEqual(service.readString(forKey: .lastOpenedDestinationKey), "cleaner")
    }

    func test_remove_clearsValue() {
        let suite = "omnipo.tests.defaults.\(UUID().uuidString)"
        let service = UserDefaultsSettingsService.testing(suiteName: suite)

        service.write("launcher", forKey: .lastOpenedDestinationKey)
        service.remove(forKey: .lastOpenedDestinationKey)

        XCTAssertEqual(service.readString(forKey: .lastOpenedDestinationKey), "dashboard")
    }

    func test_resetAll_clearsAllPrefixedKeys() {
        let service = UserDefaultsSettingsService.testing(suiteName: "omnipo.tests.defaults.\(UUID().uuidString)")

        service.write("cleaner", forKey: .lastOpenedDestinationKey)
        service.write(false, forKey: .launchDashboardAtStart)
        service.resetAll()

        XCTAssertTrue(service.readBool(forKey: .launchDashboardAtStart))
        XCTAssertEqual(service.readString(forKey: .lastOpenedDestinationKey), "dashboard")
    }

    func test_writeNilString_clearsKey() {
        let service = UserDefaultsSettingsService.testing(suiteName: "omnipo.tests.defaults.\(UUID().uuidString)")

        service.write("cleaner", forKey: .lastOpenedDestinationKey)
        service.write(nil as String?, forKey: .lastOpenedDestinationKey)

        XCTAssertEqual(service.readString(forKey: .lastOpenedDestinationKey), "dashboard")
    }

    func test_isolationFromStandardDefaults() {
        UserDefaults.standard.removeObject(forKey: SettingsKey.launchDashboardAtStart.rawValue)

        let service = UserDefaultsSettingsService.testing(suiteName: "omnipo.tests.defaults.\(UUID().uuidString)")
        service.write(false, forKey: .launchDashboardAtStart)

        XCTAssertNil(UserDefaults.standard.object(forKey: SettingsKey.launchDashboardAtStart.rawValue))
    }
}
