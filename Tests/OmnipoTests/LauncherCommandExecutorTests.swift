import XCTest
import Observation
@testable import Omnipo

@MainActor
private final class FakeLauncherNavigation: LauncherNavigation {
    private(set) var activatedCount = 0
    private(set) var navigatedDestinations: [AppDestination] = []

    func activateMainWindow() {
        activatedCount += 1
    }

    func navigate(to destination: AppDestination) {
        navigatedDestinations.append(destination)
    }
}

@MainActor
final class LauncherCommandExecutorTests: XCTestCase {

    func test_destinationMapping_coversAllCommands() {
        XCTAssertEqual(LauncherCommandExecutor.destination(for: .openClipboard), .clipboard)
        XCTAssertEqual(LauncherCommandExecutor.destination(for: .scanDisk), .cleaner)
        XCTAssertEqual(LauncherCommandExecutor.destination(for: .uninstallApplication), .uninstaller)
        XCTAssertEqual(LauncherCommandExecutor.destination(for: .auditPermissions), .permissionAudit)
        XCTAssertEqual(LauncherCommandExecutor.destination(for: .inspectWeChatStorage), .wechatManager)
        XCTAssertEqual(LauncherCommandExecutor.destination(for: .openSystemMonitor), .systemMonitor)
    }

    func test_execute_activatesWindowAndNavigates() {
        let navigator = FakeLauncherNavigation()
        let executor = LauncherCommandExecutor(navigator: navigator)

        executor.execute(.openClipboard)

        XCTAssertEqual(navigator.activatedCount, 1)
        XCTAssertEqual(navigator.navigatedDestinations, [.clipboard])
    }

    func test_execute_multipleCommands_navigateToEachDestination() {
        let navigator = FakeLauncherNavigation()
        let executor = LauncherCommandExecutor(navigator: navigator)

        for command in LauncherCommand.allCases {
            executor.execute(command)
        }

        XCTAssertEqual(navigator.activatedCount, LauncherCommand.allCases.count)
        XCTAssertEqual(Set(navigator.navigatedDestinations), Set(LauncherCommand.allCases.map {
            LauncherCommandExecutor.destination(for: $0)
        }))
    }

    func test_mainWindowNavigator_publishesAndConsumesObservableDestination() {
        let navigator = MainWindowNavigator()
        let changed = expectation(description: "pending destination changed")

        withObservationTracking {
            _ = navigator.pendingDestination
        } onChange: {
            changed.fulfill()
        }

        navigator.navigate(to: .systemMonitor)

        wait(for: [changed], timeout: 1)
        XCTAssertEqual(navigator.pendingDestination, .systemMonitor)

        navigator.consumePendingDestination()
        XCTAssertNil(navigator.pendingDestination)
    }

    func test_mainWindowNavigator_recognizesSwiftUIMainWindowIdentifiers() {
        XCTAssertTrue(MainWindowNavigator.isMainWindowIdentifier("omnipo.main"))
        XCTAssertTrue(MainWindowNavigator.isMainWindowIdentifier("omnipo.main-AppWindow-1"))
        XCTAssertTrue(MainWindowNavigator.isMainWindowIdentifier("omnipo.main-AppWindow-42"))
        XCTAssertFalse(MainWindowNavigator.isMainWindowIdentifier("omnipo.settings-AppWindow-1"))
        XCTAssertFalse(MainWindowNavigator.isMainWindowIdentifier(nil))
    }
}
