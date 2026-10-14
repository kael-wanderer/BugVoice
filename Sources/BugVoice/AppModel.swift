import AppKit
import Carbon
import BugVoiceMac
import Foundation
import Observation
import ServiceManagement
import SwiftUI
import VoiceCore
import WhisperEngine

private enum MeetingGenerationError: LocalizedError {
    case noTextModel
    var errorDescription: String? { "Choose a text model in Settings before generating meeting notes." }
}

/// Main-window pages. Notes are reserved for sub-project 3.
enum Page: String, CaseIterable, Identifiable {
    case dictation, meetings, settings
    var id: String { rawValue }
    var title: String { switch self { case .dictation: "Dictation"; case .meetings: "Meetings"; case .settings: "Settings" } }
    var symbol: String { switch self { case .dictation: "mic"; case .meetings: "waveform.path"; case .settings: "gearshape" } }
}

@MainActor
@Observable
final class AppModel {
    let paths = AppPaths.standard()
    let keychain = Keychain()
    @ObservationIgnored let store = SettingsStore(url: AppPaths.standard().settings)
    @ObservationIgnored let historyLog = HistoryLog(url: AppPaths.standard().history)
    @ObservationIgnored private var meetingStore: MeetingStore { MeetingStore(root: paths.meetings) }
    @ObservationIgnored private(set) var whisper: WhisperKitTranscriber
    @ObservationIgnored private(set) var priorityTranscriber: PriorityTranscriber
    @ObservationIgnored let transcriptionRouter: TranscriptionRouter
    @ObservationIgnored private var systemAudioGrantedThisRun = false

    var settings = AppSettings() {
        didSet {
            guard settings != oldValue, !isLoadingSettings else { return }
            settingsDidChange(from: oldValue)
        }
    }
    var vocabularyText = ""
    var vocabulary = Vocabulary()
    var history: [HistoryEntry] = []
    var meetingManifests: [MeetingManifest] = []
    var selectedMeetingID: MeetingID?
    var meetingSearchQuery = ""
    /// The latest dictation, for the menu preview and *Paste last*. A
    /// secure-field result is stored without its text.
    var lastResult: DictationResult?
    var page: Page = .dictation
    var speechState: WhisperKitTranscriber.LoadState = .notLoaded
    var hotkeyActive = false
    /// True while the microphone is recording a dictation.
    var isListening = false
    var permissionsGranted = Permissions.allGranted
    var permissionStatus: [PermissionKind: Bool] = [:]
    var systemAudioPermissionFailed = false
    /// The latest failure to save something (settings, vocabulary, history,
    /// Keychain, login item). The UI shows it and sets it back to nil once
    /// the user has seen it. Never cleared by a later success.
    var saveError: String?

    @ObservationIgnored var onSettingsChanged: (() -> Void)?
    /// Brings up the main window. Set by the app delegate, which owns it.
    @ObservationIgnored var presentMainWindow: (() -> Void)?
    /// Brings up the Permissions window. Set by the app delegate.
    @ObservationIgnored var presentPermissionsWindow: (() -> Void)?
    /// Created by `bootstrap()` once settings are loaded.
    @ObservationIgnored private(set) var dictation: DictationController?
    @ObservationIgnored private(set) var meetings: MeetingController?
    @ObservationIgnored private var isLoadingSettings = false
    @ObservationIgnored private var preparingEngine: WhisperKitTranscriber?
    @ObservationIgnored private var speechAPIKeyGeneration: UInt64 = 0

    init() {
        let engine = WhisperKitTranscriber(modelName: AppSettings().speech.whisperModel, downloadBase: AppPaths.standard().models)
        whisper = engine
        let priority = PriorityTranscriber(base: engine)
        priorityTranscriber = priority
        transcriptionRouter = TranscriptionRouter(initial: priority)
    }

