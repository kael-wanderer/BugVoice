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
        Form {
            Picker("Engine", selection: $model.settings.speech.engine) {
                Text("WhisperKit (on device)").tag(SpeechEngine.whisperKit)
                Text("OpenAI-compatible server").tag(SpeechEngine.openAICompatible)
            }
            .pickerStyle(.segmented)

            if model.settings.speech.engine == .whisperKit {
                LabeledContent("Model") {
                    HStack {
                        Picker("", selection: $model.settings.speech.whisperModel) {
                            ForEach(Self.whisperModels, id: \.0) { Text($0.1).tag($0.0) }
                        }
                        .labelsHidden()
                        Text(stateText).foregroundStyle(.secondary)
                    }
                }
            } else {
                TextField("Base URL", text: $model.settings.speech.serverBaseURL)
                TextField("Model", text: $model.settings.speech.serverModel)
                KeyField(model: model, title: "API key (stored in Keychain)", account: "speech-openai")
            }

            Picker("Language", selection: $model.settings.speech.language) {
                Text("Auto").tag(SpeechLanguage.auto)
                Text("Vietnamese").tag(SpeechLanguage.vi)
                Text("English").tag(SpeechLanguage.en)
            }
            .pickerStyle(.segmented)
            Toggle("Use vocabulary as hints", isOn: $model.settings.speech.useVocabularyHints)
            Picker("Microphone", selection: $model.settings.speech.microphoneUID) {
                Text("System default").tag(String?.none)
                ForEach(devices) { Text($0.name).tag(Optional($0.id)) }
            }
        }
        .formStyle(.grouped)
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
