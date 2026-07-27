import SwiftUI

enum SettingsTab: Int, CaseIterable, Equatable, Sendable {
    case general
    case pet
    case quickTools
    case ai
    case focus
    case music
    case diary
    case about
}

enum AppRoute: Equatable, Sendable {
    case statusDashboard
    case chat
    case settings(SettingsTab)
    case chatHistory
    case maintenance(tab: Int)
    case music
    case diary
    case quickDiary
}

enum QuickToolRoute: Equatable, Sendable {
    case regionScreenshot
    case screenshotTranslation
    case translateSelection
}

struct AppActions: @unchecked Sendable {
    var open: @MainActor @Sendable (AppRoute) -> Void
    var runQuickTool: @MainActor @Sendable (QuickToolRoute) -> Void
    var terminateForUpdate: @MainActor @Sendable () async -> Bool

    nonisolated static let disabled = AppActions(
        open: { _ in },
        runQuickTool: { _ in },
        terminateForUpdate: { false }
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
