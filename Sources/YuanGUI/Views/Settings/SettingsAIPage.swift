import SwiftUI

struct SettingsAIPage: View {
    @ObservedObject var ai: AISettingsStore
    @State private var promptEditorState: PromptEditorState?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsPageHeader(
                title: AppLocalizer.string("AI 对话"),
                subtitle: AppLocalizer.string("配置兼容服务与角色设定，支持流式回复"),
                systemImage: "message.fill",
                accent: .pink
            )
            Form {
                TextField("API 基础地址", text: Binding(
                    get: { ai.baseURL },
                    set: ai.updateBaseURL
                ))
                SecureField("API Key（保存在本机，仅当前用户可读）", text: Binding(
                    get: { ai.apiKey },
                    set: ai.updateAPIKey
                ))
                HStack {
                    if ai.isConnecting {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在读取模型…")
                            .foregroundStyle(.secondary)
                    } else if let message = ai.connectionMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(ai.availableModels.isEmpty ? .orange : .green)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button("连接并读取模型") {
                        Task { await ai.connectAndLoadModels() }
                    }
                    .disabled(
                        ai.isConnecting
                            || ai.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || ai.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
                if !ai.availableModels.isEmpty {
                    Picker("可用模型（\(ai.availableModels.count)）", selection: $ai.model) {
                        if !ai.model.isEmpty, !ai.availableModels.contains(ai.model) {
                            Text("手动：\(ai.model)").tag(ai.model)
                        }
                        ForEach(ai.availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .pickerStyle(.menu)
                    TextField("手动模型名", text: $ai.model)
                } else {
                    TextField("模型（可手动填写）", text: $ai.model)
                }
                Button("查看或编辑角色提示词…") {
                    promptEditorState = PromptEditorState(prompt: ai.systemPrompt)
                }
            }
            .formStyle(.grouped)
            HStack {
                Button("恢复 MiMo 默认值", action: ai.resetDefaults)
                if let message = ai.saveMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button("保存", action: ai.save)
                    .keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(.borderedProminent)
            }
        }
        .sheet(item: $promptEditorState) { state in
            PromptEditorSheet(
                initialPrompt: state.prompt,
                defaultPrompt: AISettingsStore.defaultPrompt(for: ai.promptLanguage)
            ) { updatedPrompt in
                ai.systemPrompt = updatedPrompt
            }
        }
    }
}

struct PromptEditorState: Identifiable {
    let id = UUID()
    let prompt: String
}

struct PromptEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String
    let defaultPrompt: String
    let apply: (String) -> Void

    init(initialPrompt: String, defaultPrompt: String, apply: @escaping (String) -> Void) {
        _draft = State(initialValue: initialPrompt)
        self.defaultPrompt = defaultPrompt
        self.apply = apply
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("角色提示词", systemImage: "text.quote")
                .font(.title3.bold())
            Text("修改会先应用到当前设置，点击主设置页的“保存”后才会持久保存。")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $draft)
                .font(.system(size: 12, design: .rounded))
                .padding(8)
                .background(.quaternary.opacity(0.45), in: .rect(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.separator.opacity(0.5))
                }
            HStack {
                Button("恢复默认提示词") { draft = defaultPrompt }
                Spacer()
                Button("取消", role: .cancel, action: dismiss.callAsFunction)
                Button("应用") {
                    apply(draft)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560, height: 410)
    }
}
