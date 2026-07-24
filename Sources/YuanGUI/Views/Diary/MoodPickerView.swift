import SwiftUI

/// 心情选择器
struct MoodPickerView: View {
    @Binding var selectedMood: DiaryMood?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(DiaryMood.allCases, id: \.self) { mood in
                    Button {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: DiaryDesign.animationDuration)) {
                            selectedMood = selectedMood == mood ? nil : mood
                        }
                    } label: {
                        ZStack(alignment: .bottomTrailing) {
                            Text(mood.emoji)
                                .font(.system(size: 19))
                                .frame(width: 32, height: 32)
                                .background(
                                    selectedMood == mood ? Color.diarySelection : Color.clear,
                                    in: RoundedRectangle(cornerRadius: DiaryDesign.smallCornerRadius, style: .continuous)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: DiaryDesign.smallCornerRadius, style: .continuous)
                                        .stroke(selectedMood == mood ? Color.diaryAccent.opacity(0.55) : Color.clear, lineWidth: 1)
                                }
                            if selectedMood == mood {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Color.diaryAccent, .background)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help(mood.title)
                    .accessibilityLabel(mood.title)
                    .accessibilityAddTraits(selectedMood == mood ? .isSelected : [])
                }
            }
        }
    }
}
