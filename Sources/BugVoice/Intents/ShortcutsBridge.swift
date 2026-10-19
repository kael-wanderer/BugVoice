import AppIntents
import Foundation
import VoiceCore

@MainActor
enum ShortcutsBridge {
    static weak var model: AppModel?
    static func ready() async throws -> AppModel {
        let deadline = ContinuousClock.now.advanced(by: .seconds(ShortcutsActions.bootstrapWait))
        repeat {
            try Task.checkCancellation()
            if let model, model.meetings != nil, model.uploads != nil { return model }
            try await Task.sleep(for: .milliseconds(100))
        } while ContinuousClock.now < deadline
        throw ShortcutsError.notReady
    }
}

extension ShortcutsError: CustomLocalizedStringResourceConvertible {
    public var localizedStringResource: LocalizedStringResource { "\(message)" }
}
