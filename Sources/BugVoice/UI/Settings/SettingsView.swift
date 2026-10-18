import SwiftUI
import VoiceCore

enum SettingsTab: String, Hashable { case general, shortcuts, editing, theme, speech, models, agents, meetings, storage }

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: LayoutTokens.spacing[4]) {
                SectionList("Settings sections", groups: [
                    .init(title: nil, items: [(.general, "General"), (.shortcuts, "Shortcuts"), (.editing, "Editing"), (.theme, "Theme & icons")]),
                    .init(title: "Engine", items: [(.speech, "Speech"), (.models, "Models"), (.agents, "Agents"), (.meetings, "Meetings"), (.storage, "Storage")])
                ], selection: $model.settingsTab)
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
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
            .bvPageColumn(.sectioned)
        }
    }
}
