import XCTest
@testable import Omnipo

final class SettingsServiceTests: XCTestCase {

    func test_readUnsavedSetting_returnsDefaultValue() {
        let service = UserDefaultsSettingsService.testing(suiteName: "omnipo.tests.defaults.\(UUID().uuidString)")

        XCTAssertTrue(service.readBool(forKey: .launchDashboardAtStart))
        XCTAssertFalse(service.readBool(forKey: .reopenLastDestination))
        XCTAssertEqual(service.readString(forKey: .lastOpenedDestinationKey), "dashboard")
    }

    func test_writeAndRead_reflectsPersistedValue() {
        let service = UserDefaultsSettingsService.testing(suiteName: "omnipo.tests.defaults.\(UUID().uuidString)")

        service.write(false, forKey: .launchDashboardAtStart)
        service.write(true, forKey: .reopenLastDestination)
        service.write("cleaner", forKey: .lastOpenedDestinationKey)

        XCTAssertFalse(service.readBool(forKey: .launchDashboardAtStart))
        XCTAssertTrue(service.readBool(forKey: .reopenLastDestination))
        XCTAssertEqual(service.readString(forKey: .lastOpenedDestinationKey), "cleaner")
    }

    func test_writeAndRead_arbitraryDoubleKey() {
        let arbitraryKey = SettingsKey(
            "omnipo.tests.arbitrary.\(UUID().uuidString)",
            default: .double(0)
        )
        let service = UserDefaultsSettingsService.testing(suiteName: "omnipo.tests.defaults.\(UUID().uuidString)")

        service.write(280.5, forKey: arbitraryKey)
        XCTAssertEqual(service.readDouble(forKey: arbitraryKey), 280.5)
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

    // MARK: - Launcher Shortcut

    func test_readLauncherShortcut_returnsNilWhenUnset() {
        let service = UserDefaultsSettingsService.testing(suiteName: "omnipo.tests.defaults.\(UUID().uuidString)")
        XCTAssertNil(service.readLauncherShortcut())
    }

    func test_writeAndRead_launcherShortcut_roundTrips() {
        let service = UserDefaultsSettingsService.testing(suiteName: "omnipo.tests.defaults.\(UUID().uuidString)")
        let shortcut = KeyboardShortcut(keyCode: 11, modifierFlags: [.command, .shift])
        service.writeLauncherShortcut(shortcut)

        let restored = service.readLauncherShortcut()
        XCTAssertEqual(restored, shortcut)
    }

    func test_readLauncherShortcut_returnsNilForCorruptedModifiers() {
        let service = UserDefaultsSettingsService.testing(suiteName: "omnipo.tests.defaults.\(UUID().uuidString)")
        service.write(Double(11), forKey: .launcherShortcutKeyCode)
        service.write(Double(0), forKey: .launcherShortcutModifiers)

        XCTAssertNil(service.readLauncherShortcut(), "modifiers=0 should not produce a valid shortcut")
    }

    func test_clearLauncherShortcut_resetsToDefault() {
        let service = UserDefaultsSettingsService.testing(suiteName: "omnipo.tests.defaults.\(UUID().uuidString)")
        service.writeLauncherShortcut(KeyboardShortcut(keyCode: 11, modifierFlags: .command))
        service.clearLauncherShortcut()

        XCTAssertNil(service.readLauncherShortcut())
    }
}
