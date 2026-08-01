import SwiftUI

struct TranslationEditorHeaderView: View {
    let sourceApplicationName: String
    let engineTitle: String
    @Binding var targetLanguage: QuickToolLanguage

    var body: some View {
        HStack(spacing: 12) {
            TranslationMascotBadgeView(
                mode: .duo,
                accent: Color(red: 0.39, green: 0.55, blue: 0.91),
                size: 42
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(AppLocalizer.string("translation.mascot.title"))
                    .font(.title3)
                    .bold()
                HStack(spacing: 10) {
                    Label(sourceApplicationName, systemImage: "app.dashed")
                    Label(AppLocalizer.string(engineTitle), systemImage: "gearshape.2")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            Picker("目标语言", selection: $targetLanguage) {
                ForEach(QuickToolLanguage.allCases) { language in
                    Text(language.title).tag(language)
                }
            }
            .controlSize(.small)
            .frame(width: 132)
        }
    }
}
