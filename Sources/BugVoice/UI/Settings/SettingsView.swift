import SwiftUI

enum SettingsTab: Hashable { case general, speech, models, meetings, storage }

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var tab: SettingsTab = .general

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings").font(.title2.weight(.semibold))
            PillTabs(
                items: [
                    .init(value: SettingsTab.general, title: "General"),
                    .init(value: SettingsTab.speech, title: "Speech"),
                    .init(value: SettingsTab.models, title: "Models"),
                    .init(value: SettingsTab.meetings, title: "Meetings"),
                    .init(value: SettingsTab.storage, title: "Storage"),
                ],
                selection: $tab
            )
            Group {
                switch tab {
                case .general: GeneralTab(model: model)
                case .speech: SpeechTab(model: model)
                case .models: ModelsTab(model: model)
                case .meetings: MeetingsTab(model: model)
                case .storage: StorageTab(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Settings")
    }
}
