import SwiftUI
import VoiceCore

struct MeetingRecorderView: View {
    @Bindable var controller: MeetingController

    private var state: MeetingRecorderState {
        if controller.isTranscribing { .transcribing }
        else if controller.isPaused { .paused }
        else if controller.isRecording { .recording }
        else { .idle }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                Circle().fill(controller.isTranscribing ? .orange : .red).frame(width: 9, height: 9)
                Text(controller.isTranscribing ? "Transcribing meeting" : controller.isPaused ? "Meeting paused" : "Recording meeting")
                    .fontWeight(.semibold)
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(clock(controller.elapsed)).monospacedDigit().font(.system(.title3, design: .rounded))
                }
            }

            HStack(spacing: 16) {
                meter("You", level: controller.youLevel)
                meter("Others", level: controller.othersLevel)
            }

            Text(controller.latestLine.isEmpty ? "Waiting for speech" : controller.latestLine)
                .font(.callout)
                .foregroundStyle(controller.latestLine.isEmpty ? .secondary : .primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)

            HStack(spacing: 8) {
                ForEach(Array(MeetingRecorderPresentation.actions(for: state).enumerated()), id: \.offset) { _, action in
                    button(for: action)
                }
                Spacer(minLength: 0)
                if controller.isRecording || controller.isPaused { languageMenu }
            }
        }
        .padding(16)
        .frame(width: 480)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.15)))
    }

    @ViewBuilder private func button(for action: MeetingRecorderAction) -> some View {
        switch action {
        case .start:
            Button("Start") { Task { await controller.start() } }.buttonStyle(.borderedProminent)
        case .pause:
            Button("Pause") { Task { await controller.pause() } }
        case .resume:
            Button("Resume") { Task { await controller.resume() } }
        case .mark:
            Button("Mark") { Task { await controller.mark() } }
        case .stop:
            Button("Stop") { Task { await controller.stop() } }.buttonStyle(.bordered)
        }
    }

    private var languageMenu: some View {
        Menu {
            ForEach(MeetingLanguages.choices, id: \.self) { language in
                Toggle(language.displayName, isOn: Binding(
                    get: { controller.languages.contains(language) },
                    set: { _ in controller.toggleLanguage(language) }
                ))
                .disabled(controller.languages == [language])
            }
        } label: {
            Text(controller.languages.map { $0.rawValue.uppercased() }.joined(separator: " · "))
                .font(.caption.weight(.medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Languages spoken in this meeting")
    }

    private func meter(_ title: String, level: Float) -> some View {
        HStack(spacing: 7) {
            Text(title).font(.caption).foregroundStyle(.secondary).frame(width: 42, alignment: .leading)
            LevelBars(level: level).foregroundStyle(level > 0.02 ? .green : .secondary)
        }
    }

    private func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
