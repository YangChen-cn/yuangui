import AppKit
import SwiftUI

struct PetRootView: View {
    let window: PetPanel
    let store: PetStore
    let chat: ChatStore
    let chatPresentation: ChatPresentationCoordinator
    let maintenance: MaintenanceStore
    let focusTimer: FocusTimerStore
    let music: MusicFeature
    let guide: PetGuideCoordinator
    let auxiliaryBubblePresentation: PetAuxiliaryBubblePresentation

    var body: some View {
        PetSceneRoot(
            window: window,
            store: store,
            chat: chat,
            chatPresentation: chatPresentation,
            maintenance: maintenance,
            focusTimer: focusTimer,
            music: music,
            guide: guide,
            auxiliaryBubblePresentation: auxiliaryBubblePresentation
        )
    }
}

private struct PetSceneRoot: View {
    let window: PetPanel
    let store: PetStore
    let chat: ChatStore
    let chatPresentation: ChatPresentationCoordinator
    let maintenance: MaintenanceStore
    let focusTimer: FocusTimerStore
    let music: MusicFeature
    let guide: PetGuideCoordinator
    let auxiliaryBubblePresentation: PetAuxiliaryBubblePresentation

    @Environment(\.appActions) private var appActions

    var body: some View {
        PetSceneInteractiveLayer(
            window: window,
            store: store,
            chat: chat,
            chatPresentation: chatPresentation,
            maintenance: maintenance,
            focusTimer: focusTimer,
            music: music,
            auxiliaryBubblePresentation: auxiliaryBubblePresentation
        )
        .contextMenu { contextMenu }
    }

    /// The pet is the entry point to the whole app: the top section runs
    /// existing tools directly, followed by the pet's own behaviors.
    @ViewBuilder
    private var contextMenu: some View {
        Button(AppLocalizer.string("pet.menu.screenshot")) { appActions.runQuickTool(.regionScreenshot) }
        Button(AppLocalizer.string("pet.menu.screenshotTranslation")) { appActions.runQuickTool(.screenshotTranslation) }
        Button(AppLocalizer.string("pet.menu.translateSelection")) { appActions.runQuickTool(.translateSelection) }
        Divider()
        Menu("番茄钟") {
            switch focusTimer.state {
            case .idle, .completed:
                Button("开始 \(focusTimer.durationMinutes) 分钟专注") { focusTimer.start() }
                Divider()
                Button("15 分钟") { focusTimer.start(minutes: 15) }
                Button("25 分钟") { focusTimer.start(minutes: 25) }
                Button("45 分钟") { focusTimer.start(minutes: 45) }
                Button("60 分钟") { focusTimer.start(minutes: 60) }
            case .running:
                Button("暂停（剩余 \(focusTimer.timeText)）") { focusTimer.pause() }
                Button("提前结束") { focusTimer.stop() }
            case .paused:
                Button("继续（剩余 \(focusTimer.timeText)）") { focusTimer.resume() }
                Button("提前结束") { focusTimer.stop() }
            }
        }
        Menu("音乐") {
            Button("打开完整播放器…") { appActions.open(.music) }
            Button(music.playback.isPlaying ? "暂停" : "播放") { music.playPause() }
            Button("上一首") { music.previous() }
            Button("下一首") { music.next() }
            Divider()
            Button(music.lyricsPresentation.isVisible ? "隐藏桌面歌词" : "显示桌面歌词") {
                music.toggleLyricsVisible()
            }
        }
        Button(AppLocalizer.string("pet.menu.diary")) { appActions.open(.diary) }
        Button(AppLocalizer.string("pet.menu.finderExtension")) { appActions.open(.finderExtension) }
        Divider()
        Button(AppLocalizer.string("pet.menu.guide")) { guide.restartOnboarding() }
        Button(AppLocalizer.string("pet.menu.settings")) { appActions.open(.settings(.pet)) }
        Divider()
        Button(chat.isPresented ? "收起 AI 对话" : "和元圭、VCC 聊天…") { appActions.open(.chat) }
        Button("打开完整监控") { appActions.open(.statusDashboard) }
        Button("打开清理屋…") { appActions.open(.maintenance(tab: 0)) }
        Button(store.shouldShowPetBubble ? "隐藏系统状态" : "显示系统状态") {
            store.toggleSystemStatus()
        }
        Button(store.desktopIconsVisible ? "隐藏桌面图标" : "显示桌面图标") {
            store.toggleDesktopIcons()
        }
        Menu("切换角色") {
            ForEach(PetMode.allCases) { mode in
                Button(mode.title) { store.setMode(mode) }
            }
        }
        Menu("桌宠大小") {
            Button("迷你（50%）") { store.setPetScale(0.50) }
            Button("轻巧（60%）") { store.setPetScale(0.60) }
            Button("默认（75%）") { store.setPetScale(PetLayout.defaultScale) }
            Button("舒展（90%）") { store.setPetScale(0.90) }
            Button("大只（125%）") { store.setPetScale(1.25) }
            Button("超大（140%）") { store.setPetScale(1.40) }
        }
        Toggle("智能状态动作", isOn: Binding(
            get: { store.smartReactionsEnabled },
            set: { store.setSmartReactionsEnabled($0) }
        ))
        Button(store.interactionLocked ? "解锁桌宠点击" : "锁定并允许点击穿透") {
            store.toggleInteractionLock()
        }
        Divider()
        Button("打开废纸篓") { store.openTrash() }
        Button("清空废纸篓…") { store.confirmAndEmptyTrash() }
        Divider()
        Button("退出元圭与 VCC") { NSApp.terminate(nil) }
    }
}

struct PetChatLayer: View {
    @ObservedObject var chat: ChatStore
    @ObservedObject var pet: PetStore
    @ObservedObject var presentation: ChatPresentationCoordinator
    @ObservedObject var maintenance: MaintenanceStore
    let reduceMotion: Bool

    @ViewBuilder
    var body: some View {
        let scale = CGFloat(pet.petScale)
        if presentation.showsChatLayer {
            ZStack(alignment: .bottom) {
                if chat.latestReply != nil || chat.isSending || chat.errorMessage != nil {
                    PetReplyBubble(chat: chat, pet: pet)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 291 * scale + PetLayout.chatPetBottomInset + 4)
                        .zIndex(4)
                }

                if maintenance.quickMode == nil {
                    PetChatComposer(chat: chat, pet: pet)
                        .padding(.bottom, 3)
                        .zIndex(5)
                }
            }
            .opacity(presentation.showsChatContent ? 1 : 0)
            .scaleEffect(
                presentation.showsChatContent ? 1 : 0.97,
                anchor: .bottom
            )
            .animation(
                reduceMotion
                    ? nil
                    : .easeOut(duration: ChatPresentationCoordinator.contentAnimationDuration),
                value: presentation.showsChatContent
            )
        }
    }
}
