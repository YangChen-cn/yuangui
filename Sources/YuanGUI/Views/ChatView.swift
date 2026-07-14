import SwiftUI

struct ChatView: View {
    @ObservedObject var chat: ChatStore
    @ObservedObject var pet: PetStore
    let openSettings: () -> Void
    let close: () -> Void
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.45)
            messages
            composer
        }
        .frame(width: 420, height: 430)
        .background(.regularMaterial)
        .onAppear { inputFocused = true }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: pet.mode == .vcc ? "cat.fill" : "heart.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.pink)
            VStack(alignment: .leading, spacing: 1) {
                Text("和元圭、VCC 聊聊")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Text(chat.settings.model)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: openSettings) { Image(systemName: "gearshape") }
                .buttonStyle(.borderless)
                .help("AI 设置")
            Button(action: close) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("关闭")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if chat.messages.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "bubble.left.and.sparkles")
                                .font(.system(size: 32))
                                .foregroundStyle(.pink.opacity(0.8))
                            Text("想聊什么？元圭和 VCC 都在～")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                            Text("可以聊天、问问题，也可以让我们陪你休息一下。")
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 64)
                    }
                    ForEach(chat.messages) { message in
                        ChatBubble(message: message).id(message.id)
                    }
                    if chat.isSending {
                        HStack(spacing: 7) {
                            ProgressView().controlSize(.small)
                            Text("元圭和 VCC 正在想…")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                    if let error = chat.errorMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle.fill")
                            Text(error).textSelection(.enabled)
                            Spacer()
                        }
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.red)
                        .padding(9)
                        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(14)
            }
            .onChange(of: chat.messages.count) {
                if let id = chat.messages.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("输入想说的话…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .focused($inputFocused)
                .onSubmit(send)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 26))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.pink)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chat.isSending)
        }
        .padding(12)
        .overlay(alignment: .top) { Divider().opacity(0.45) }
    }

    private func send() {
        let text = draft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        draft = ""
        Task { await chat.send(text, petMode: pet.mode) }
    }
}

private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 56) }
            Text(message.content)
                .font(.system(size: 11.5, weight: .regular, design: .rounded))
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    message.role == .user ? Color.accentColor.opacity(0.16) : Color.pink.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
            if message.role == .assistant { Spacer(minLength: 56) }
        }
    }
}
