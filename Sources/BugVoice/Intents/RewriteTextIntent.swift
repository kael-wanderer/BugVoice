import AppIntents
import Foundation
import VoiceCore

struct RewriteTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Rewrite text"
    static let description = IntentDescription("Applies an instruction to text with your Dictation cleanup model, like command mode.")
    static let openAppWhenRun = false
    @Parameter(title: "Text", inputOptions: String.IntentInputOptions(multiline: true)) var text: String
    @Parameter(title: "Instruction") var instruction: String
    static var parameterSummary: some ParameterSummary { Summary("Rewrite \(\.$text) with \(\.$instruction)") }
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let model = try await ShortcutsBridge.ready()
        return .result(value: try await model.makeCommandPipeline().rewrite(text: text, instruction: instruction).get())
    }
}
