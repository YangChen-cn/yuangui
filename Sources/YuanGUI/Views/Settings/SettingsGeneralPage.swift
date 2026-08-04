import SwiftUI

struct SettingsGeneralPage: View {
    @ObservedObject var language: AppLanguageSettings
    @ObservedObject var ai: AISettingsStore
    @ObservedObject var guide: PetGuideCoordinator
    var restartOnboarding: () -> Void = {}

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
                Section(AppLocalizer.string("settings.guide")) {
                    Text(AppLocalizer.string("settings.guide.subtitle"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(AppLocalizer.string("settings.guide.restart")) {
                        restartOnboarding()
                    }
                    Toggle(AppLocalizer.string("settings.featureTips"), isOn: Binding(
                        get: { guide.featureTipsEnabled },
                        set: { guide.setFeatureTipsEnabled($0) }
                    ))
                    Text(AppLocalizer.string("settings.featureTips.subtitle"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
    }
}
