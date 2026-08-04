import AppKit
import SwiftUI

@MainActor
final class SettingsSelectionModel: ObservableObject {
    @Published var selectedTab: SettingsTab

    init(selectedTab: SettingsTab = .pet) {
        self.selectedTab = selectedTab
    }
}

struct SettingsView: View {
    @ObservedObject var language: AppLanguageSettings
    let pet: PetStore
    let ai: AISettingsStore
    let loginItem: LoginItemStore
    let focusTimer: FocusTimerStore
    let music: MusicFeature
    let diary: DiaryFeature
    let externalAudioInterruption: ExternalAudioInterruptionController
    let quickTools: QuickToolsController
    let finderExtension: FinderExtensionController
    let updater: AppUpdateStore
    let guide: PetGuideCoordinator
    let selection: SettingsSelectionModel
    let showPet: () -> Void
    let restartOnboarding: () -> Void

    init(
        language: AppLanguageSettings,
        pet: PetStore,
        ai: AISettingsStore,
        loginItem: LoginItemStore,
        focusTimer: FocusTimerStore,
        music: MusicFeature,
        diary: DiaryFeature,
        externalAudioInterruption: ExternalAudioInterruptionController,
        quickTools: QuickToolsController,
        finderExtension: FinderExtensionController,
        updater: AppUpdateStore,
        guide: PetGuideCoordinator,
        selection: SettingsSelectionModel,
        showPet: @escaping () -> Void,
        restartOnboarding: @escaping () -> Void
    ) {
        self.language = language
        self.pet = pet
        self.ai = ai
        self.loginItem = loginItem
        self.focusTimer = focusTimer
        self.music = music
        self.diary = diary
        self.externalAudioInterruption = externalAudioInterruption
        self.quickTools = quickTools
        self.finderExtension = finderExtension
        self.updater = updater
        self.guide = guide
        self.selection = selection
        self.showPet = showPet
        self.restartOnboarding = restartOnboarding
    }

    var body: some View {
        NavigationSplitView {
            SettingsNavigationShell(selection: selection)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 260)
        } detail: {
            SettingsDetailView(
                selection: selection,
                language: language,
                pet: pet,
                ai: ai,
                loginItem: loginItem,
                focusTimer: focusTimer,
                music: music,
                diary: diary,
                externalAudioInterruption: externalAudioInterruption,
                quickTools: quickTools,
                finderExtension: finderExtension,
                updater: updater,
                guide: guide,
                showPet: showPet,
                restartOnboarding: restartOnboarding
            )
        }
        .frame(minWidth: 700, idealWidth: 760, minHeight: 520, idealHeight: 560)
        .alert(
            AppLocalizer.string("settings.language.restartTitle"),
            isPresented: Binding(
                get: { language.needsRestart },
                set: { if !$0 { language.dismissRestartNotice() } }
            )
        ) {
            Button(AppLocalizer.string("settings.language.restartLater"), role: .cancel) {
                language.dismissRestartNotice()
            }
            Button(AppLocalizer.string("settings.language.quit")) {
                NSApp.terminate(nil)
            }
        } message: {
            Text(AppLocalizer.string("settings.language.restartMessage"))
        }
    }
}

struct SettingsNavigationShell: View {
    @ObservedObject var selection: SettingsSelectionModel

    var body: some View {
        List(selection: $selection.selectedTab) {
            Label(AppLocalizer.string("settings.general"), systemImage: "gearshape")
                .tag(SettingsTab.general)
            Label("桌宠", systemImage: "pawprint.fill")
                .tag(SettingsTab.pet)
            Label("快捷工具", systemImage: "wand.and.stars")
                .tag(SettingsTab.quickTools)
            Label("AI 对话", systemImage: "message.fill")
                .tag(SettingsTab.ai)
            Label("专注", systemImage: "timer")
                .tag(SettingsTab.focus)
            Label("音乐", systemImage: "music.note")
                .tag(SettingsTab.music)
            Label("手帐本", systemImage: "book.closed.fill")
                .tag(SettingsTab.diary)
            Label("关于", systemImage: "info.circle.fill")
                .tag(SettingsTab.about)
        }
        .listStyle(.sidebar)
    }
}

struct SettingsDetailView: View {
    @ObservedObject var selection: SettingsSelectionModel
    let language: AppLanguageSettings
    let pet: PetStore
    let ai: AISettingsStore
    let loginItem: LoginItemStore
    let focusTimer: FocusTimerStore
    let music: MusicFeature
    let diary: DiaryFeature
    let externalAudioInterruption: ExternalAudioInterruptionController
    let quickTools: QuickToolsController
    let finderExtension: FinderExtensionController
    let updater: AppUpdateStore
    let guide: PetGuideCoordinator
    let showPet: () -> Void
    let restartOnboarding: () -> Void

    @ViewBuilder
    var body: some View {
        Group {
            switch selection.selectedTab {
            case .general:
                SettingsGeneralPage(
                    language: language,
                    ai: ai,
                    guide: guide,
                    restartOnboarding: restartOnboarding
                )
            case .pet:
                PetSettingsView(pet: pet, loginItem: loginItem, showPet: showPet)
            case .quickTools:
                QuickToolsSettingsView(
                    controller: quickTools,
                    settings: quickTools.settings,
                    finderExtension: finderExtension
                )
            case .ai:
                SettingsAIPage(ai: ai)
            case .focus:
                SettingsFocusPage(focusTimer: focusTimer, showPet: showPet)
            case .music:
                SettingsMusicPage(
                    music: music,
                    externalAudioInterruption: externalAudioInterruption
                )
            case .diary:
                DiaryBackupSettingsView(diary: diary)
            case .about:
                AboutUpdateView(updater: updater)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
