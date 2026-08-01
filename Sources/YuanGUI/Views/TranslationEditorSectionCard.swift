import SwiftUI

struct TranslationEditorSectionCard<Header: View, Content: View>: View {
    let role: TranslationMascotRole
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            content
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(role.accent.opacity(0.075), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(role.accent.opacity(0.16), lineWidth: 0.8)
        }
    }
}
