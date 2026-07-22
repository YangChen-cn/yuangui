import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PetReplyBubble: View {
    @ObservedObject var chat: ChatStore
    @ObservedObject var pet: PetStore

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(.pink.opacity(0.15))
                Image(systemName: pet.mode == .vcc ? "cat.fill" : "heart.fill")
                    .foregroundStyle(.pink)
            }
            .frame(width: 28, height: 28)

            ScrollView {
                replyContent
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: replyContentHeight)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 410)
        .foregroundStyle(.primary)
        .background(
            Color(nsColor: .windowBackgroundColor).opacity(0.96),
            in: RoundedRectangle(cornerRadius: 23, style: .continuous)
        )
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
        .background(
            LinearGradient(
                colors: [.pink.opacity(0.12), .purple.opacity(0.07), .blue.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 23, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .stroke(
                    LinearGradient(colors: [.white.opacity(0.55), .pink.opacity(0.32)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.9
                )
        }
        .shadow(color: .pink.opacity(0.20), radius: 17, y: 7)
        .overlay(alignment: .bottom) {
            ReplyBubbleTail()
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))
                .frame(width: 25, height: 13)
                .offset(x: 92, y: 9)
        }
    }

    private var replyContentHeight: CGFloat {
        if chat.errorMessage != nil { return 28 }
        let count = chat.latestReply?.count ?? 0
        let estimatedLines = max(1, Int(ceil(Double(count) / 32.0)))
        return min(max(CGFloat(estimatedLines) * 18, 28), 92)
    }

    @ViewBuilder
    private var replyContent: some View {
        if let error = chat.errorMessage {
            Label(error, systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .textSelection(.enabled)
        } else if let reply = chat.latestReply, !reply.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(reply)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if chat.isSending {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("正在继续生成…")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else if chat.isSending {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在认真想怎么回复你…")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct PetChatComposer: View {
    @ObservedObject var chat: ChatStore
    @ObservedObject var pet: PetStore
    @State private var draft = ""
    @State private var attachments: [PreparedChatAttachment] = []
    @State private var attachmentError: String?
    @FocusState private var inputFocused: Bool
    private let preparer: AttachmentPreparing = AttachmentPreparer()

    var body: some View {
        VStack(spacing: 7) {
            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(attachments) { attachment in
                            HStack(spacing: 5) {
                                Image(systemName: attachment.metadata.kind == .image ? "photo.fill" : "doc.text.fill")
                                Text(attachment.metadata.name).lineLimit(1)
                                Button { attachments.removeAll { $0.id == attachment.id } } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .buttonStyle(.plain)
                            }
                            .font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(.pink.opacity(0.11), in: Capsule())
                        }
                    }
                }
                Text("附件内容会发送给当前 AI 服务商，但原文件不会保存到历史")
                    .font(.system(size: 9, design: .rounded)).foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button(action: chooseAttachments) {
                    Image(systemName: "paperclip.circle.fill").font(.system(size: 19))
                }
                .buttonStyle(.plain).foregroundStyle(.pink).help("添加图片或文件")

                TextField("直接和我们说话…", text: $draft)
                    .textFieldStyle(.plain)
                    .focused($inputFocused)
                    .onSubmit(send)
                    .onPasteCommand(of: [.image]) { providers in
                        pasteImages(providers)
                    }
                    .background {
                        ChatImagePasteMonitor(isEnabled: inputFocused) { images in
                            addPastedImages(images)
                        }
                        .allowsHitTesting(false)
                    }

                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 22))
                }
                .buttonStyle(.borderless).foregroundStyle(.pink)
                .disabled((draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty) || chat.isSending)

                Divider().frame(height: 20)
                Button { chat.showHistory() } label: { Image(systemName: "clock.arrow.circlepath") }
                    .buttonStyle(.borderless).help("对话历史")
                Button { pet.showSettings() } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.borderless).help("AI 设置")
                Button { chat.dismiss() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary).help("收起对话")
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .frame(width: 426)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .background(
            LinearGradient(colors: [.white.opacity(0.38), .pink.opacity(0.11)], startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.64), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.13), radius: 13, y: 5)
        .onAppear { inputFocused = true }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil, perform: handleDrop)
        .alert("附件无法添加", isPresented: Binding(
            get: { attachmentError != nil },
            set: { if !$0 { attachmentError = nil } }
        )) { Button("好") { attachmentError = nil } } message: { Text(attachmentError ?? "") }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachments.isEmpty else { return }
        let sendingAttachments = attachments
        draft = ""
        attachments = []
        Task { await chat.send(text, attachments: sendingAttachments, petMode: pet.mode) }
    }

    private func chooseAttachments() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image, .pdf, .plainText, .json, .commaSeparatedText, .sourceCode]
        guard panel.runModal() == .OK else { return }
        addAttachments(panel.urls)
    }

    private func addAttachments(_ urls: [URL]) {
        for url in urls.prefix(6) {
            do {
                let attachment = try preparer.prepare(url: url)
                if !attachments.contains(where: { $0.metadata.name == attachment.metadata.name }) {
                    attachments.append(attachment)
                }
            } catch {
                attachmentError = error.localizedDescription
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let providers = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !providers.isEmpty else { return false }
        for provider in providers.prefix(6) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let value = item as? URL { url = value }
                else if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                else { url = nil }
                guard let url else { return }
                DispatchQueue.main.async { addAttachments([url]) }
            }
        }
        return true
    }

    private func pasteImages(_ providers: [NSItemProvider]) {
        for provider in providers.prefix(max(0, 6 - attachments.count)) {
            guard let type = provider.registeredTypeIdentifiers.first(where: {
                guard let value = UTType($0) else { return false }
                return value.conforms(to: .image)
            }) else { continue }
            provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
                DispatchQueue.main.async {
                    do {
                        if let error { throw error }
                        guard let data else { throw ChatServiceError.unreadableAttachment("粘贴的图片") }
                        let name = "粘贴图片-\(attachments.count + 1).png"
                        attachments.append(try preparer.prepare(imageData: data, name: name))
                    } catch {
                        attachmentError = error.localizedDescription
                    }
                }
            }
        }
    }

    private func addPastedImages(_ images: [PastedChatImage]) {
        for image in images.prefix(max(0, 6 - attachments.count)) {
            do {
                let attachment: PreparedChatAttachment
                switch image.source {
                case .data(let data):
                    attachment = try preparer.prepare(imageData: data, name: image.suggestedName)
                case .fileURL(let url):
                    attachment = try preparer.prepare(url: url)
                }
                attachments.append(attachment)
            } catch {
                attachmentError = error.localizedDescription
            }
        }
    }
}

private struct ChatImagePasteMonitor: NSViewRepresentable {
    let isEnabled: Bool
    let onPasteImages: ([PastedChatImage]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isEnabled: isEnabled, onPasteImages: onPasteImages)
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.install()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onPasteImages = onPasteImages
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator {
        var isEnabled: Bool
        var onPasteImages: ([PastedChatImage]) -> Void
        private var eventMonitor: Any?

        init(isEnabled: Bool, onPasteImages: @escaping ([PastedChatImage]) -> Void) {
            self.isEnabled = isEnabled
            self.onPasteImages = onPasteImages
        }

        func install() {
            guard eventMonitor == nil else { return }
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self,
                      isEnabled,
                      !event.isARepeat,
                      event.charactersIgnoringModifiers?.lowercased() == "v" else {
                    return event
                }
                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                guard modifiers.contains(.command),
                      !modifiers.contains(.control),
                      !modifiers.contains(.option) else {
                    return event
                }
                let images = ChatPasteboardReader.images()
                guard !images.isEmpty else { return event }
                onPasteImages(images)
                return nil
            }
        }

        func uninstall() {
            guard let eventMonitor else { return }
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }
}

private struct ReplyBubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
