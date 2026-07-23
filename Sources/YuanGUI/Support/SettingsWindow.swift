import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let window: NSWindow
    private let selection = SettingsSelectionModel()

    init(petStore: PetStore, aiSettings: AISettingsStore, loginItem: LoginItemStore, focusTimer: FocusTimerStore, music: MusicFeature, externalAudioInterruption: ExternalAudioInterruptionController, quickTools: QuickToolsController, showPet: @escaping () -> Void, appActions: AppActions = .disabled) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "元圭与 VCC 设置"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentMinSize = NSSize(width: 700, height: 520)
        window.contentView = NSHostingView(rootView:
            SettingsView(
                pet: petStore,
                ai: aiSettings,
                loginItem: loginItem,
                focusTimer: focusTimer,
                music: music,
                externalAudioInterruption: externalAudioInterruption,
                quickTools: quickTools,
                selection: selection,
                showPet: showPet
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
