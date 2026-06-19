import Foundation

public enum AppError: Error, Sendable, Equatable {
    case invalidArgument(name: String)
    case invalidState(detail: String)
    case cancelled
    case insufficientPermission(resource: String)
    case resourceUnavailable(reason: String)
    case systemFailure(code: String)
    case dataCorrupted(detail: String)
    case unsupportedFormat(detail: String)
    case unknown(code: String)

    public var stableCode: String {
        switch self {
        case .invalidArgument: return "E_INVALID_ARGUMENT"
        case .invalidState: return "E_INVALID_STATE"
        case .cancelled: return "E_CANCELLED"
        case .insufficientPermission: return "E_PERMISSION"
        case .resourceUnavailable: return "E_RESOURCE_UNAVAILABLE"
        case .systemFailure: return "E_SYSTEM"
        case .dataCorrupted: return "E_DATA_CORRUPTED"
        case .unsupportedFormat: return "E_UNSUPPORTED_FORMAT"
        case .unknown: return "E_UNKNOWN"
        }
    }

    public var userDescription: String {
        switch self {
        case .invalidArgument(let name):
            return "请求参数 \(name) 无效。"
        case .invalidState(let detail):
            return "应用状态暂不可用:\(detail)。"
        case .cancelled:
            return "操作已取消。"
        case .insufficientPermission(let resource):
            return "没有访问 \(resource) 所需的系统权限。"
        case .resourceUnavailable(let reason):
            return "所需资源不可用:\(reason)。"
        case .systemFailure:
            return "发生系统级错误,请稍后重试。"
        case .dataCorrupted(let detail):
            return "数据已损坏或无法解析:\(detail)。"
        case .unsupportedFormat(let detail):
            return "暂不支持该格式:\(detail)。"
        case .unknown:
            return "发生未知错误。"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .cancelled:
            return nil
        case .invalidArgument:
            return "请检查输入后重试。"
        case .invalidState:
            return "请重启应用或稍后再试。"
        case .insufficientPermission(let resource):
            return "请在系统设置 > 隐私与安全性中授予 \(resource) 权限后重试。"
        case .resourceUnavailable:
            return "请确认所需资源存在并重试。"
        case .systemFailure:
            return "请稍后重试,如持续发生请重启应用。"
        case .dataCorrupted:
            return "请尝试重新生成或恢复该数据。"
        case .unsupportedFormat:
            return "请使用受支持的格式。"
        case .unknown:
            return "请稍后重试。"
        }
    }

    public var isCancellableTerminal: Bool {
        if case .cancelled = self { return true }
        return false
    }
}

extension AppError {
    public var safeDiagnosticContext: [String: String] {
        var context: [String: String] = ["code": stableCode]
        switch self {
        case .invalidArgument(let name):
            context["argumentName"] = name
        case .invalidState(let detail):
            context["stateDetail"] = detail
        case .insufficientPermission(let resource):
            context["resource"] = resource
        case .resourceUnavailable(let reason):
            context["reason"] = reason
        case .systemFailure(let code):
            context["systemCode"] = code
        case .dataCorrupted(let detail):
            context["corruptionDetail"] = detail
        case .unsupportedFormat(let detail):
            context["formatDetail"] = detail
        case .unknown(let code):
            context["unknownCode"] = code
        case .cancelled:
            break
        }
        return context
    }
}
