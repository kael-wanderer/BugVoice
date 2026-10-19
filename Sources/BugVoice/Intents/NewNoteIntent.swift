import AppIntents
import Foundation
import VoiceCore

struct NewNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "New note"
    static let description = IntentDescription("Creates a Scratchpad note with the text. Optional title and folder.")
    static let openAppWhenRun = false
    @Parameter(title: "Text", inputOptions: String.IntentInputOptions(multiline: true)) var text: String
    @Parameter(title: "Title") var title: String?
    @Parameter(title: "Folder") var folder: String?
    static var parameterSummary: some ParameterSummary {
        Summary("New note with \(\.$text)") { \.$title; \.$folder }
    }
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let model = try await ShortcutsBridge.ready()
        let folderID = try ShortcutsActions.folder(folder, in: model.library.folders).get()
        let title = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let note = try await model.notesController.createForAgent(title: title.isEmpty ? "Untitled" : title,
                body: text, frontMatter: NoteFrontMatter(folderID: folderID, tags: []))
            return .result(value: note.title)
        } catch { throw ShortcutsError.other("Could not create the note: \(error.localizedDescription)") }
    }
}
