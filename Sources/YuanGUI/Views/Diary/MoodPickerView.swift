import SwiftUI

/// 心情选择器
struct MoodPickerView: View {
    @Binding var selectedMood: DiaryMood?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(DiaryMood.allCases, id: \.self) { mood in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        selectedMood = selectedMood == mood ? nil : mood
                    }
                } label: {
                    Text(mood.emoji)
                        .font(.system(size: selectedMood == mood ? 22 : 18))
                        .frame(width: 32, height: 32)
                        .background(
                            selectedMood == mood
                                ? Color.pink.opacity(0.18)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(
                                    selectedMood == mood ? Color.pink.opacity(0.5) : Color.clear,
                                    lineWidth: 1.5
                                )
                        )
                }
                .buttonStyle(.plain)
                .help(mood.title)
            }
        }
    }
}
