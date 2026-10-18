import SwiftUI
import VoiceCore

enum SettingsTab: String, Hashable { case general, shortcuts, editing, theme, speech, models, agents, meetings, storage }

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing[3]) {
            Text("Settings").bvFont(.title2)
            PillTabs(
                items: [
                    .init(value: SettingsTab.general, title: "General"),
                    .init(value: SettingsTab.shortcuts, title: "Shortcuts"),
                    .init(value: SettingsTab.editing, title: "Editing"),
                    .init(value: SettingsTab.theme, title: "Theme & icons"),
                    .init(value: SettingsTab.speech, title: "Speech"),
                    .init(value: SettingsTab.models, title: "Models"),
                    .init(value: SettingsTab.agents, title: "Agents"),
                    .init(value: SettingsTab.meetings, title: "Meetings"),
                    .init(value: SettingsTab.storage, title: "Storage"),
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
