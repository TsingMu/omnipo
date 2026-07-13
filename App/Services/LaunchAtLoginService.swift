import Foundation
import Observation
import ServiceManagement

public enum LaunchAtLoginStatus: String, Sendable, Equatable, CaseIterable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable

    public var isEnabled: Bool {
        self == .enabled
    }

    public var recoveryMessage: String? {
        switch self {
        case .disabled, .enabled:
            return nil
        case .requiresApproval:
            return "需要在“系统设置 > 通用 > 登录项与扩展”中允许 Omnipo,然后返回此处刷新状态。"
        case .unavailable:
            return "当前应用副本无法设置开机启动。请将 Omnipo 放入“应用程序”文件夹后重试。"
        }
    }
}

@MainActor
public protocol LaunchAtLoginService: AnyObject {
    var status: LaunchAtLoginStatus { get }

    func setEnabled(_ isEnabled: Bool) throws
}

@MainActor
public final class SystemLaunchAtLoginService: LaunchAtLoginService {
    private let service: SMAppService

    public init(service: SMAppService = .mainApp) {
        self.service = service
    }

    public var status: LaunchAtLoginStatus {
        Self.map(service.status)
    }

    public func setEnabled(_ isEnabled: Bool) throws {
        if isEnabled {
            try service.register()
        } else {
            try service.unregister()
        }
    }

    static func map(_ status: SMAppService.Status) -> LaunchAtLoginStatus {
        switch status {
        case .notRegistered:
            return .disabled
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }
}

@Observable
@MainActor
final class LaunchAtLoginSettingsController {
    private let service: any LaunchAtLoginService
    private let settings: any SettingsService
    private let logger: any LoggingService
    private(set) var status: LaunchAtLoginStatus = .disabled
    private(set) var isUpdating = false
    private(set) var transientMessage: String?

    init(
        service: any LaunchAtLoginService,
        settings: any SettingsService,
        logger: any LoggingService
    ) {
        self.service = service
        self.settings = settings
        self.logger = logger
    }

    var isEnabled: Bool {
        status.isEnabled
    }

    var message: String? {
        transientMessage ?? status.recoveryMessage
    }

    func refresh() {
        transientMessage = nil
        status = service.status
        persistConfirmedStatus()
        log(result: "refreshed")
    }

    func setEnabled(_ isEnabled: Bool) async {
        guard !isUpdating, isEnabled != status.isEnabled else { return }

        isUpdating = true
        transientMessage = nil
        await Task.yield()

        do {
            try service.setEnabled(isEnabled)
            status = service.status
            persistConfirmedStatus()

            if status.isEnabled == isEnabled {
                log(result: "succeeded")
            } else {
                transientMessage = status.recoveryMessage
                    ?? "macOS 未应用开机启动请求,请稍后重试。"
                log(result: "notApplied")
            }
        } catch {
            status = service.status
            persistConfirmedStatus()
            transientMessage = "无法更新开机启动设置。请稍后重试,或在系统设置中检查登录项。"
            log(result: "failed")
        }

        isUpdating = false
    }

    private func persistConfirmedStatus() {
        settings.write(status.isEnabled, forKey: .launchAtLogin)
    }

    private func log(result: String) {
        logger.log(LogEvent(
            level: result == "failed" ? .warning : .info,
            category: .settings,
            message: "settings.launchAtLogin.reconciled",
            stableCode: result == "failed" ? "W_LAUNCH_AT_LOGIN" : "I_LAUNCH_AT_LOGIN",
            sanitizedContext: [
                "stateDetail": status.rawValue,
                "reason": result
            ]
        ))
    }
}
