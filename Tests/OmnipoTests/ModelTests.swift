import XCTest
@testable import Omnipo

final class ModelTests: XCTestCase {

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
