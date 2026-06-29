import Foundation

public enum SystemMonitorTab: String, CaseIterable, Identifiable, Sendable, Equatable {
    case overview
    case cpu
    case memory
    case energy
    case disk
    case network

    public var id: Self { self }

    public var title: String {
        switch self {
        case .overview: return "纵览"
        case .cpu: return "CPU"
        case .memory: return "内存"
        case .energy: return "能耗"
        case .disk: return "磁盘"
        case .network: return "网络"
        }
    }

    public var accessibilityLabel: String {
        switch self {
        case .overview: return "系统监控纵览"
        case .cpu: return "CPU 监控"
        case .memory: return "内存监控"
        case .energy: return "能耗监控"
        case .disk: return "磁盘监控"
        case .network: return "网络监控"
        }
    }
}
