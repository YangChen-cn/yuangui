import SwiftUI

struct ChatHistoryView: View {
    @ObservedObject var chat: ChatStore
    @State private var pendingDelete: UUID?

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text("对话历史").font(.title2.bold())
                    Spacer()
                    Button { chat.newSession() } label: { Image(systemName: "square.and.pencil") }
                        .help("新建对话")
                }
                .padding()
                List(selection: Binding(
                    get: { chat.currentSessionID },
                    set: { if let id = $0 { chat.selectSession(id) } }
                )) {
                    ForEach(chat.sessions) { session in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.title).font(.headline).lineLimit(1)
                            Text(session.updatedAt, style: .relative)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(session.id)
                        .contextMenu {
                            Button("删除", role: .destructive) { pendingDelete = session.id }
                        }
                    }
                }
                HStack {
                    Button("清空全部…", role: .destructive) { confirmClear() }
                    Spacer()
                    Text("仅保存在本机").font(.caption).foregroundStyle(.secondary)
                }
                .padding(12)
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 230)
        } detail: {
            if let session = chat.currentSession {
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(session.title).font(.title2.bold())
                            Text("\(chat.messageCount(for: session.id)) 条消息")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("继续对话") { chat.present() }
                            .buttonStyle(.borderedProminent).tint(.pink)
                    }
                    .padding()
                    Divider()
                    if chat.isLoadingSession {
                        ProgressView("正在读取这段对话…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(session.messages) { message in
                                historyBubble(message)
                            }
                        }
                        .padding()
                    }
                    }
                }
            } else {
                ContentUnavailableView("还没有对话", systemImage: "bubble.left.and.bubble.right", description: Text("和元圭、VCC 说句话吧～"))
            }
        }
        .alert("删除这段对话？", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("删除", role: .destructive) {
                if let id = pendingDelete { chat.deleteSession(id) }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        }
    }

    private func historyBubble(_ message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: message.role == .user ? "person.crop.circle.fill" : "heart.circle.fill")
                Text(message.role == .user ? "master" : "元圭与 VCC").font(.caption.bold())
                Spacer()
                Text(message.createdAt, style: .time).font(.caption2).foregroundStyle(.secondary)
            }
            Text(message.content).textSelection(.enabled)
            if !message.attachments.isEmpty {
                ForEach(message.attachments) { attachment in
                    Label(attachment.name, systemImage: attachment.kind == .image ? "photo" : "doc.text")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(message.role == .user ? Color.blue.opacity(0.10) : Color.pink.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
    }

    private func confirmClear() {
        let alert = NSAlert()
        alert.messageText = "清空全部对话历史？"
        alert.informativeText = "此操作无法撤销，但不会删除你的 API Key。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn { chat.clearHistory() }
    }
}
