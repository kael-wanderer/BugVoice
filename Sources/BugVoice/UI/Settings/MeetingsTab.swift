import SwiftUI
import VoiceCore

struct MeetingsTab: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Automatic deletion") {
                Picker("Delete ready meetings after", selection: $model.settings.meetings.deleteAfter) {
                    Text("Never").tag(MeetingRetentionPolicy.never)
                    Text("30 days").tag(MeetingRetentionPolicy.days30)
                    Text("90 days").tag(MeetingRetentionPolicy.days90)
                    Text("365 days").tag(MeetingRetentionPolicy.year)
                }
                Text("Meetings that are recording, interrupted, or transcribing are kept.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Summary and action item budget") {
                Stepper(value: $model.settings.meetings.generationContextTokens, in: 2_048...65_536, step: 1_024) {
                    LabeledContent("Context size", value: "\(model.settings.meetings.generationContextTokens.formatted()) tokens")
                }
                Stepper(
                    value: $model.settings.meetings.generationOutputTokens,
                    in: 256...max(256, model.settings.meetings.generationContextTokens - 1_024),
                    step: 256
                ) {
                    LabeledContent("Output limit", value: "\(model.settings.meetings.generationOutputTokens.formatted()) tokens")
                }
                Text("Long transcripts are summarized in parts and combined. These limits are separate from dictation cleanup.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: model.settings.meetings.generationContextTokens) { _, context in
            model.settings.meetings.generationOutputTokens = min(
                model.settings.meetings.generationOutputTokens,
                max(256, context - 1_024)
            )
        }
    }
}
