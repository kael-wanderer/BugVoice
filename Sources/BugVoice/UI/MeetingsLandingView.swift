import SwiftUI

struct MeetingsLandingView: View {
    @Bindable var model: AppModel

    var body: some View {
        ContentUnavailableView {
            Label("Meetings", systemImage: "waveform.path")
        } description: {
            Text(model.meetings?.statusMessage ?? "Record a meeting to see its transcript here.")
        } actions: {
            if model.meetings?.isTranscribing == true {
                Text("Transcribing meeting…")
            } else if model.meetings?.isRecording == true || model.meetings?.isPaused == true {
                Button("Stop meeting") { Task { await model.meetings?.stop() } }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Start recording") { Task { await model.meetings?.start() } }
                    .buttonStyle(.borderedProminent)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let meeting = model.meetings {
                VStack(alignment: .trailing, spacing: 5) {
                    if meeting.isRecording || meeting.isPaused { Text(time(meeting.elapsed)).font(.title3.monospacedDigit()) }
                    if !meeting.latestLine.isEmpty { Text(meeting.latestLine).lineLimit(2).font(.callout) }
                    if meeting.isTranscribing { Text("Transcribing meeting…").font(.callout) }
                }
                .padding(20)
            }
        }
    }

    private func time(_ value: TimeInterval) -> String {
        let seconds = max(0, Int(value))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
