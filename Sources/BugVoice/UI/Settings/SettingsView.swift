import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            GeneralTab(model: model).tabItem { Label("General", systemImage: "gearshape") }
            SpeechTab(model: model).tabItem { Label("Speech", systemImage: "mic") }
            TextModelTab(model: model).tabItem { Label("Text model", systemImage: "cpu") }
            MeetingsTab(model: model).tabItem { Label("Meetings", systemImage: "waveform.path") }
            StylesTab(model: model).tabItem { Label("Styles", systemImage: "text.alignleft") }
            VocabularyTab(model: model).tabItem { Label("Vocabulary", systemImage: "book") }
            StorageTab(model: model).tabItem { Label("Storage", systemImage: "internaldrive") }
        }
        .padding(20)
        .navigationTitle("Settings")
    }
}
