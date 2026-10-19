import AppIntents
import Foundation
import VoiceCore

struct StartMeetingIntent: AppIntent {
    static let title: LocalizedStringResource = "Start meeting recording"
    static let description = IntentDescription("Starts recording a meeting, like Start meeting in the menu bar. Optional title.")
    static let openAppWhenRun = false
    @Parameter(title: "Title") var title: String?
    static var parameterSummary: some ParameterSummary { Summary("Start meeting recording") { \.$title } }

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let model = try await ShortcutsBridge.ready()
        guard let meetings = model.meetings else { throw ShortcutsError.notReady }
        guard !meetings.isRecording else { throw ShortcutsError.meetingAlreadyRecording }
        await meetings.start()
        guard meetings.isRecording else { throw ShortcutsError.other(meetings.statusMessage ?? "Could not start the meeting.") }
        let name = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { await meetings.rename(name) }
        return .result(value: meetings.title)
    }
}
