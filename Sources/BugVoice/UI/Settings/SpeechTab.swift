import BugVoiceMac
import SwiftUI
import VoiceCore
import WhisperEngine

struct SpeechTab: View {
    @Environment(AppearanceStore.self) private var store
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
                            .textFieldStyle(.roundedBorder).labelsHidden().frame(maxWidth: store.scaled(360))
                    }
                    SettingsRow(title: "Model") {
                        TextField("Model", text: $model.settings.speech.serverModel)
                            .textFieldStyle(.roundedBorder).labelsHidden().frame(maxWidth: store.scaled(360))
                    }
                    SettingsRow(title: "API key") {
                        KeyField(model: model, title: "Paste the key", account: "speech-openai")
                            .textFieldStyle(.roundedBorder).frame(maxWidth: store.scaled(360))
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
                Text("Auto uses the per-app list below, then detects the language. English or Vietnamese applies everywhere.")
                    .bvFont(.footnote).foregroundStyle(.bvSecondary)
                Divider()
                SettingsToggle(title: "Show language switch in menu", isOn: $model.settings.speech.showLanguageSwitch)
                Divider()
                SettingsRow(title: "Language key while recording") {
                    Picker("Language key while recording", selection: $model.settings.speech.languageKey) {
                        Text("Off").tag(LanguageKey.off)
                        Text("Shift").tag(LanguageKey.shift)
                        Text("Option").tag(LanguageKey.option)
                    }
                    .labelsHidden().fixedSize()
                }
                Text("Tap the key while speaking to change the language for that dictation: Auto, English, Vietnamese.")
                    .bvFont(.footnote).foregroundStyle(.bvSecondary)
                Divider()
                SettingsToggle(title: "Keep English words in Vietnamese", isOn: $model.settings.speech.keepEnglishWords)
                Text("Words like module, API and neuron stay in English. Add words you always say in English to the Dictionary.")
                    .bvFont(.footnote).foregroundStyle(.bvSecondary)
                Divider()
                SettingsToggle(title: "Learn from corrections", isOn: $model.settings.speech.learnFromCorrections)
                Text("After a paste, BugVoice reads the field back for a minute. When you fix a word, it suggests adding it to the Dictionary. Text stays on this Mac; only the changed words are kept.")
                    .bvFont(.footnote).foregroundStyle(.bvSecondary)
                Divider()
                SettingsToggle(title: "Use Dictionary words as hints", isOn: $model.settings.speech.useVocabularyHints)
                Divider()
                SettingsToggle(title: "Live preview", isOn: $model.settings.speech.livePreview)
                Text("Shows the words under the HUD while you speak, using a small extra speech model (downloaded once, about 150 MB). The pasted text still comes from the whole recording after you release. Off with the OpenAI-compatible engine.")
                    .bvFont(.footnote).foregroundStyle(.bvSecondary)
                Divider()
                SettingsRow(title: "Use project words in") {
                    Picker("Use project words in", selection: $model.settings.speech.projectWordsScope) {
                        Text("Coding apps").tag(ProjectWordsScope.codingApps)
                        Text("All apps").tag(ProjectWordsScope.allApps)
                        Text("Off").tag(ProjectWordsScope.off)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                Text("Coding apps: Terminal-style apps, VS Code, Cursor, Xcode, Zed and Orca. Manage folders in Dictionary › Projects.")
                    .bvFont(.footnote).foregroundStyle(.bvSecondary)
                Divider()
                SettingsRow(title: "Microphone") {
                    Picker("Microphone", selection: $model.settings.speech.microphoneUID) {
                        Text("System default").tag(String?.none)
                        ForEach(devices) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .labelsHidden().fixedSize()
                }
            }
            AppLanguagesCard(model: model)
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
