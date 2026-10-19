import AppKit
import BugVoiceMac
import Foundation
import SwiftUI
import VoiceCore
import WhisperEngine

extension AppModel {
    // MARK: Models

    var appleIntelligenceAvailable: Bool {
        #if canImport(FoundationModels)
            if #available(macOS 26.0, *) { return AppleIntelligenceModel.isAvailable }
        #endif
        return false
    }

    func plan(for feature: ModelFeature) -> ModelPlan {
        ModelResolver.plan(
            for: feature, settings: settings.models,
            cliPaths: cliInfo.mapValues(\.path),
            appleIntelligenceAvailable: appleIntelligenceAvailable
        )
    }

    func refreshCLIs() async {
        let runner = FoundationProcessRunner()
        var found: [CLITool: CLIInfo] = [:]
        for tool in CLITool.allCases {
            if let info = await CLILocator.locate(tool, runner: runner) { found[tool] = info }
        }
        cliInfo = found
    }

    /// Copies keys saved under the old single-key accounts to their new
    /// connections once, then forgets the moves (which saves the settings
    /// in the new format).
    func applyPendingKeyMoves() {
        let moves = settings.models.pendingKeyMoves
        guard !moves.isEmpty else { return }
        for move in moves where credentials.read(move.to) == nil {
            guard let value = credentials.read(move.from), !value.isEmpty else { continue }
            do {
                try credentials.write(value, account: move.to)
                try credentials.write(nil, account: move.from)
            } catch {
                saveError = "Could not move the API key: \(error.localizedDescription)"
            }
        }
        settings.models.pendingKeyMoves = []
    }

    /// Lists the server's models; never asks for a generation.
    func testConnection(_ connection: ModelConnection) async {
        guard let url = ConnectionAddress.baseURL(for: connection) else {
            connectionStatus[connection.id] = .failed(
                ConnectionAddress.problem(connection.baseURL) ?? "The address is not valid.")
            return
        }
        do {
            let models = try await ModelCatalog.list(
                baseURL: url, apiKey: credentials.read(connection.credentialAccount),
                anthropic: connection.kind.usesAnthropicAPI
            )
            connectionStatus[connection.id] = .reachable(models: models)
        } catch {
            connectionStatus[connection.id] = .failed(error.localizedDescription)
        }
    }

    /// The meeting window's notes editor when it has the keyboard, for the hotkey.
    func meetingNotesEditorWithKeyboard() -> MeetingNotesTextView? {
        guard let window = NSApp.keyWindow, window.identifier == AppWindow.meeting else { return nil }
        return window.firstResponder as? MeetingNotesTextView
    }

    func captureNotesDictation(startFocus: FocusSnapshot) -> NotesDictationCapture? {
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        // The Scratchpad panel takes the keyboard without making BugVoice the
        // frontmost app, so a key Scratchpad window counts as frontmost.
        let scratchpadHasKeyboard = NSApp.keyWindow?.identifier == AppWindow.scratchpad
        let bugVoiceIsFrontmost =
            scratchpadHasKeyboard
            || (NSApp.isActive
                && frontmostPID == ProcessInfo.processInfo.processIdentifier
                && startFocus.bundleID == Bundle.main.bundleIdentifier)
        let firstResponderEditorID = (NSApp.keyWindow?.firstResponder as? NotesTextView)?.editorID
        return notesController.captureAtStart(
            bugVoiceIsFrontmost: bugVoiceIsFrontmost,
            notesPageIsSelected: scratchpadHasKeyboard,
            firstResponderEditorID: firstResponderEditorID
        )
    }

    func registerGlobalShortcuts() {
        let shortcuts = GlobalShortcuts.shared
        shortcuts.unregisterAll()
        unavailableShortcuts.removeAll()
        unavailableShortcutActions.removeAll()

        for action in ShortcutAction.allCases {
            let letter = settings.shortcuts.letter(for: action)
            guard let keyCode = ShortcutKeys.keyCode(forLetter: letter) else { continue }
            let registered = shortcuts.register(
                keyCode: UInt32(keyCode),
                modifiers: GlobalShortcuts.controlOption
            ) { [weak self] in
                guard let self else { return }
                switch action {
                case .pasteLast: dictation?.pasteLast()
                case .pasteRaw: dictation?.pasteRaw()
                case .redoOtherLanguage: dictation?.redoInOtherLanguage()
                case .toggleMeeting: meetings?.toggleRecording()
                case .openApp: openMainWindow(.dictation)
                case .newNote: Task { @MainActor in await openScratchpadWindow(newNote: true) }
                }
            }
            if !registered {
                unavailableShortcuts.append("⌃⌥\(letter) \(action.title)")
                unavailableShortcutActions.insert(action)
            }
        }
    }

    func captureSelectedNoteForMic() -> NotesDictationCapture? {
        guard scratchpadWindowIsVisible else { return nil }
        return notesController.captureSelectedNoteForMic()
    }

    func record(_ result: DictationResult) async {
        lastResult = result.recallable
        guard settings.historyRetention != .off, let entry = result.historyEntry else { return }
        do {
            try await historyLog.append(entry)
        } catch {
            saveError = "Could not save to history: \(error.localizedDescription)"
        }
        await reloadHistory()
        // One batch: a later dictation does not push back the pending deadline.
        searchIndexer.schedule(.dictations, after: .seconds(600), extend: false)
    }

    func replaceLast(_ result: DictationResult, kind: FixKind) async {
        guard var previous = lastResult else { return }
        previous.language = result.language
        previous.requestedLanguage = result.requestedLanguage
        previous.raw = result.raw
        previous.cleaned = result.cleaned
        previous.finalText = result.finalText
        previous.uncleanedText = result.uncleanedText
        previous.outcome = .inserted
        previous.rawReason = result.rawReason
        previous.errorMessage = nil
        previous.timings = result.timings
        lastResult = previous.recallable
        guard settings.historyRetention != .off, var entry = previous.historyEntry else { return }
        entry.replacedBy = kind
        do {
            try await historyLog.replace(entry)
            await reloadHistory()
        } catch {
            saveError = "Could not update history: \(error.localizedDescription)"
        }
    }
}
