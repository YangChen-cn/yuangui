import SwiftUI

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
        .background(
            LinearGradient(
                colors: [.pink.opacity(0.19), .purple.opacity(0.13), .blue.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 23, style: .continuous)
        )
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .stroke(
                    LinearGradient(colors: [.white.opacity(0.75), .pink.opacity(0.28)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.9
                )
        }
        .shadow(color: .pink.opacity(0.20), radius: 17, y: 7)
        .overlay(alignment: .bottom) {
            ReplyBubbleTail()
                .fill(.regularMaterial)
                .frame(width: 25, height: 13)
                .offset(x: 92, y: 9)
        }
    }

    private var replyContentHeight: CGFloat {
        if chat.isSending || chat.errorMessage != nil { return 28 }
        let count = chat.latestReply?.count ?? 0
        let estimatedLines = max(1, Int(ceil(Double(count) / 32.0)))
        return min(max(CGFloat(estimatedLines) * 18, 28), 92)
    }

    @ViewBuilder
    private var replyContent: some View {
        if chat.isSending {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在认真想怎么回复你…")
                    .foregroundStyle(.secondary)
            }
        } else if let error = chat.errorMessage {
            Label(error, systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .textSelection(.enabled)
        } else if let reply = chat.latestReply {
            Text(reply)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct PetChatComposer: View {
    @ObservedObject var chat: ChatStore
    @ObservedObject var pet: PetStore
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left.and.sparkles.fill")
                .foregroundStyle(.pink)
                .font(.system(size: 15, weight: .semibold))

            TextField("直接和我们说话…", text: $draft)
                .textFieldStyle(.plain)
                .focused($inputFocused)
                .onSubmit(send)

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.pink)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chat.isSending)

            Divider().frame(height: 20)

            Button { pet.showSettings() } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless)
                .help("AI 设置")
            Button { chat.dismiss() } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("收起对话")
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .frame(width: 426)
        .background(.ultraThinMaterial, in: Capsule())
        .background(
            LinearGradient(colors: [.white.opacity(0.38), .pink.opacity(0.11)], startPoint: .top, endPoint: .bottom),
            in: Capsule()
        )
        .overlay(Capsule().stroke(.white.opacity(0.64), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.13), radius: 13, y: 5)
        .onAppear { inputFocused = true }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        Task { await chat.send(text, petMode: pet.mode) }
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
