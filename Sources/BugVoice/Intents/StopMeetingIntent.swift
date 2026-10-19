import AppIntents
import Foundation
import VoiceCore

struct StopMeetingIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop meeting recording"
    static let description = IntentDescription("Stops the meeting that is recording. Transcription continues in BugVoice.")
    static let openAppWhenRun = false
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let model = try await ShortcutsBridge.ready()
        guard let meetings = model.meetings else { throw ShortcutsError.notReady }
        guard meetings.isRecording else { throw ShortcutsError.noMeetingRecording }
        let title = meetings.title
        await meetings.stop()
        return .result(value: title)
    }
}
