import AppKit
import BugVoiceMac
import Foundation
import Observation
import ServiceManagement
import SwiftUI
import VoiceCore
import WhisperEngine

/// Main-window pages. Meetings and Notes are added by sub-projects 2 and 3.
enum Page: String, CaseIterable, Identifiable {
    case dictation, settings
    var id: String { rawValue }
    var title: String { self == .dictation ? "Dictation" : "Settings" }
    var symbol: String { self == .dictation ? "mic" : "gearshape" }
}

@MainActor
@Observable
final class AppModel {
    let paths = AppPaths.standard()
    let keychain = Keychain()
    @ObservationIgnored let store = SettingsStore(url: AppPaths.standard().settings)
    @ObservationIgnored let historyLog = HistoryLog(url: AppPaths.standard().history)
    @ObservationIgnored private(set) var whisper: WhisperKitTranscriber

    var settings = AppSettings() {
        didSet {
            guard settings != oldValue, !isLoadingSettings else { return }
            settingsDidChange(from: oldValue)
        }
    }
    var vocabularyText = ""
    var vocabulary = Vocabulary()
    var history: [HistoryEntry] = []
    /// The latest dictation, for the menu preview and *Paste last*. A
    /// secure-field result is stored without its text.
    var lastResult: DictationResult?
    var page: Page = .dictation
    var speechState: WhisperKitTranscriber.LoadState = .notLoaded
    var hotkeyActive = false
    var permissionsGranted = Permissions.allGranted
    /// The latest failure to save something (settings, vocabulary, history,
    /// Keychain, login item). The UI shows it and sets it back to nil once
    /// the user has seen it. Never cleared by a later success.
    var saveError: String?

    @ObservationIgnored var onSettingsChanged: (() -> Void)?
    /// Brings up the main window. Set by the app delegate, which owns it.
    @ObservationIgnored var presentMainWindow: (() -> Void)?
    /// Created by `bootstrap()` once settings are loaded.
    @ObservationIgnored private(set) var dictation: DictationController?
    @ObservationIgnored private var isLoadingSettings = false

    init() {
        whisper = WhisperKitTranscriber(modelName: AppSettings().speech.whisperModel, downloadBase: AppPaths.standard().models)
    }

    func bootstrap() async {
        do {
            try paths.ensureExists()
        } catch {
            saveError = "Could not create \(paths.root.path): \(error.localizedDescription)"
        }
        let loaded = store.load()
        whisper = WhisperKitTranscriber(modelName: loaded.speech.whisperModel, downloadBase: paths.models)
        // Loading is not a change: no save, no model reload, no login-item call.
        isLoadingSettings = true
        settings = loaded
        isLoadingSettings = false

        if !FileManager.default.fileExists(atPath: paths.vocabulary.path) {
            do {
                try "# One term per line. Use  spoken => written  for replacements.\n"
                    .write(to: paths.vocabulary, atomically: true, encoding: .utf8)
            } catch {
                saveError = "Could not create vocabulary.txt: \(error.localizedDescription)"
            }
        }
        vocabularyText = (try? String(contentsOf: paths.vocabulary, encoding: .utf8)) ?? ""
        vocabulary = Vocabulary.parse(vocabularyText)
        startDictation()
        await applyRetention()
        Task { await prepareSpeech() }
    }

    /// Configured from the settings just loaded (loading does not fire
    /// `onSettingsChanged`), then follows later changes.
    private func startDictation() {
        guard dictation == nil else { return }
        let controller = DictationController(model: self)
        dictation = controller
        controller.start()
        onSettingsChanged = { [weak controller] in controller?.applySettings() }
    }

    func openMainWindow(_ page: Page? = nil) {
        if let page { self.page = page }
        presentMainWindow?()
    }

    // MARK: Settings

