import SwiftUI
import VoiceCore

enum SettingsTab: String, Hashable, CaseIterable {
    case general, shortcuts, editing, theme, speech, models, agents, meetings, storage

    var title: String {
        switch self {
        case .general: "General"
        case .shortcuts: "Shortcuts"
        case .editing: "Editing"
        case .theme: "Theme & icons"
        case .speech: "Speech"
        case .models: "Models"
        case .agents: "Agents"
        case .meetings: "Meetings"
        case .storage: "Storage"
        }
    }
}

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutTokens.spacing[3]) {
                RoundPills("Settings sections", items: SettingsTab.allCases.map { ($0, $0.title) }, selection: $model.settingsTab)
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
            .bvPageColumn(.wide)
        }
    }
}
