import ServiceManagement
import XCTest
@testable import Omnipo

final class LaunchAtLoginServiceTests: XCTestCase {
    func test_systemStatusMapping_coversKnownStatuses() async {
        await MainActor.run {
            XCTAssertEqual(SystemLaunchAtLoginService.map(.notRegistered), .disabled)
            XCTAssertEqual(SystemLaunchAtLoginService.map(.enabled), .enabled)
            XCTAssertEqual(SystemLaunchAtLoginService.map(.requiresApproval), .requiresApproval)
            XCTAssertEqual(SystemLaunchAtLoginService.map(.notFound), .unavailable)
        }
    }

    func test_refresh_usesEffectiveStatusAndPersistsConfirmedValue() async {
        await MainActor.run {
            let fixture = Fixture(status: .enabled)

            fixture.controller.refresh()

            XCTAssertTrue(fixture.controller.isEnabled)
            XCTAssertTrue(fixture.settings.readBool(forKey: .launchAtLogin))
            XCTAssertTrue(fixture.service.requests.isEmpty)
        }
    }

    func test_successfulRequest_persistsEffectiveStatus() async {
        let fixture = await MainActor.run { Fixture(status: .disabled) }
        await MainActor.run {
            fixture.service.onRequest = { requested in
                fixture.service.status = requested ? .enabled : .disabled
            }
        }

        await fixture.controller.setEnabled(true)

        await MainActor.run {
            XCTAssertEqual(fixture.service.requests, [true])
            XCTAssertTrue(fixture.controller.isEnabled)
            XCTAssertTrue(fixture.settings.readBool(forKey: .launchAtLogin))
            XCTAssertNil(fixture.controller.message)
        }
    }

    func test_successfulDisable_persistsEffectiveStatus() async {
        let fixture = await MainActor.run { Fixture(status: .enabled) }
        await MainActor.run {
            fixture.controller.refresh()
            fixture.service.onRequest = { requested in
                fixture.service.status = requested ? .enabled : .disabled
            }
        }

        await fixture.controller.setEnabled(false)

        await MainActor.run {
            XCTAssertEqual(fixture.service.requests, [false])
            XCTAssertFalse(fixture.controller.isEnabled)
            XCTAssertFalse(fixture.settings.readBool(forKey: .launchAtLogin))
            XCTAssertNil(fixture.controller.message)
        }
    }

    func test_failedRequest_rollsBackAndDoesNotPersistRequestedValue() async {
        let fixture = await MainActor.run { Fixture(status: .disabled) }
        await MainActor.run {
            fixture.settings.write(false, forKey: .launchAtLogin)
            fixture.service.error = TestError.denied
        }

        await fixture.controller.setEnabled(true)

        await MainActor.run {
            XCTAssertEqual(fixture.service.requests, [true])
            XCTAssertFalse(fixture.controller.isEnabled)
            XCTAssertFalse(fixture.settings.readBool(forKey: .launchAtLogin))
            XCTAssertEqual(
                fixture.controller.message,
                "无法更新开机启动设置。请稍后重试,或在系统设置中检查登录项。"
            )
            XCTAssertEqual(fixture.logger.events.last?.stableCode, "W_LAUNCH_AT_LOGIN")
            XCTAssertEqual(fixture.logger.events.last?.sanitizedContext["reason"], "failed")
        }
    }

    func test_requiresApproval_isNotPresentedOrPersistedAsEnabled() async {
        let fixture = await MainActor.run { Fixture(status: .disabled) }
        await MainActor.run {
            fixture.service.onRequest = { _ in
                fixture.service.status = .requiresApproval
            }
        }

        await fixture.controller.setEnabled(true)

        await MainActor.run {
            XCTAssertFalse(fixture.controller.isEnabled)
            XCTAssertFalse(fixture.settings.readBool(forKey: .launchAtLogin))
            XCTAssertEqual(fixture.controller.status, .requiresApproval)
            XCTAssertNotNil(fixture.controller.message)
        }
    }

    func test_requestMatchingEffectiveStatus_doesNotCallSystemService() async {
        let fixture = await MainActor.run { Fixture(status: .enabled) }
        await MainActor.run {
            fixture.controller.refresh()
        }

        await fixture.controller.setEnabled(true)

        await MainActor.run {
            XCTAssertTrue(fixture.service.requests.isEmpty)
        }
    }
}

private extension LaunchAtLoginServiceTests {
    enum TestError: Error {
        case denied
    }

    @MainActor
    final class Fixture {
        let settings = UserDefaultsSettingsService.testing(
            suiteName: "omnipo.tests.launch-at-login.\(UUID().uuidString)"
        )
        let service: TestLaunchAtLoginService
        let logger = RecordingLoggingService()
        let controller: LaunchAtLoginSettingsController

        init(status: LaunchAtLoginStatus) {
            service = TestLaunchAtLoginService(status: status)
            controller = LaunchAtLoginSettingsController(
                service: service,
                settings: settings,
                logger: logger
            )
        }
    }

    @MainActor
    final class TestLaunchAtLoginService: LaunchAtLoginService {
        var status: LaunchAtLoginStatus
        var requests: [Bool] = []
        var error: Error?
        var onRequest: ((Bool) -> Void)?

        init(status: LaunchAtLoginStatus) {
            self.status = status
        }

        func setEnabled(_ isEnabled: Bool) throws {
            requests.append(isEnabled)
            if let error { throw error }
            onRequest?(isEnabled)
        }
    }

    final class RecordingLoggingService: LoggingService, @unchecked Sendable {
        private(set) var events: [LogEvent] = []

        func log(_ event: LogEvent) {
            events.append(event)
        }
    }
}