    private func settingsDidChange(from old: AppSettings) {
        do {
            try store.save(settings)
        } catch {
            saveError = "Could not save settings: \(error.localizedDescription)"
        }
        if settings.speech.whisperModel != old.speech.whisperModel {
            whisper = WhisperKitTranscriber(modelName: settings.speech.whisperModel, downloadBase: paths.models)
            speechState = .notLoaded
            Task { await prepareSpeech() }
        }
        if settings.launchAtLogin != old.launchAtLogin { applyLaunchAtLogin() }
        if settings.historyRetention != old.historyRetention {
            Task { await applyRetention() }
        }
        onSettingsChanged?()
    }

    private func applyLaunchAtLogin() {
        do {
            if settings.launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            saveError = "Could not change Launch at login: \(error.localizedDescription)"
        }
    }

    // MARK: Speech model

    func prepareSpeech() async {
        let engine = whisper
        do {
            try await engine.prepare { [weak self] fraction in
                Task { @MainActor in self?.showDownloadProgress(fraction, for: engine) }
            }
        } catch {}
        guard engine === whisper else { return }
        speechState = await engine.state
    }

    private func showDownloadProgress(_ fraction: Double, for engine: WhisperKitTranscriber) {
        // A late progress report must not overwrite Loading or Ready.
        guard engine === whisper else { return }
        switch speechState {
        case .notLoaded, .downloading: speechState = .downloading(fraction)
        case .loading, .ready, .failed: break
        }
    }

    func refreshSpeechState() async {
        speechState = await whisper.state
    }

    // MARK: Dictation

    func makePipeline(insertion: any InsertionTarget) -> DictationPipeline {
        DictationPipeline(
            transcriber: ProviderFactory.transcriber(settings.speech, whisper: whisper, keychain: keychain),
            textModel: ProviderFactory.textModel(settings.textModel, keychain: keychain),
            insertion: insertion,
            focus: FocusInspector(),
            settings: settings,
            vocabulary: vocabulary
        )
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
    }

    // MARK: History

    func reloadHistory() async {
        history = await historyLog.load()
    }

    func deleteHistory(id: UUID) async {
        do {
            try await historyLog.delete(id: id)
        } catch {
            saveError = "Could not delete the dictation: \(error.localizedDescription)"
        }
        await reloadHistory()
    }

    /// Deletes every saved dictation. Also what Settings calls after the user
    /// confirms switching retention to *Don't save*.
    func clearHistory() async {
        do {
            try await historyLog.clear()
        } catch {
            saveError = "Could not clear history: \(error.localizedDescription)"
        }
        await reloadHistory()
    }

    /// Drops entries older than the retention window, then reloads.
    private func applyRetention() async {
        if let age = settings.historyRetention.maxAge {
            do {
                try await historyLog.prune(olderThan: Date().addingTimeInterval(-age))
            } catch {
                saveError = "Could not remove old history: \(error.localizedDescription)"
            }
        }
        await reloadHistory()
    }

    // MARK: Vocabulary

    func saveVocabulary(_ text: String) {
        vocabularyText = text
        vocabulary = Vocabulary.parse(text)
        do {
            try text.write(to: paths.vocabulary, atomically: true, encoding: .utf8)
        } catch {
            saveError = "Could not save vocabulary.txt: \(error.localizedDescription)"
        }
    }

    // MARK: Keychain

    /// A text binding backed by the Keychain item `account` (service
    /// `BugVoice`). Empty deletes the item. A failed write sets `saveError`
    /// and leaves the stored value as it was.
    func keyBinding(account: String) -> Binding<String> {
        Binding(
            get: { [keychain] in keychain.read(account) ?? "" },
            set: { [weak self] value in self?.saveKey(value, account: account) }
        )
    }

    /// Returns false, and sets `saveError`, when the Keychain refused the write.
    @discardableResult
    func saveKey(_ value: String, account: String) -> Bool {
        do {
            try keychain.write(value, account: account)
            return true
        } catch let error as KeychainError {
            saveError = "Could not save the key in Keychain (error \(error.status))."
            return false
        } catch {
            saveError = "Could not save the key in Keychain: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: Permissions

    func refreshPermissions() {
        permissionsGranted = Permissions.allGranted
    }
}
