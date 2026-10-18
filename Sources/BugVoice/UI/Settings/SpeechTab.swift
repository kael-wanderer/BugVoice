import BugVoiceMac
import SwiftUI
import VoiceCore
import WhisperEngine

struct SpeechTab: View {
    @Bindable var model: AppModel
    @State private var devices: [AudioInputDevice] = []

    static let whisperModels = [
        ("large-v3-v20240930_turbo", "large-v3-turbo · 1.6 GB"),
        ("large-v3", "large-v3 · 3.1 GB"),
        ("small", "small · 0.5 GB"),
    ]

    var body: some View {
        SettingsScroll {
            SettingsCard {
                SettingsRow(title: "Engine") {
                    Picker("Engine", selection: $model.settings.speech.engine) {
                        Text("WhisperKit (on device)").tag(SpeechEngine.whisperKit)
                        Text("OpenAI-compatible server").tag(SpeechEngine.openAICompatible)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                Divider()
                if model.settings.speech.engine == .whisperKit {
                    SettingsRow(title: "Model") {
                        Text(stateText).foregroundStyle(.bvSecondary)
                        Picker("Model", selection: $model.settings.speech.whisperModel) {
                            ForEach(Self.whisperModels, id: \.0) { Text($0.1).tag($0.0) }
                        }
                        .labelsHidden().fixedSize()
                    }
                } else {
                    SettingsRow(title: "Base URL") {
                        TextField("Base URL", text: $model.settings.speech.serverBaseURL)
                            .textFieldStyle(.roundedBorder).labelsHidden().frame(maxWidth: 360)
                    }
                    SettingsRow(title: "Model") {
                        TextField("Model", text: $model.settings.speech.serverModel)
                            .textFieldStyle(.roundedBorder).labelsHidden().frame(maxWidth: 360)
                    }
                    SettingsRow(title: "API key") {
                        KeyField(model: model, title: "Paste the key", account: "speech-openai")
                            .textFieldStyle(.roundedBorder).frame(maxWidth: 360)
                    }
                }
            }
            SettingsCard {
                SettingsRow(title: "Language") {
                    Picker("Language", selection: $model.settings.speech.language) {
                        Text("Auto").tag(SpeechLanguage.auto)
                        Text("Vietnamese").tag(SpeechLanguage.vi)
                        Text("English").tag(SpeechLanguage.en)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                Divider()
                SettingsToggle(title: "Use Dictionary words as hints", isOn: $model.settings.speech.useVocabularyHints)
                Divider()
                SettingsRow(title: "Microphone") {
                    Picker("Microphone", selection: $model.settings.speech.microphoneUID) {
                        Text("System default").tag(String?.none)
                        ForEach(devices) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .labelsHidden().fixedSize()
                }
            }
        }
        .task {
            devices = AudioDevices.inputs()
            await model.refreshSpeechState()
        }
    }

    var stateText: String {
        switch model.speechState {
        case .notLoaded: "Not loaded"
        case .downloading(let p): "Downloading \(Int(p * 100))%"
        case .loading: "Loading…"
        case .ready: "Ready"
        case .failed(let message): "Failed: \(message)"
        }
    }
}
