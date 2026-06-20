import XCTest
import AppKit
@testable import Omnipo

final class ModelTests: XCTestCase {

    func test_appDestination_sectionsCoverAllDestinationsOnce() {
        let grouped = AppDestination.Section.allCases.flatMap { section in
            AppDestination.allCases.filter { $0.section == section }
        }

        XCTAssertEqual(grouped.count, AppDestination.allCases.count)
        XCTAssertEqual(Set(grouped), Set(AppDestination.allCases))
        XCTAssertEqual(AppDestination.dashboard.section, .overview)
        XCTAssertEqual(AppDestination.launcher.section, .productivity)
        XCTAssertEqual(AppDestination.cleaner.section, .system)
    }

    func test_dashboardShortcuts_mapToSafeNavigationDestinations() {
        XCTAssertEqual(DashboardShortcut.scanDisk.destination, .cleaner)
        XCTAssertEqual(DashboardShortcut.uninstallApplication.destination, .uninstaller)
        XCTAssertEqual(DashboardShortcut.auditPermissions.destination, .permissionAudit)
        XCTAssertEqual(DashboardShortcut.manageWeChat.destination, .wechatManager)
        XCTAssertEqual(Set(DashboardShortcut.allCases.map(\.destination)).count, 4)
    }

    func test_sidebarLayout_keepsViewportBelowCurrentTitlebarSafeArea() {
        XCTAssertEqual(SidebarLayout.viewportTopInset(safeAreaTop: 58, windowTitlebarHeight: 72), 96)
        XCTAssertEqual(SidebarLayout.viewportTopInset(safeAreaTop: 58, windowTitlebarHeight: 44), 82)
        XCTAssertEqual(SidebarLayout.viewportTopInset(safeAreaTop: 0, windowTitlebarHeight: 0), 0)
        XCTAssertEqual(SidebarLayout.viewportTopInset(safeAreaTop: -1, windowTitlebarHeight: -2), 0)
    }

    // MARK: - LauncherInputState

    func test_launcherInputState_defaultsEffectiveQueryToDisplayedText() {
        let state = LauncherInputState(displayedText: "wechat", isComposing: true)

        XCTAssertEqual(state.displayedText, "wechat")
        XCTAssertEqual(state.effectiveQuery, "wechat")
        XCTAssertTrue(state.isComposing)
    }

    func test_launcherInputState_keepsDisplayAndEffectiveQuerySeparate() {
        let state = LauncherInputState(
            displayedText: "we chat",
            effectiveQuery: "wechat",
            isComposing: true
        )

        XCTAssertEqual(state.displayedText, "we chat")
        XCTAssertEqual(state.effectiveQuery, "wechat")
    }

    @MainActor
    func test_launcherSearchField_publishesMarkedTextAsEffectiveQuery() {
        var published: LauncherInputState?
        let coordinator = LauncherSearchField.Coordinator(
            onInputStateChange: { published = $0 },
            onMoveSelection: { _ in },
            onSubmit: {},
            onCancel: {}
        )
        let field = LauncherSearchTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.delegate = coordinator
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 80),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = field
        window.makeFirstResponder(field)
        guard let editor = field.currentEditor() as? NSTextView else {
            XCTFail("expected field editor")
            return
        }

        editor.setMarkedText(
            "wechat",
            selectedRange: NSRange(location: 6, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        coordinator.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))

