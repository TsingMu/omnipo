import Foundation

/// 统一任务进度值模型。
///
/// 状态、单位、错误字段使用 `public private(set)`,调用方不能直接赋值制造非法状态;
/// 所有变化必须通过 `markCompleted`、`markFailed`、`markCancelled`、`updateProgress`、`withStatus` 等受控转换方法。
public struct TaskProgress: Sendable, Equatable {
    public enum Status: String, Sendable, Equatable {
        case pending
        case running
        case completed
        case failed
        case cancelled
    }

    public enum ValidationError: Error, Equatable, Sendable {
        case completedExceedsTotal
        case negativeCompleted
        case negativeTotal
        case failedWithoutError
        case transitionFromTerminal
    }

    public let id: UUID
    public let taskKey: String
    public private(set) var status: Status
    public private(set) var stage: String
    public private(set) var userMessage: String
    public private(set) var completedUnits: Int
    public private(set) var totalUnits: Int?
    public let isCancellable: Bool
    public private(set) var error: AppError?

    public init(
        id: UUID = UUID(),
        taskKey: String,
        status: Status = .pending,
        stage: String = "",
        userMessage: String = "",
        completedUnits: Int = 0,
        totalUnits: Int? = nil,
        isCancellable: Bool = true,
        error: AppError? = nil
    ) {
        self.id = id
        self.taskKey = taskKey
        self.isCancellable = isCancellable

        let normalizedCompleted = max(0, completedUnits)
        let normalizedTotal: Int? = {
            guard let total = totalUnits else { return nil }
            return max(0, total)
        }()
        let clampedCompleted: Int = {
            if let total = normalizedTotal, normalizedCompleted > total {
                return total
            }
            return normalizedCompleted
        }()

        self.completedUnits = clampedCompleted
        self.totalUnits = normalizedTotal
        self.stage = stage
        self.userMessage = userMessage

        if status == .failed && error == nil {
            self.status = .failed
            self.error = .unknown(code: "missing_error")
        } else {
            self.status = status
            self.error = error
        }
    }

    public var isIndeterminate: Bool {
        totalUnits == nil
    }

    public var fractionCompleted: Double? {
        guard let total = totalUnits, total > 0 else { return nil }
        let clamped = min(max(Double(completedUnits), 0), Double(total))
        return clamped / Double(total)
    }

    public var isTerminal: Bool {
        switch status {
        case .completed, .failed, .cancelled:
            return true
        case .pending, .running:
            return false
        }
    }
}

public extension TaskProgress {
    @discardableResult
    mutating func markRunning(stage: String? = nil, userMessage: String? = nil) -> Bool {
        guard !isTerminal else { return false }
        status = .running
        if let stage { self.stage = stage }
        if let userMessage { self.userMessage = userMessage }
        return true
    }

    @discardableResult
    mutating func updateProgress(completed: Int, total: Int? = nil, userMessage: String? = nil) -> Bool {
        guard !isTerminal else { return false }
        let normalizedTotal: Int? = {
            if let total = total ?? self.totalUnits {
                return max(0, total)
            }
            return nil
        }()
        let normalizedCompleted = max(0, completed)
        if let total = normalizedTotal, normalizedCompleted > total {
            return false
        }
        self.completedUnits = normalizedCompleted
        self.totalUnits = normalizedTotal
        if let userMessage { self.userMessage = userMessage }
        return true
    }

    @discardableResult
    mutating func markCompleted(userMessage: String? = nil) -> Bool {
        guard !isTerminal else { return false }
        status = .completed
        if let userMessage { self.userMessage = userMessage }
        return true
    }

    @discardableResult
    mutating func markFailed(_ error: AppError, userMessage: String? = nil) -> Bool {
        guard !isTerminal else { return false }
        status = .failed
        self.error = error
        if let userMessage { self.userMessage = userMessage }
        return true
    }

    @discardableResult
    mutating func markCancelled(userMessage: String? = nil) -> Bool {
        guard !isTerminal else { return false }
        status = .cancelled
        if let userMessage { self.userMessage = userMessage }
        return true
    }

    func withStatus(_ newStatus: Status, error: AppError? = nil) -> TaskProgress {
        var copy = self
        switch newStatus {
        case .failed:
            copy.markFailed(error ?? .unknown(code: "missing_error"))
        case .completed:
            copy.markCompleted()
        case .cancelled:
            copy.markCancelled()
        case .pending, .running:
            copy.status = newStatus
            copy.error = nil
        }
        return copy
    }
}

public extension TaskProgress {
    enum ValidationOutcome {
        case ok(TaskProgress)
        case failed(ValidationError)
    }

    static func validate(
        completedUnits: Int,
        totalUnits: Int?,
        status: Status,
        error: AppError?
    ) -> ValidationOutcome {
        if completedUnits < 0 { return .failed(.negativeCompleted) }
        if let total = totalUnits, total < 0 { return .failed(.negativeTotal) }
        if let total = totalUnits, completedUnits > total {
            return .failed(.completedExceedsTotal)
        }
        if status == .failed && error == nil {
            return .failed(.failedWithoutError)
        }
        return .ok(TaskProgress(
            taskKey: "_validate",
            status: status,
            completedUnits: completedUnits,
            totalUnits: totalUnits,
            error: error
        ))
    }
}
