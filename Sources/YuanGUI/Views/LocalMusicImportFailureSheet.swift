import SwiftUI

struct LocalMusicImportFailureSheet: View {
    let failures: [LocalMusicImportFailure]
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(
                AppLocalizer.string("music.local.import.failures.title"),
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.title3.bold())
            .foregroundStyle(.orange)

            Text(AppLocalizer.format("music.local.import.failures.count", failures.count))
                .foregroundStyle(.secondary)

            List {
                ForEach(Array(failures.enumerated()), id: \.offset) { _, failure in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(failure.filename)
                            .bold()
                            .textSelection(.enabled)
                        Text(failure.message)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 4)
                }
            }

            HStack {
                Spacer()
                Button(AppLocalizer.string("完成")) {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 360)
    }
}
