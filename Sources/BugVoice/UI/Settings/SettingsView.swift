import SwiftUI
import VoiceCore

enum SettingsTab: String, Hashable { case general, shortcuts, editing, theme, speech, models, agents, meetings, storage }

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[3]) {
            RoundPills("Settings section",
                items: [
                    (SettingsTab.general, "General"),
                    (SettingsTab.shortcuts, "Shortcuts"),
                    (SettingsTab.editing, "Editing"),
                    (SettingsTab.theme, "Theme & icons"),
                    (SettingsTab.speech, "Speech"),
                    (SettingsTab.models, "Models"),
                    (SettingsTab.agents, "Agents"),
                    (SettingsTab.meetings, "Meetings"),
                    (SettingsTab.storage, "Storage"),
                ],
                selection: $model.settingsTab
            )
            Group {
                switch model.settingsTab {
                case .general: GeneralTab(model: model)
                case .shortcuts: ShortcutsSettingsView(model: model)
                case .editing: EditingSettingsView(model: model)
                case .theme: ThemeSettingsView(model: model)
                case .speech: SpeechTab(model: model)
                case .models: ModelsTab(model: model)
                case .agents: AgentsSettings(model: model)
                case .meetings: MeetingsTab(model: model)
                case .storage: StorageTab(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(LayoutTokens.spacing[4])
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

    }
}