    func bootstrap() async {
        do {
            try paths.ensureExists()
        } catch {
            saveError = "Could not create \(paths.root.path): \(error.localizedDescription)"
        }
        let loaded = store.load()
        whisper = WhisperKitTranscriber(modelName: loaded.speech.whisperModel, downloadBase: paths.models)
        priorityTranscriber = PriorityTranscriber(base: ProviderFactory.transcriber(loaded.speech, whisper: whisper, keychain: keychain))
        await transcriptionRouter.replace(with: priorityTranscriber)
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
        GlobalShortcuts.shared.register(keyCode: UInt32(kVK_ANSI_M), modifiers: GlobalShortcuts.controlOption) { [weak self] in
            Task { @MainActor in self?.meetings?.toggleRecording() }
        }
        meetings = MeetingController(model: self)
        refreshPermissions()
        if !permissionsGranted { openPermissionsWindow() }
        await applyRetention()
        await recoverUnfinishedMeetings()
        await applyMeetingRetention()
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

    func openPermissionsWindow() {
        presentPermissionsWindow?()
    }

    // MARK: Settings

    private func settingsDidChange(from old: AppSettings) {
        do {
            try store.save(settings)
        } catch {
            saveError = "Could not save settings: \(error.localizedDescription)"
        }
        if SpeechTranscriberConfiguration(settings: settings.speech, speechAPIKeyGeneration: speechAPIKeyGeneration)
            != SpeechTranscriberConfiguration(settings: old.speech, speechAPIKeyGeneration: speechAPIKeyGeneration) {
            rebuildSpeechTranscriber()
        }
        if settings.launchAtLogin != old.launchAtLogin { applyLaunchAtLogin() }
        if settings.historyRetention != old.historyRetention {
            Task { await applyRetention() }
        }
        if settings.meetings.deleteAfter != old.meetings.deleteAfter {
            Task { await applyMeetingRetention() }
        }
        onSettingsChanged?()
    }

    private func rebuildSpeechTranscriber() {
        let speech = settings.speech
        let replacementWhisper = WhisperKitTranscriber(modelName: speech.whisperModel, downloadBase: paths.models)
        let replacement = PriorityTranscriber(base: ProviderFactory.transcriber(speech, whisper: replacementWhisper, keychain: keychain))
        speechState = speech.engine == .whisperKit ? .notLoaded : .ready
        Task { [weak self] in
            guard let self else { return }
            await transcriptionRouter.replace(with: replacement)
            whisper = replacementWhisper
            priorityTranscriber = replacement
            if speech.engine == .whisperKit { Task { await prepareSpeech() } }
        }
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

    /// Starts loading the speech model again after a failure. Repeated
    /// calls while a retry is under way do nothing.
    func retrySpeech() {
        guard case .failed = speechState else { return }
        speechState = .notLoaded
        Task { await prepareSpeech() }
    }

    func prepareSpeech() async {
        let engine = whisper
        // One load per engine at a time; a new engine (model change) may start its own.
        guard preparingEngine !== engine else { return }
        preparingEngine = engine
        defer { if preparingEngine === engine { preparingEngine = nil } }
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
            transcriber: transcriptionRouter,
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

    // MARK: Meetings

    var selectedMeeting: MeetingManifest? {
        meetingManifests.first { $0.id == selectedMeetingID }
    }

    func reloadMeetings() async {
        do {
            meetingManifests = try await meetingStore.list()
            if let selectedMeetingID, !meetingManifests.contains(where: { $0.id == selectedMeetingID }) {
                self.selectedMeetingID = nil
            }
        } catch {
            saveError = "Could not load meetings: \(error.localizedDescription)"
        }
    }

    func renameMeeting(id: MeetingID, title: String) async {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        if let meetings {
            do {
                if try await meetings.renameSession(id: id, title: cleaned) {
                    await reloadMeetings()
                    return
                }
            } catch {
                saveError = "Could not rename meeting: \(error.localizedDescription)"
                return
            }
        }
        guard !cleaned.isEmpty, var meeting = meetingManifests.first(where: { $0.id == id }) else { return }
        meeting.title = cleaned
        do {
            try await meetingStore.save(meeting)
            await reloadMeetings()
        } catch {
            saveError = "Could not rename meeting: \(error.localizedDescription)"
        }
    }

    func deleteMeeting(id: MeetingID) async {
        do {
            try await meetingStore.delete(id: id)
            if selectedMeetingID == id { selectedMeetingID = nil }
            await reloadMeetings()
        } catch {
            saveError = "Could not delete meeting: \(error.localizedDescription)"
        }
    }

    func generateMeetingText(
        id: MeetingID,
        kind: MeetingTextKind,
        progress: @escaping @Sendable (MeetingTextProgress) -> Void
    ) async throws -> String {
        var meeting = try await meetingStore.load(id: id)
        guard let textModel = ProviderFactory.textModel(settings.textModel, keychain: keychain) else {
            throw MeetingGenerationError.noTextModel
        }
        let text = try await MeetingTextGenerator().generate(
            transcript: meeting.segments,
            kind: kind,
            budget: MeetingTextBudget(settings: settings.meetings),
            model: textModel,
            progress: progress
        )
        if kind == .summary { meeting.summary = text }
        else { meeting.actionItems = text }
        if let meetings, try await meetings.saveGeneratedTextToSession(id: id, text: text, kind: kind) {
            await reloadMeetings()
            return text
        }
        try await meetingStore.save(meeting)
        await reloadMeetings()
        return text
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

    private func recoverUnfinishedMeetings() async {
        do {
            for var meeting in try await meetingStore.list() where meeting.state == .recording || meeting.state == .paused {
                meeting.state = .interrupted
                meeting.endedAt = meeting.endedAt ?? Date()
                try await meetingStore.save(meeting)
            }
            await reloadMeetings()
        } catch {
            saveError = "Could not recover meetings: \(error.localizedDescription)"
        }
    }

    private func applyMeetingRetention() async {
        do {
            let meetings = try await meetingStore.list()
            let expired = MeetingRetention.pruneCandidates(meetings, policy: settings.meetings.deleteAfter, now: Date())
            for id in expired { try await meetingStore.delete(id: id) }
            await reloadMeetings()
        } catch {
            saveError = "Could not remove old meetings: \(error.localizedDescription)"
        }
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

    /// Returns false, and sets `saveError`, when the Keychain refused the write.
    @discardableResult
    func saveKey(_ value: String, account: String) -> Bool {
        do {
            try keychain.write(value, account: account)
            if account == "speech-openai" {
                speechAPIKeyGeneration &+= 1
                rebuildSpeechTranscriber()
            }
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
        var status: [PermissionKind: Bool] = [:]
        for kind in PermissionKind.allCases {
            status[kind] = kind == .systemAudioRecording ? systemAudioGrantedThisRun : Permissions.isGranted(kind)
        }
        if permissionStatus != status { permissionStatus = status }
        let granted = Permissions.allGranted
        if permissionsGranted != granted { permissionsGranted = granted }
    }

    func setSystemAudioCaptureObserved(_ granted: Bool) {
        systemAudioGrantedThisRun = granted
        permissionStatus[.systemAudioRecording] = granted
        if granted { systemAudioPermissionFailed = false }
    }

    func noteSystemAudioCaptureStartFailure() {
        systemAudioGrantedThisRun = false
        permissionStatus[.systemAudioRecording] = false
        systemAudioPermissionFailed = true
    }
}