        XCTAssertEqual(published?.displayedText, "wechat")
        XCTAssertEqual(published?.effectiveQuery, "wechat")
        XCTAssertEqual(published?.isComposing, true)
    }

    @MainActor
    func test_launcherSearchField_leavesLauncherCommandsUnhandledWhileComposing() {
        var moves: [Int] = []
        var submitCount = 0
        var cancelCount = 0
        let coordinator = LauncherSearchField.Coordinator(
            onInputStateChange: { _ in },
            onMoveSelection: { moves.append($0) },
            onSubmit: { submitCount += 1 },
            onCancel: { cancelCount += 1 }
        )
        let editor = NSTextView()
        editor.setMarkedText(
            "wechat",
            selectedRange: NSRange(location: 6, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        let field = NSTextField()

        for selector in [
            #selector(NSResponder.moveUp(_:)),
            #selector(NSResponder.moveDown(_:)),
            #selector(NSResponder.insertNewline(_:)),
            #selector(NSResponder.cancelOperation(_:))
        ] {
            XCTAssertFalse(coordinator.control(field, textView: editor, doCommandBy: selector))
        }

        XCTAssertTrue(moves.isEmpty)
        XCTAssertEqual(submitCount, 0)
        XCTAssertEqual(cancelCount, 0)
    }

    @MainActor
    func test_launcherSearchField_handlesLauncherCommandsWithoutMarkedText() {
        var moves: [Int] = []
        var submitCount = 0
        var cancelCount = 0
        let coordinator = LauncherSearchField.Coordinator(
            onInputStateChange: { _ in },
            onMoveSelection: { moves.append($0) },
            onSubmit: { submitCount += 1 },
            onCancel: { cancelCount += 1 }
        )
        let editor = NSTextView()
        let field = NSTextField()

        XCTAssertTrue(coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.moveUp(_:))))
        XCTAssertTrue(coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:))))
        XCTAssertTrue(coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertTrue(coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))

        XCTAssertEqual(moves, [-1, 1])
        XCTAssertEqual(submitCount, 1)
        XCTAssertEqual(cancelCount, 1)
    }

    // MARK: - AppError

    func test_appError_stableCodesAreUnique() {
        let errors: [AppError] = [
            .invalidArgument(name: "x"),
            .invalidState(detail: "x"),
            .cancelled,
            .insufficientPermission(resource: "x"),
            .resourceUnavailable(reason: "x"),
            .systemFailure(code: "x"),
            .dataCorrupted(detail: "x"),
            .unsupportedFormat(detail: "x"),
            .unknown(code: "x")
        ]
        let codes = Set(errors.map(\.stableCode))
        XCTAssertEqual(codes.count, errors.count)
    }

    func test_appError_userDescription_isNonEmpty() {
        let errors: [AppError] = [
            .invalidArgument(name: "x"),
            .invalidState(detail: "x"),
            .cancelled,
            .insufficientPermission(resource: "x"),
            .resourceUnavailable(reason: "x"),
            .systemFailure(code: "x"),
            .dataCorrupted(detail: "x"),
            .unsupportedFormat(detail: "x"),
            .unknown(code: "x")
        ]
        for error in errors {
            XCTAssertFalse(error.userDescription.isEmpty)
        }
    }

    func test_appError_cancelledHasNoRecoverySuggestion() {
        XCTAssertNil(AppError.cancelled.recoverySuggestion)
        XCTAssertTrue(AppError.cancelled.isCancellableTerminal)
    }

    func test_appError_insufficientPermission_offersActionableSuggestion() {
        let suggestion = AppError.insufficientPermission(resource: "Disk").recoverySuggestion
        XCTAssertNotNil(suggestion)
        XCTAssertTrue(suggestion?.contains("Disk") == true)
    }

    func test_appError_safeDiagnosticContext_doesNotEchoUnderlyingValues() {
        let context = AppError.resourceUnavailable(reason: "missing").safeDiagnosticContext
        XCTAssertEqual(context["code"], "E_RESOURCE_UNAVAILABLE")
        XCTAssertNotNil(context["reason"])
    }

    // MARK: - TaskProgress

    func test_taskProgress_defaultIsIndeterminate() {
        let progress = TaskProgress(taskKey: "scan")
        XCTAssertTrue(progress.isIndeterminate)
        XCTAssertNil(progress.fractionCompleted)
        XCTAssertTrue(progress.isCancellable)
        XCTAssertFalse(progress.isTerminal)
    }

    func test_taskProgress_fractionComputedForKnownTotal() {
        let progress = TaskProgress(
            taskKey: "scan",
            status: .running,
            completedUnits: 5,
            totalUnits: 10
        )
        XCTAssertEqual(progress.fractionCompleted, 0.5)
        XCTAssertFalse(progress.isIndeterminate)
    }

    func test_taskProgress_completedExceedingTotal_isClamped() {
        let progress = TaskProgress(taskKey: "scan", completedUnits: 11, totalUnits: 10)
        XCTAssertEqual(progress.completedUnits, 10)
        XCTAssertEqual(progress.totalUnits, 10)
    }

    func test_taskProgress_negativeCompleted_isClampedToZero() {
        let progress = TaskProgress(taskKey: "scan", completedUnits: -3, totalUnits: 10)
        XCTAssertEqual(progress.completedUnits, 0)
    }

    func test_taskProgress_failedMustCarryError_normalizesToUnknown() {
        let progress = TaskProgress(taskKey: "scan", status: .failed)
        XCTAssertEqual(progress.status, .failed)
        XCTAssertEqual(progress.error, .unknown(code: "missing_error"))
    }

    func test_taskProgress_validate_detectsInvalidInputs() {
        if case .failed(let error) = TaskProgress.validate(
            completedUnits: 11,
            totalUnits: 10,
            status: .running,
            error: nil
        ) {
            XCTAssertEqual(error, .completedExceedsTotal)
        } else {
            XCTFail("Expected completedExceedsTotal validation failure")
        }

        if case .failed(let error) = TaskProgress.validate(
            completedUnits: 0,
            totalUnits: 0,
            status: .failed,
            error: nil
        ) {
            XCTAssertEqual(error, .failedWithoutError)
        } else {
            XCTFail("Expected failedWithoutError validation failure")
        }

        if case .ok = TaskProgress.validate(
            completedUnits: 0,
            totalUnits: nil,
            status: .pending,
            error: nil
        ) {
            // expected
        } else {
            XCTFail("Expected validation to succeed for valid input")
        }
    }

    func test_taskProgress_withStatus_failedWithoutError_defaultsToUnknown() {
        let progress = TaskProgress(taskKey: "scan").withStatus(.failed)
        XCTAssertEqual(progress.status, .failed)
        XCTAssertEqual(progress.error, .unknown(code: "missing_error"))
        XCTAssertTrue(progress.isTerminal)
    }

    func test_taskProgress_withStatus_cancelled_marksTerminal() {
        let progress = TaskProgress(taskKey: "scan").withStatus(.cancelled)
        XCTAssertEqual(progress.status, .cancelled)
        XCTAssertTrue(progress.isTerminal)
    }

    func test_taskProgress_withStatus_completed_clearsError() {
        let progress = TaskProgress(taskKey: "scan").withStatus(.completed)
        XCTAssertEqual(progress.status, .completed)
        XCTAssertNil(progress.error)
        XCTAssertTrue(progress.isTerminal)
    }

    func test_taskProgress_mutatingRejectedForIllegalExternalAssignment() {
        var progress = TaskProgress(taskKey: "scan", completedUnits: 0, totalUnits: 10)
        let ok = progress.updateProgress(completed: 5, total: 10)
        XCTAssertTrue(ok)
        XCTAssertEqual(progress.completedUnits, 5)

        let rejected = progress.updateProgress(completed: 100, total: 10)
        XCTAssertFalse(rejected)
        XCTAssertEqual(progress.completedUnits, 5, "拒绝非法值时不修改状态")
    }

    func test_taskProgress_markFailedRequiresError() {
        var progress = TaskProgress(taskKey: "scan", status: .running)
        let ok = progress.markFailed(.systemFailure(code: "E_TEST"))
        XCTAssertTrue(ok)
        XCTAssertEqual(progress.status, .failed)
        XCTAssertEqual(progress.error, .systemFailure(code: "E_TEST"))
        XCTAssertTrue(progress.isTerminal)
    }

    func test_taskProgress_terminalStateIsStable() {
        var progress = TaskProgress(taskKey: "scan", status: .running)
        XCTAssertTrue(progress.markCompleted())

        XCTAssertFalse(progress.markFailed(.unknown(code: "x")), "终态后不允许 markFailed")
        XCTAssertFalse(progress.markCancelled(), "终态后不允许 markCancelled")
        XCTAssertFalse(progress.updateProgress(completed: 99), "终态后不允许 updateProgress")
        XCTAssertFalse(progress.markRunning(), "终态后不允许 markRunning")

        XCTAssertEqual(progress.status, .completed, "终态保持稳定")
    }

    func test_taskProgress_cancelledIsTerminal() {
        var progress = TaskProgress(taskKey: "scan", status: .running)
        XCTAssertTrue(progress.markCancelled())
        XCTAssertTrue(progress.isTerminal)
        XCTAssertFalse(progress.markCompleted())
        XCTAssertEqual(progress.status, .cancelled)
    }

    // MARK: - OperationLog

    func test_operationLog_carriesSanitizedFields() {
        let log = OperationLog(
            level: .info,
            category: .lifecycle,
            message: "lifecycle.start",
            stableCode: "I_LIFECYCLE"
        )

        XCTAssertEqual(log.level, .info)
        XCTAssertEqual(log.category, .lifecycle)
        XCTAssertEqual(log.stableCode, "I_LIFECYCLE")
        XCTAssertTrue(log.sanitizedContext.isEmpty)
    }
}
