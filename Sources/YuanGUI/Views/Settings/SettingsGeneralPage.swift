import SwiftUI

struct SettingsGeneralPage: View {
    @ObservedObject var language: AppLanguageSettings
    @ObservedObject var ai: AISettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsDesign.pageSpacing) {
            SettingsPageHeader(
                title: AppLocalizer.string("settings.general"),
                subtitle: AppLocalizer.string("settings.language.subtitle"),
                systemImage: "gearshape",
                accent: .blue
            )
            Form {
                Section(AppLocalizer.string("settings.language")) {
                    Picker(AppLocalizer.string("settings.language"), selection: Binding(
                        get: { language.language },
                        set: { selectedLanguage in
                            ai.updateDefaultPromptLanguage(selectedLanguage)
                            language.setLanguage(selectedLanguage)
                        }
                    )) {
                        ForEach(AppLanguage.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    Text(AppLocalizer.string("settings.language.subtitle"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section(AppLocalizer.string("settings.permissions")) {
                    Text(AppLocalizer.string("settings.permissions.subtitle"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
    }
}
