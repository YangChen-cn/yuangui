import SwiftUI

/// 快速记录弹窗
struct QuickDiaryEntryView: View {
    @ObservedObject var store: DiaryFeature
    let onSaved: () -> Void

    @State private var entryBody: String = ""
    @State private var mood: DiaryMood? = nil
    @State private var tagText: String = ""
    @State private var tags: [String] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题栏
            HStack {
                Text("记录这一刻")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // 心情
            MoodPickerView(selectedMood: $mood)

            // 正文
            TextEditor(text: $entryBody)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 100)
                .overlay(
                    Group {
                        if entryBody.isEmpty {
                            Text("今天发生了什么…")
                                .font(.system(size: 13))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }
                    },
                    alignment: .topLeading
                )

            // 标签
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    HStack(spacing: 3) {
                        Text("#\(tag)")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                        Button { tags.removeAll { $0 == tag } } label: {
                            Image(systemName: "xmark").font(.system(size: 7, weight: .bold))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.pink.opacity(0.1), in: Capsule())
                }
                TextField("标签", text: $tagText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .frame(width: 60)
                    .onSubmit { addTag() }
            }

            // 保存按钮
            HStack {
                Spacer()
                Button("保存") { save() }
                    .buttonStyle(.borderedProminent)
                    .tint(.pink)
                    .disabled(entryBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 360, height: 320)
    }

    private func addTag() {
        let tag = tagText.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty, !tags.contains(tag) else { return }
        tags.append(tag)
        tagText = ""
    }

    private func save() {
        var entry = store.createEntry()
        entry.body = entryBody
        entry.mood = mood
        entry.tags = tags
        store.updateEntry(entry)
        onSaved()
        dismiss()
    }
}
