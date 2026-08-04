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

    var body: some View {
        PetSceneInteractiveLayer(
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
