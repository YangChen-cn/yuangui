import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PetSpriteLayer: View {
    @ObservedObject var store: PetStore
    let music: MusicFeature
    let chatIsPresented: Bool
    let hasMaintenanceTask: Bool
    let focusState: FocusTimerStore.State
    let scale: CGFloat
    let panelWidth: CGFloat
    let displayedAction: PetAction
    let dockPreviewScale: CGFloat
    let dockPreviewOpacity: Double
    let dockPreviewRotation: Angle
    @Binding var dragStartOrigin: NSPoint?
    @Binding var dragStartMouseLocation: NSPoint?
    let updateAdaptiveControlSide: (PetPanel?) -> Void

    var body: some View {
        VStack(spacing: -12) {
            if let toast = store.toast {
                PetToastView(
                    message: toast,
                    maximumWidth: max(220, panelWidth - 24)
                )
                .transition(.scale(scale: 0.82).combined(with: .opacity))
                .zIndex(3)
            }

            AnimatedPetSprite(
                mode: store.mode,
                action: displayedAction,
                motionEnabled: store.isPetPresented,
                sequencePlaybackEnabled: store.petMotionEnabled
                    && (!displayedAction.file.contains("chatting") || store.ambientMessage != nil)
            )
            .overlay(alignment: .topTrailing) {
                PetMusicIndicatorView(
                    music: music,
                    isChatPresented: chatIsPresented,
                    hasMaintenanceTask: hasMaintenanceTask,
                    focusState: focusState,
                    scale: scale
                )
            }
            .frame(width: 326 * scale, height: 326 * scale)
            .shadow(color: .black.opacity(0.16), radius: 8, y: 5)
            .scaleEffect(dockPreviewScale)
            .rotationEffect(dockPreviewRotation)
            .opacity(dockPreviewOpacity)
            .contentShape(Rectangle())
            .onTapGesture { store.interact() }
            .simultaneousGesture(windowDragGesture)
            .onDrop(
                of: [UTType.fileURL.identifier],
                isTargeted: $store.isDropTargeted,
                perform: handleDrop
            )
        }
        .frame(maxWidth: .infinity)
        .offset(x: 35 * scale)
        .padding(.bottom, chatIsPresented ? PetLayout.chatPetBottomInset : 0)
    }

    private var windowDragGesture: some Gesture {
        DragGesture(minimumDistance: 7)
            .onChanged { _ in
                guard let window = NSApp.windows.first(where: { $0 is PetPanel }) as? PetPanel else { return }
                if dragStartOrigin == nil {
                    window.isUserDragging = true
                    dragStartOrigin = window.frame.origin
                    dragStartMouseLocation = NSEvent.mouseLocation
                }
                guard let origin = dragStartOrigin,
                      let mouseOrigin = dragStartMouseLocation else { return }
                let mouse = NSEvent.mouseLocation
                window.setFrameOrigin(NSPoint(
                    x: origin.x + mouse.x - mouseOrigin.x,
                    y: origin.y + mouse.y - mouseOrigin.y
                ))
                window.dragMovedAction?()
                updateAdaptiveControlSide(window)
            }
            .onEnded { _ in
                if let window = NSApp.windows.first(where: { $0 is PetPanel }) as? PetPanel {
                    window.isUserDragging = false
                    updateAdaptiveControlSide(window)
                    window.dragEndedAction?()
                }
                dragStartOrigin = nil
                dragStartMouseLocation = nil
            }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let matching = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !matching.isEmpty else { return false }

        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        for provider in matching {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                let url: URL?
                if let itemURL = item as? URL {
                    url = itemURL
                } else if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let itemURL = item as? NSURL {
                    url = itemURL as URL
                } else {
                    url = nil
                }
                guard let url else { return }
                lock.lock()
                urls.append(url)
                lock.unlock()
            }
        }
        group.notify(queue: .main) { self.store.recycle(urls) }
        return true
    }
}
