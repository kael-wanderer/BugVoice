import AppIntents
import Foundation
import VoiceCore

struct ActionItemsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get open action items"
    static let description = IntentDescription("Returns open action items from your meetings, newest meeting first.")
    static let openAppWhenRun = false
    @Parameter(title: "Meeting") var meeting: String?
    @Parameter(title: "Limit", default: 50) var limit: Int
    static var parameterSummary: some ParameterSummary { Summary("Get open action items") { \.$meeting; \.$limit } }
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<[String]> {
        let model = try await ShortcutsBridge.ready()
        return .result(value: try ShortcutsActions.openActionItems(meetings: model.meetingManifests,
            done: model.actionItemsDone, meeting: meeting, limit: limit, now: Date()).get())
    }
}
