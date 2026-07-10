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

    func test_weChatStorageRootBookmarks_roundTripAndClear() {
        let service = UserDefaultsSettingsService.testing(suiteName: "omnipo.tests.defaults.\(UUID().uuidString)")
        let bookmarks = [Data([0x11, 0x12]), Data([0x21, 0x22])]

        service.writeWeChatStorageRootBookmarks(bookmarks)
        XCTAssertEqual(service.readWeChatStorageRootBookmarks(), bookmarks)

        service.writeWeChatStorageRootBookmarks([])
        XCTAssertTrue(service.readWeChatStorageRootBookmarks().isEmpty)
    }

    func test_weChatSensitiveNamesConsent_roundTripsAndDefaultsOff() {
        let service = UserDefaultsSettingsService.testing(suiteName: "omnipo.tests.defaults.\(UUID().uuidString)")
        XCTAssertFalse(service.readBool(forKey: .weChatSensitiveNamesEnabled))

        service.write(true, forKey: .weChatSensitiveNamesEnabled)
        XCTAssertTrue(service.readBool(forKey: .weChatSensitiveNamesEnabled))

        service.write(false, forKey: .weChatSensitiveNamesEnabled)
        XCTAssertFalse(service.readBool(forKey: .weChatSensitiveNamesEnabled))
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

    func test_writeAndRead_clipboardPanelShortcut_roundTrips() {
        let service = UserDefaultsSettingsService.testing(suiteName: "omnipo.tests.defaults.\(UUID().uuidString)")
        let shortcut = KeyboardShortcut(keyCode: KeyCodes.c, modifierFlags: [.option, .command])

        service.writeClipboardPanelShortcut(shortcut)

        XCTAssertEqual(service.readClipboardPanelShortcut(), shortcut)
    }

    func test_clearClipboardPanelShortcut_resetsToDefault() {
        let service = UserDefaultsSettingsService.testing(suiteName: "omnipo.tests.defaults.\(UUID().uuidString)")
        service.writeClipboardPanelShortcut(.defaultClipboardPanel)
        service.clearClipboardPanelShortcut()

        XCTAssertNil(service.readClipboardPanelShortcut())
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
        XCTAssertTrue(service.readBool(forKey: .clipboardAutoPaste))
        XCTAssertEqual(service.readClipboardMaxRecords(), ClipboardSettingsDefaults.maxRecords)
        XCTAssertEqual(service.readClipboardRetentionDays(), ClipboardSettingsDefaults.retentionDays)
        XCTAssertEqual(service.readClipboardMaxStorageMB(), ClipboardSettingsDefaults.maxStorageMB)
        XCTAssertEqual(service.readClipboardPollingIntervalSeconds(), ClipboardSettingsDefaults.pollingIntervalSeconds)
        XCTAssertEqual(service.readClipboardImageQuality(), ClipboardSettingsDefaults.imageQuality)
        XCTAssertTrue(service.readBool(forKey: .showMenuBarIcon))
        XCTAssertEqual(service.readClipboardPanelPosition(), .center)
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

    func test_clipboardSettings_clampAdvancedValues() {
        let service = UserDefaultsSettingsService.testing(suiteName: "omnipo.tests.defaults.\(UUID().uuidString)")

        service.writeClipboardPollingIntervalSeconds(9)
        service.writeClipboardImageQuality(-1)

        XCTAssertEqual(service.readClipboardPollingIntervalSeconds(), 2.0)
        XCTAssertEqual(service.readClipboardImageQuality(), 0.1)
    }

    func test_clipboardSettings_stringLists_roundTripAndClear() {
        let service = UserDefaultsSettingsService.testing(suiteName: "omnipo.tests.defaults.\(UUID().uuidString)")

        service.writeClipboardExcludedApplications(["com.example.app", "", " com.example.other "])
        service.writeClipboardExcludedPatterns(["password", "\\d{6}"])

        XCTAssertEqual(service.readClipboardExcludedApplications(), ["com.example.app", "com.example.other"])
        XCTAssertEqual(service.readClipboardExcludedPatterns(), ["password", "\\d{6}"])

        service.writeClipboardExcludedApplications([])
        service.writeClipboardExcludedPatterns([])

        XCTAssertEqual(service.readClipboardExcludedApplications(), [])
        XCTAssertEqual(service.readClipboardExcludedPatterns(), [])
    }

    func test_clipboardPanelPosition_roundTripsAndFallsBack() {
        let service = UserDefaultsSettingsService.testing(suiteName: "omnipo.tests.defaults.\(UUID().uuidString)")

        service.writeClipboardPanelPosition(.followMouse)
        XCTAssertEqual(service.readClipboardPanelPosition(), .followMouse)

        service.write("unknown", forKey: .clipboardPanelPosition)
        XCTAssertEqual(service.readClipboardPanelPosition(), .center)
    }

    func test_resetClippyStyleSettingsToDefaults_restoresImportedDefaults() {
        let service = UserDefaultsSettingsService.testing(suiteName: "omnipo.tests.defaults.\(UUID().uuidString)")

        service.write(false, forKey: .clipboardAutoPaste)
        service.writeClipboardMaxRecords(20)
        service.writeClipboardExcludedApplications(["com.example.app"])
        service.writeClipboardExcludedPatterns(["secret"])
        service.writeClipboardPollingIntervalSeconds(2)
        service.writeClipboardImageQuality(0.1)
        service.write(false, forKey: .showMenuBarIcon)
        service.writeClipboardPanelPosition(.lastPosition)

        service.resetClippyStyleSettingsToDefaults()

        XCTAssertTrue(service.readBool(forKey: .clipboardAutoPaste))
        XCTAssertEqual(service.readClipboardMaxRecords(), 1_000)
        XCTAssertEqual(service.readClipboardRetentionDays(), 30)
        XCTAssertEqual(service.readClipboardMaxStorageMB(), 500)
        XCTAssertEqual(service.readClipboardExcludedApplications(), [])
        XCTAssertEqual(service.readClipboardExcludedPatterns(), [])
        XCTAssertEqual(service.readClipboardPollingIntervalSeconds(), 0.3)
        XCTAssertEqual(service.readClipboardImageQuality(), 0.8)
        XCTAssertTrue(service.readBool(forKey: .showMenuBarIcon))
        XCTAssertEqual(service.readClipboardPanelPosition(), .center)
    }
}
