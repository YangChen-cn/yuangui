import SwiftUI

enum AppRoute: Equatable, Sendable {
    case statusDashboard
    case chat
    case settings
    case chatHistory
    case maintenance(tab: Int)
    case music
}

enum QuickToolRoute: Equatable, Sendable {
    case regionScreenshot
    case screenshotTranslation
    case translateSelection
}

struct AppActions: @unchecked Sendable {
    var open: @MainActor @Sendable (AppRoute) -> Void
    var runQuickTool: @MainActor @Sendable (QuickToolRoute) -> Void
    var terminateForUpdate: @MainActor @Sendable () -> Void

    nonisolated static let disabled = AppActions(
        open: { _ in },
        runQuickTool: { _ in },
        terminateForUpdate: {}
    )
}

private struct AppActionsEnvironmentKey: EnvironmentKey {
    static let defaultValue = AppActions.disabled
}

extension EnvironmentValues {
    var appActions: AppActions {
        get { self[AppActionsEnvironmentKey.self] }
        set { self[AppActionsEnvironmentKey.self] = newValue }
    }
}
