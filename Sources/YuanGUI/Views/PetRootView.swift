import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PetRootView: View {
    @ObservedObject var store: PetStore
    @ObservedObject var chat: ChatStore
    @State private var isHovering = false
    @State private var dragStartOrigin: NSPoint?
    @State private var dragStartMouseLocation: NSPoint?

    private var scale: CGFloat { store.petScale }
    private var panelSize: CGSize {
        PetLayout.panelSize(
            scale: store.petScale,
            showsBubble: store.shouldShowPetBubble,
            showsChat: chat.isPresented
        )
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if chat.isPresented {
                if chat.latestReply != nil || chat.isSending || chat.errorMessage != nil {
                    PetReplyBubble(chat: chat, pet: store)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 291 * scale + 62)
                        .zIndex(4)
                }
            } else if store.shouldShowPetBubble {
                PetStatusBubble(store: store)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 291 * scale + 4)
                    .zIndex(2)
            }

            VStack(spacing: -12) {
                if let toast = store.toast {
                    Text(toast)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 0.7))
                        .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
                        .transition(.scale(scale: 0.82).combined(with: .opacity))
                        .zIndex(3)
                }

                petImage
                    .frame(width: 326 * scale, height: 326 * scale)
                    .shadow(color: .black.opacity(0.20), radius: 14, y: 8)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        store.interact()
                    }
                    .simultaneousGesture(windowDragGesture)
                    .onDrop(of: [UTType.fileURL.identifier], isTargeted: $store.isDropTargeted) { providers in
                        handleDrop(providers)
                    }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, chat.isPresented ? 58 : 0)

            if chat.isPresented {
                PetChatComposer(chat: chat, pet: store)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 3)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(5)
            }

            if store.isDropTargeted {
                dropOverlay
                    .transition(.scale.combined(with: .opacity))
            }

            if isHovering && !store.isDropTargeted {
                controls
                    .padding(.bottom, chat.isPresented ? 64 : 5)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: panelSize.width, height: panelSize.height)
        .background(Color.clear)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.18)) { isHovering = hovering }
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.82), value: store.currentAction.id)
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: store.showsSystemStatus)
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: chat.isPresented)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: store.petScale)
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: store.smartState)
        .animation(.easeOut(duration: 0.18), value: store.toast)
        .contextMenu { contextMenu }
    }

    @ViewBuilder
    private var petImage: some View {
        if let image = SpriteLoader.image(mode: store.mode, action: store.currentAction) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .id("\(store.mode.rawValue)-\(store.currentAction.id)")
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
        } else {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 100))
                .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        HStack(spacing: 5) {
            ForEach(PetMode.allCases) { mode in
                Button { store.setMode(mode) } label: {
                    Text(mode.title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .buttonStyle(.bordered)
                .tint(store.mode == mode ? .pink : .secondary)
                .controlSize(.small)
            }
            Divider().frame(height: 18)
            Button { store.toggleSystemStatus() } label: {
                Image(systemName: store.showsSystemStatus
                      ? "gauge.with.dots.needle.67percent"
                      : "gauge.with.dots.needle.33percent")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("显示系统状态")
            Button { store.showChat() } label: {
                Image(systemName: "bubble.left.and.bubble.right")
            }
            .buttonStyle(.bordered)
            .tint(chat.isPresented ? .pink : .secondary)
            .controlSize(.small)
            .help(chat.isPresented ? "收起对话" : "和元圭、VCC 聊天")
            Menu {
                Button("缩小") { store.adjustPetScale(by: -0.1) }
                Button("恢复默认大小") { store.setPetScale(1) }
                Button("放大") { store.adjustPetScale(by: 0.1) }
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
            .help("调整桌宠大小")
        }
        .padding(6)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.3), lineWidth: 0.6))
        .shadow(color: .black.opacity(0.14), radius: 12, y: 5)
    }

    private var dropOverlay: some View {
        VStack(spacing: 10) {
            Image(systemName: "trash.circle.fill")
                .font(.system(size: 48, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .pink)
            Text("松手移入废纸篓")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: 278, height: 216)
        .background(.black.opacity(0.66), in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 32).stroke(.white.opacity(0.5), lineWidth: 1))
        .padding(.bottom, 58)
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button(chat.isPresented ? "收起 AI 对话" : "和元圭、VCC 聊天…") { store.showChat() }
        Button("打开完整监控") { store.showFullDashboard() }
        Button(store.showsSystemStatus ? "隐藏系统状态" : "显示系统状态") {
            store.toggleSystemStatus()
        }
        Menu("切换角色") {
            ForEach(PetMode.allCases) { mode in
                Button(mode.title) { store.setMode(mode) }
            }
        }
        Menu("桌宠大小") {
            Button("小巧（70%）") { store.setPetScale(0.70) }
            Button("默认（100%）") { store.setPetScale(1) }
            Button("大只（125%）") { store.setPetScale(1.25) }
            Button("超大（140%）") { store.setPetScale(1.40) }
        }
        Toggle("智能状态动作", isOn: Binding(
            get: { store.smartReactionsEnabled },
            set: { store.setSmartReactionsEnabled($0) }
        ))
        Button("设置…") { store.showSettings() }
        Divider()
        Button("打开废纸篓") { store.openTrash() }
        Button("清空废纸篓…") { store.confirmAndEmptyTrash() }
        Divider()
        Button("退出元圭与 VCC") { NSApp.terminate(nil) }
    }

    private var windowDragGesture: some Gesture {
        DragGesture(minimumDistance: 7)
            .onChanged { _ in
                guard let window = NSApp.windows.first(where: { $0 is PetPanel }) else { return }
                if dragStartOrigin == nil {
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
            }
            .onEnded { _ in
                dragStartOrigin = nil
                dragStartMouseLocation = nil
            }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let matching = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
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
        group.notify(queue: .main) { store.recycle(urls) }
        return true
    }
}
