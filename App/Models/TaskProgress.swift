import Foundation

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
    }

    public let id: UUID
    public let taskKey: String
    public var status: Status
    public var stage: String
    public var userMessage: String
    public var completedUnits: Int
    public var totalUnits: Int?
    public var isCancellable: Bool
    public var error: AppError?

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
        self.stage = stage
        self.userMessage = userMessage

        if completedUnits < 0 {
            self.completedUnits = 0
        } else {
            self.completedUnits = completedUnits
        }

        if let total = totalUnits, total < 0 {
            self.totalUnits = 0
        } else {
            self.totalUnits = totalUnits
        }

        if let total = self.totalUnits, self.completedUnits > total {
            self.completedUnits = total
        }

        self.isCancellable = isCancellable

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

    public func withStatus(_ newStatus: Status, error: AppError? = nil) -> TaskProgress {
        var copy = self
        copy.status = newStatus
        if newStatus == .failed {
            copy.error = error ?? .unknown(code: "missing_error")
        } else {
            copy.error = error
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
