import SwiftUI
import VoiceCore

struct MeetingsTab: View {
    @Bindable var model: AppModel

    var body: some View {
        SettingsScroll {
            SettingsCard(title: "Languages") {
                ForEach(MeetingLanguages.choices, id: \.self) { language in
                    SettingsRow(title: language.displayName) {
                        Toggle(language.displayName, isOn: languageBinding(language))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .disabled(isLastLanguage(language))
                    }
                }
                Text("Speech in any other language is transcribed again in one of these. Pick only English for English calls. Applies to meetings and uploads; change it for one meeting on the recorder panel.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            SettingsCard(title: "Automatic deletion") {
                SettingsRow(title: "Delete ready meetings after") {
                    Picker("Delete ready meetings after", selection: $model.settings.meetings.deleteAfter) {
                        Text("Never").tag(MeetingRetentionPolicy.never)
                        Text("30 days").tag(MeetingRetentionPolicy.days30)
                        Text("90 days").tag(MeetingRetentionPolicy.days90)
                        Text("365 days").tag(MeetingRetentionPolicy.year)
                    }
                    .labelsHidden().fixedSize()
                }
                Text("Meetings that are recording, interrupted, or transcribing are kept.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            SettingsCard(title: "Summary and action item budget") {
                SettingsRow(title: "Context size") {
                    Text("\(model.settings.meetings.generationContextTokens.formatted()) tokens").monospacedDigit()
                    Stepper("Context size", value: $model.settings.meetings.generationContextTokens, in: 2_048...65_536, step: 1_024)
                        .labelsHidden()
                }
                Divider()
                SettingsRow(title: "Output limit") {
                    Text("\(model.settings.meetings.generationOutputTokens.formatted()) tokens").monospacedDigit()
                    Stepper(
                        "Output limit",
                        value: $model.settings.meetings.generationOutputTokens,
                        in: 256...max(256, model.settings.meetings.generationContextTokens - 1_024),
                        step: 256
                    )
                    .labelsHidden()
                }
                Text("Long transcripts are summarized in parts and combined. These limits are separate from dictation cleanup.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onChange(of: model.settings.meetings.generationContextTokens) { _, context in
            model.settings.meetings.generationOutputTokens = min(
                model.settings.meetings.generationOutputTokens,
                max(256, context - 1_024)
            )
        }
    }

    private func isLastLanguage(_ language: SpeechLanguage) -> Bool {
        model.settings.meetings.languages == [language]
    }

    private func languageBinding(_ language: SpeechLanguage) -> Binding<Bool> {
        Binding(
            get: { model.settings.meetings.languages.contains(language) },
            set: { isOn in
                let current = model.settings.meetings.languages
                let next = isOn ? current + [language] : current.filter { $0 != language }
                guard !next.isEmpty else { return }
                model.settings.meetings.languages = MeetingLanguages.choices.filter(next.contains)
            }
        )
    }
}
