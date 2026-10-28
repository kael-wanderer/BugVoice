import BugVoiceMac
import Foundation
import VoiceCore

/// The Settings › General readiness card: what dictation needs, and how to fix it.
extension AppModel {
    var readinessRows: [ReadinessRow] {
        let names: [(PermissionKind, String)] = [
            (.microphone, "Microphone"), (.accessibility, "Accessibility"), (.inputMonitoring, "Input Monitoring"),
        ]
        let onDevice = settings.speech.engine == .whisperKit
        return Readiness.rows(
            missingPermissions: names.filter { permissionStatus[$0.0] == false }.map(\.1),
            hotkeyActive: hotkeyActive,
            hotkey: settings.hotkey.spokenName,
            speech: readinessSpeech,
            onDeviceModel: onDevice ? speechModelName : nil,
            serverURL: onDevice ? nil : settings.speech.serverBaseURL,
            cleanup: cleanupCheck
        )
    }

    /// The connection dictation cleanup uses, if it uses one.
    var dictationConnection: ModelConnection? {
        if case .connection(let connection, _, _, _, _) = plan(for: .dictation) { return connection }
        return nil
    }

    func runReadinessAction(_ action: ReadinessAction) {
        switch action {
        case .openPermissions: openPermissionsWindow()
        case .retryHotkey: dictation?.retryHotkey()
        case .retrySpeech: retrySpeech()
        case .checkCleanup:
            guard let connection = dictationConnection else { return }
            Task { await testConnection(connection) }
        case .openModels: settingsTab = .models
        }
    }

    private var readinessSpeech: MenuSpeechState {
        switch speechState {
        case .downloading(let fraction): .downloading(fraction)
        case .loading, .notLoaded: .loading
        case .failed: .failed
        case .ready: .ready
        }
    }

    private var speechModelName: String {
        let id = settings.speech.whisperModel
        let label = SpeechTab.whisperModels.first { $0.0 == id }?.1
        return label?.components(separatedBy: " · ").first ?? id
    }

    private var cleanupCheck: CleanupCheck {
        let plan = plan(for: .dictation)
        switch plan {
        case .none:
            return .off
        case .unavailable(let reason):
            return .unavailable(reason)
        case .connection(let connection, _, _, _, _):
            let name = plan.shortName ?? connection.name
            switch connectionStatus[connection.id] {
            case nil: return .unchecked(name: name)
            case .reachable: return .reachable(name: name)
            case .failed(let message): return .failed(name: name, message: message)
            }
        case .appleIntelligence, .cli:
            return .local(name: plan.shortName ?? "")
        }
    }
}
