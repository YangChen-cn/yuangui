import SwiftUI

struct TranslationEditorHeaderView: View {
    let sourceApplicationName: String
    let engineTitle: String
    @Binding var targetLanguage: QuickToolLanguage

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "translate")
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 38, height: 38)
                .background(.blue.opacity(0.11), in: .rect(cornerRadius: 10))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("划词翻译")
                    .font(.title3)
                    .bold()
                HStack(spacing: 10) {
                    Label(sourceApplicationName, systemImage: "app")
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
