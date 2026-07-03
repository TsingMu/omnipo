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

    func test_launcherFileDirectoryBookmarks_roundTripAndClear() {
        let service = UserDefaultsSettingsService.testing(suiteName: "omnipo.tests.defaults.\(UUID().uuidString)")
        let bookmarks = [
            Data([0x01, 0x02, 0x03]),
            Data([0x04, 0x05, 0x06])
        ]

        service.writeLauncherFileDirectoryBookmarks(bookmarks)
        XCTAssertEqual(service.readLauncherFileDirectoryBookmarks(), bookmarks)

        service.writeLauncherFileDirectoryBookmarks([])
        XCTAssertTrue(service.readLauncherFileDirectoryBookmarks().isEmpty)
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

    // MARK: - System Monitor

    func test_systemMonitorInterval_roundTripsAndClampsInvalidValue() {
        let service = UserDefaultsSettingsService.testing(suiteName: "omnipo.tests.defaults.\(UUID().uuidString)")

        service.writeSystemMonitorIntervalSeconds(12)
        XCTAssertEqual(service.readSystemMonitorIntervalSeconds(), 12)

        service.writeSystemMonitorIntervalSeconds(-1)
        XCTAssertEqual(service.readSystemMonitorIntervalSeconds(), SystemMonitorInterval.defaultSeconds)
    }

    // MARK: - Clipboard

    func test_clipboardSettings_defaultToDisabledAndUnacknowledged() {
        let service = UserDefaultsSettingsService.testing(suiteName: "omnipo.tests.defaults.\(UUID().uuidString)")

        XCTAssertFalse(service.readBool(forKey: .clipboardIsEnabled))
        XCTAssertFalse(service.readBool(forKey: .clipboardHasAcknowledgedLocalStorageNotice))
        XCTAssertFalse(service.readBool(forKey: .clipboardAutoPaste))
        XCTAssertEqual(service.readClipboardMaxRecords(), ClipboardSettingsDefaults.maxRecords)
        XCTAssertEqual(service.readClipboardRetentionDays(), ClipboardSettingsDefaults.retentionDays)
        XCTAssertEqual(service.readClipboardMaxStorageMB(), ClipboardSettingsDefaults.maxStorageMB)
    }

    func test_clipboardSettings_roundTripBooleans() {
        let service = UserDefaultsSettingsService.testing(suiteName: "omnipo.tests.defaults.\(UUID().uuidString)")

        service.write(true, forKey: .clipboardIsEnabled)
        service.write(true, forKey: .clipboardHasAcknowledgedLocalStorageNotice)
        service.write(true, forKey: .clipboardAutoPaste)

        XCTAssertTrue(service.readBool(forKey: .clipboardIsEnabled))
        XCTAssertTrue(service.readBool(forKey: .clipboardHasAcknowledgedLocalStorageNotice))
        XCTAssertTrue(service.readBool(forKey: .clipboardAutoPaste))
    }

    func test_clipboardSettings_clampRetentionValues() {
        let service = UserDefaultsSettingsService.testing(suiteName: "omnipo.tests.defaults.\(UUID().uuidString)")

        service.writeClipboardMaxRecords(20_000)
        service.writeClipboardRetentionDays(0)
        service.writeClipboardMaxStorageMB(1)

        XCTAssertEqual(service.readClipboardMaxRecords(), 10_000)
        XCTAssertEqual(service.readClipboardRetentionDays(), 1)
        XCTAssertEqual(service.readClipboardMaxStorageMB(), 16)
    }
}
