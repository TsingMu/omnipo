import Foundation
import Observation

@Observable
@MainActor
final class DependencyContainer {
    let settings: any SettingsService
    let logging: any LoggingService

    init(settings: any SettingsService, logging: any LoggingService) {
        self.settings = settings
        self.logging = logging
    }

    static func production() -> DependencyContainer {
        let settings = UserDefaultsSettingsService()
        let logging = OSLogLoggingService()
        return DependencyContainer(settings: settings, logging: logging)
    }
}
