import SwiftUI
import VoiceCore

struct MeetingsTab: View {
    @Bindable var model: AppModel

    var body: some View {
        SettingsScroll {
            SettingsCard(title: "Meeting detection") {
                SettingsRow(title: "Detect meetings") {
                    Toggle("Detect meetings", isOn: $model.settings.meetings.detectMeetings)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                Text("Offers to record when Zoom, Teams, Slack, FaceTime, Webex, Discord or a Meet, Teams or Zoom tab in a browser starts using the microphone. It never records by itself.")
                    .font(.caption).foregroundStyle(.secondary)
                if model.meetingDetectionUnavailable {
                    Text("Meeting detection is not available.").font(.caption).foregroundStyle(.orange)
                }
                if model.permissionStatus[.accessibility] == false {
                    HStack {
                        Text("Browser meetings need Accessibility access.").font(.caption).foregroundStyle(.orange)
                        Button("Open Settings") { model.openPermissionsWindow() }.controlSize(.small)
                    }
                }
                if !model.settings.meetings.mutedMeetingApps.isEmpty {
                    Divider()
                    Text("Muted apps").font(.caption.weight(.semibold))
                    ForEach(model.settings.meetings.mutedMeetingApps, id: \.self) { bundleID in
                        SettingsRow(title: MeetingDetector.meetingApps[bundleID] ?? MeetingDetector.browsers[bundleID] ?? bundleID) {
                            Button("Remove") {
                                model.settings.meetings.mutedMeetingApps.removeAll { $0 == bundleID }
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
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
                Text("Speech in any other language is transcribed again in one of these. Pick only English for English calls. Applies to meetings and uploads; change it for one meeting in the meeting window.")
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
            SettingsCard(title: "Live summary") {
                SettingsRow(title: "Update every") {
                    Picker("Update every", selection: $model.settings.meetings.liveSummaryInterval) {
                        ForEach(LiveSummaryPlanner.intervalChoices, id: \.self) { seconds in
                            Text(LiveSummaryPlanner.intervalLabel(seconds)).tag(seconds)
                        }
                    }
                    .labelsHidden().fixedSize()
                }
                Text("Meeting time between updates of the summary in the meeting window. Pauses do not count. Shorter times keep the Meetings model busier.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            SettingsCard(title: "Known voices") {
                SettingsRow(title: "Suggest names from known voices") {
                    Toggle("Suggest names from known voices", isOn: $model.settings.meetings.suggestKnownVoices)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                ForEach(Array(model.knownVoices.enumerated()), id: \.element.id) { index, voice in
                    HStack(spacing: 8) {
                        Circle().fill(SpeakerColors.color(index + 1)).frame(width: 8, height: 8)
                        Text(voice.name)
                        Text(voice.contributions.count == 1 ? "1 meeting" : "\(voice.contributions.count) meetings")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Delete") { Task { await model.deleteKnownVoice(name: voice.name) } }
                            .controlSize(.small)
                            .accessibilityLabel("Delete \(voice.name)")
                    }
                }
                Text("A voice is saved when you name a speaker and confirm it. Saved voices stay on this Mac. Delete one to stop suggesting it.")
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
