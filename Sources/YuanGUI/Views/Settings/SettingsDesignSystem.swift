import SwiftUI

enum SettingsDesign {
    static let pageSpacing: CGFloat = 14
    static let sectionSpacing: CGFloat = 12
    static let compactSpacing: CGFloat = 8
    static let sectionRadius: CGFloat = 12
    static let pagePadding: CGFloat = 2
}

struct SettingsPageHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var accent: Color = .accentColor

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(accent)
                .frame(width: 42, height: 42)
                .background(accent.opacity(0.12), in: .rect(cornerRadius: 11))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3)
                    .bold()
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
    }
}

struct SettingsSectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsDesign.sectionSpacing) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.secondary)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: .rect(cornerRadius: SettingsDesign.sectionRadius))
    }
}
