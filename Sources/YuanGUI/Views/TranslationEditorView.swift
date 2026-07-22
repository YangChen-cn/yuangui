import SwiftUI
import Translation

struct TranslationEditorView: View {
    @ObservedObject var store: TranslationEditorStore
    let close: () -> Void
    @State private var configuration: TranslationSession.Configuration?
    @FocusState private var sourceIsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            sourceSection
            resultSection
            footer
        }
        .padding(12)
        .frame(minWidth: 400, idealWidth: 440, minHeight: 300, idealHeight: 352)
        .background(.regularMaterial)
        .onAppear {
            DispatchQueue.main.async { sourceIsFocused = true }
        }
        .task(id: translationRequestID) {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await requestTranslation()
        }
        .translationTask(configuration) { session in
            await store.performTranslation(using: session)
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.pink)
                Text("元圭与 VCC 翻译小屋")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            HStack {
                Label(store.engineTitle, systemImage: "translate")
                    .font(.subheadline.weight(.semibold))
                Text("来自 \(store.sourceApplicationName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Picker("目标语言", selection: Binding(
                    get: { store.targetLanguage },
                    set: store.requestTargetLanguage
                )) {
                    ForEach(QuickToolLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                .labelsHidden()
                .frame(width: 118)
            }
        }
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("原文").font(.subheadline.bold())
                if let language = store.detectedSourceLanguage {
                    Text(language).font(.caption).foregroundStyle(.secondary)
                }
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: Binding(
                    get: { store.editableSourceText },
                    set: store.updateEditableSourceText
                ))
                .font(.body)
                .padding(6)
                .scrollContentBackground(.hidden)
                .focused($sourceIsFocused)
                if store.editableSourceText.isEmpty {
                    Text("输入要翻译的文字…")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 64, maxHeight: 90)
            .background(.background.opacity(0.75), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(.separator.opacity(0.45)))
        }
    }

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("译文").font(.subheadline.bold())
                Spacer()
                if store.state == .translating {
                    ProgressView().controlSize(.small)
                    Text("正在翻译…").font(.caption).foregroundStyle(.secondary)
                }
            }
            ScrollView {
                Text(store.translatedText.isEmpty ? "等待翻译…" : store.translatedText)
                    .textSelection(.enabled)
                    .foregroundStyle(store.translatedText.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(minHeight: 68, maxHeight: 96)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 9))
            if case let .failed(message) = store.state {
                HStack {
                    Text(message).font(.caption).foregroundStyle(.red)
                    Spacer()
                    if store.canInstallShortcut {
                        Button("添加快捷指令", action: store.installShortcut)
                    }
                    Button("重试") { Task { await requestTranslation() } }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let message = store.message {
                Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            if !store.targetSnapshot.canReplace {
                Text(store.replacementHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("关闭", action: close).controlSize(.small).keyboardShortcut(.cancelAction)
            Button("复制") { store.copyTranslation() }
                .controlSize(.small)
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(store.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("替换原文") { Task { await store.replaceOriginal() } }
                .controlSize(.small)
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!store.canReplace)
                .help(store.targetSnapshot.canReplace ? "把最新译文写回原应用的原选区" : "原位置不可编辑")
        }
    }

    private func refreshConfiguration() {
        var newConfiguration = TranslationSession.Configuration(
            source: nil,
            target: Locale.Language(identifier: store.targetLanguage.rawValue)
        )
        newConfiguration.invalidate()
        configuration = newConfiguration
    }

    private func requestTranslation() async {
        if store.usesShortcutTranslation {
            configuration = nil
            await store.performShortcutTranslation()
        } else if store.usesOnlineTranslation {
            configuration = nil
            await store.performOnlineTranslation()
        } else {
            refreshConfiguration()
        }
    }

    private var translationRequestID: String {
        store.targetLanguage.rawValue + "\u{0}" + store.editableSourceText
    }
}
