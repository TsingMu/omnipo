import SwiftUI
import Observation

@Observable
@MainActor
final class AppState {
    var lastOpenedDestination: AppDestination

    init(lastOpenedDestination: AppDestination = .dashboard) {
        self.lastOpenedDestination = lastOpenedDestination
    }
}
