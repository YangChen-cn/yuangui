import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let window: NSWindow
    private let selection = SettingsSelectionModel()

    init(language: AppLanguageSettings, petStore: PetStore, aiSettings: AISettingsStore, loginItem: LoginItemStore, focusTimer: FocusTimerStore, music: MusicFeature, diary: DiaryFeature, externalAudioInterruption: ExternalAudioInterruptionController, quickTools: QuickToolsController, finderExtension: FinderExtensionController, updater: AppUpdateStore, guide: PetGuideCoordinator, showPet: @escaping () -> Void, restartOnboarding: @escaping () -> Void, appActions: AppActions = .disabled) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = AppLocalizer.string("window.settings")
        window.isReleasedWhenClosed = false
        window.center()
        window.contentMinSize = NSSize(width: 700, height: 520)
        window.contentView = NSHostingView(rootView:
            SettingsView(
                language: language,
                pet: petStore,
                ai: aiSettings,
                loginItem: loginItem,
                focusTimer: focusTimer,
                music: music,
                diary: diary,
                externalAudioInterruption: externalAudioInterruption,
                quickTools: quickTools,
                finderExtension: finderExtension,
                updater: updater,
                guide: guide,
                selection: selection,
                showPet: showPet,
                restartOnboarding: restartOnboarding
            )
            .environment(\.appActions, appActions)
        )
    }

    func show(tab: SettingsTab) {
        selection.selectedTab = tab
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}
