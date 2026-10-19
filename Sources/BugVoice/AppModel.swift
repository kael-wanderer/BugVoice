import AppKit
import BugVoiceMac
import Carbon
import Foundation
import Observation
import ServiceManagement
import SwiftUI
import VoiceCore
import WhisperEngine

/// The last Test connection result this session. Not saved.
enum ConnectionStatus: Equatable {
    case reachable(models: [String])
    case failed(String)
}

enum TagRenameOutcome: Equatable {
    case renamed, unchanged, invalid
    case needsMerge(target: String, notes: Int, meetings: Int)
    case failed(count: Int)
}

enum LibrarySheetTab: String, Identifiable {
    case folders, tags
    var id: String { rawValue }
}

/// Main-window pages.
enum Page: String, CaseIterable, Identifiable {
    case dictation, insights, meetings, notes, upload, style, dictionary, integrations, settings, help
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dictation: "Dictation"
        case .insights: "Insights"
        case .meetings: "Meetings"
        case .notes: "Scratchpad"
        case .upload: "Upload"
        case .style: "Style"
        case .dictionary: "Dictionary"
        case .integrations: "Integrations"
        case .settings: "Settings"
        case .help: "Help"
        }
    }
    var symbol: String {
        switch self {
        case .dictation: "mic"
        case .insights: "chart.bar"
        case .meetings: "waveform.path"
        case .notes: "note.text"
        case .upload: "square.and.arrow.up"
        case .style: "paintbrush.pointed"
        case .dictionary: "character.book.closed"
        case .integrations: "puzzlepiece.extension"
        case .settings: "gearshape"
        case .help: "questionmark.circle"
        }
    }
}

enum SidebarGroup: CaseIterable {
    case capture, library, personalize, bottom

    var title: String? {
        switch self {
        case .capture: "Capture"
        case .library: "Library"
        case .personalize: "Personalize"
        case .bottom: nil
        }
    }

    var pages: [Page] {
        switch self {
        case .capture: [.dictation, .insights]
        case .library: [.meetings, .notes, .upload]
        case .personalize: [.style, .dictionary]
        case .bottom: [.settings]
        }
    }
}

@MainActor
@Observable
final class AppModel {
    let appearance = AppearanceStore()
    let paths = AppPaths.standard()
    /// API keys. See `CredentialStore`.
    let credentials = CredentialStore(url: AppPaths.standard().credentials)
    @ObservationIgnored let notesStore: NotesStore
    @ObservationIgnored let notesController: NotesController
    @ObservationIgnored let store = SettingsStore(url: AppPaths.standard().settings)
    @ObservationIgnored let historyLog = HistoryLog(url: AppPaths.standard().history)
    @ObservationIgnored let insightsStore = InsightsStore(url: AppPaths.standard().insights)
    @ObservationIgnored let dictionaryStore = DictionaryStore(url: AppPaths.standard().dictionary)
    @ObservationIgnored let libraryStore = LibraryStore(url: AppPaths.standard().library)
    @ObservationIgnored private var dictionaryRevision = 0
    @ObservationIgnored var meetingStore: MeetingStore { MeetingStore(root: paths.meetings) }
    @ObservationIgnored private(set) var whisper: WhisperKitTranscriber
    @ObservationIgnored private(set) var priorityTranscriber: PriorityTranscriber
    @ObservationIgnored let transcriptionRouter: TranscriptionRouter
    @ObservationIgnored private var systemAudioGrantedThisRun = false

    @ObservationIgnored lazy var searchIndexer = SearchIndexer(model: self)
    /// The MCP server for coding agents (Settings › Agents).
    @ObservationIgnored lazy var mcp = MCPService(model: self)

    @ObservationIgnored lazy var backup = BackupController(model: self)
    var restoreMessage: String?

    var settings = AppSettings() {
        didSet {
            guard settings != oldValue, !isLoadingSettings else { return }
            settingsDidChange(from: oldValue)
        }
    }
    var insightsPeriod: InsightsPeriod = .all
    var dictionaryTab: DictionaryTab = .words
    var dictionaryAddRequest: UInt64 = 0
    var dictionaryAddTarget: DictionaryTab?
    func requestDictionaryAdd(_ tab: DictionaryTab? = nil) {
        if let tab { dictionaryTab = tab }
        dictionaryAddTarget = dictionaryTab
        dictionaryAddRequest &+= 1
    }
    var scratchpadAskRequest: UInt64 = 0
    var settingsTab: SettingsTab = .general
    var dictionary = DictionaryFile()
    var dictionaryReadOnly = false
    var vocabulary = Vocabulary()
    var history: [HistoryEntry] = []
    /// Daily usage totals for the Insights page.
    var insights = InsightsFile()
    /// True when `insights.json` was written by a newer BugVoice: shown, never written.
    var insightsReadOnly = false
    var meetingManifests: [MeetingManifest] = []
    struct MeetingJump: Equatable {
        var id: MeetingID
        var start: Double
        var lineIDs: Set<String>
        var play = true
    }
    var pendingMeetingJump: MeetingJump?

    func openMeeting(_ jump: MeetingJump) {
        guard meetingManifests.contains(where: { $0.id == jump.id }),
              FileManager.default.fileExists(atPath: paths.meetings.appendingPathComponent(jump.id.rawValue).appendingPathComponent("meeting.json").path) else { return }
        selectedMeetingID = jump.id
        pendingMeetingJump = jump
        openMainWindow(.meetings)
    }

    var meetingDetailTab: MeetingDetailTab = .transcript
    var meetingSelectionRequest: UInt64 = 0
    var notesSearchQuery = ""
    var selectedNoteID: NoteID?
    var selectedMeetingID: MeetingID?
    var meetingSearchQuery = ""
    /// Folders from `library.json`. Notes and meetings carry their own labels.
    var library = LibraryFile()
    /// True when `library.json` was written by a newer BugVoice: shown, never written.
    var libraryReadOnly = false
    var librarySheet: LibrarySheetTab?
    var meetingTagFilter: [String] = []
    var notesTagFilter: [String] = []
    /// The latest dictation, for the menu preview and *Paste last*. A
    /// secure-field result is stored without its text.
    var lastResult: DictationResult?
    var sidebarHidden = UserDefaults.standard.bool(forKey: "BugVoice.sidebarHidden") {
        didSet { UserDefaults.standard.set(sidebarHidden, forKey: "BugVoice.sidebarHidden") }
    }
    /// Widths the owner dragged the sidebar and the Meetings/Scratchpad list
    /// to; nil means the default for the text size.
    var sidebarDraggedWidth = UserDefaults.standard.object(forKey: "BugVoice.sidebarWidth") as? Double {
        didSet { UserDefaults.standard.set(sidebarDraggedWidth, forKey: "BugVoice.sidebarWidth") }
    }
    var listPaneDraggedWidth = UserDefaults.standard.object(forKey: "BugVoice.listPaneWidth") as? Double {
        didSet { UserDefaults.standard.set(listPaneDraggedWidth, forKey: "BugVoice.listPaneWidth") }
    }
    var sidebarWidth: Double { ShellLayout.sidebarWidth(scale: settings.appearance.textScale, dragged: sidebarDraggedWidth) }
    var listPaneWidth: Double { ShellLayout.listPaneWidth(scale: settings.appearance.textScale, dragged: listPaneDraggedWidth) }
    var searchFocusRequest: UInt64 = 0
    var mainWindowIsKey = false
    var mainContentHeight: CGFloat = ShellLayout.minimumWindowHeight
    /// The title bar search text. On Meetings, Scratchpad, and Dictation it
    /// also filters that page's list.
    var searchQuery = "" {
        didSet {
            switch page {
            case .meetings: meetingSearchQuery = searchQuery
            case .notes: notesSearchQuery = searchQuery
            case .dictation: dictationSearchQuery = searchQuery
            default: break
            }
        }
    }
    var dictationSearchQuery = ""
    var searchIsPresented = false
    var searchFieldFrame: CGRect = .zero
    var searchResultsFrame: CGRect = .zero
    var dictationHighlight: UUID?

    func open(_ hit: SearchHit) {
        searchIsPresented = false
        searchQuery = ""
        switch hit.target {
        case .meeting(let id, let part, let lineID):
            guard let meeting = meetingManifests.first(where: { $0.id == id }) else { return }
            meetingsFolderFilter = .all
            meetingTagFilter = []
            meetingSearchQuery = ""
            switch part {
            case .summary: meetingDetailTab = .summary
            case .actionItems: meetingDetailTab = .actionItems
            case .myNotes: meetingDetailTab = .notes
            case .transcript: meetingDetailTab = .transcript
            default: break
            }
            if part == nil {
                pendingMeetingJump = nil
                meetingSelectionRequest &+= 1
                selectedMeetingID = id
                openMainWindow(.meetings)
            } else {
                let start = meeting.segments.first(where: { $0.id == lineID })?.start ?? 0
                openMeeting(MeetingJump(id: id, start: start, lineIDs: lineID.map { [$0] } ?? [], play: false))
            }
        case .note(let id):
            guard notesController.notes.contains(where: { $0.id == id }) else { return }
            notesFolderFilter = .all
            notesTagFilter = []
            notesSearchQuery = ""
            selectedNoteID = id
            openMainWindow(.notes)
        case .dictation(let id):
            dictationHighlight = id
            openMainWindow(.dictation)
        case .settings(let section):
            guard let tab = SettingsTab(rawValue: section) else { return }
            settingsTab = tab
            openMainWindow(.settings)
        }
    }
    func toggleSidebar() { withAnimation(.easeInOut(duration: 0.2)) { sidebarHidden.toggle() } }
    var page: Page = .dictation {
        didSet {
            guard page != oldValue else { return }
            // A search belongs to the page it was typed on.
            searchQuery = ""
            meetingSearchQuery = ""
            notesSearchQuery = ""
            dictationSearchQuery = ""
        }
    }
    var speechState: WhisperKitTranscriber.LoadState = .notLoaded
    /// Coding CLIs found on this Mac, looked up at launch and when Settings → Models opens.
    var cliInfo: [CLITool: CLIInfo] = [:]
    var connectionStatus: [String: ConnectionStatus] = [:]
    var hotkeyActive = false
    /// Global shortcuts another app already holds, e.g. "⌃⌥V Paste last".
    var unavailableShortcuts: [String] = []
    var unavailableShortcutActions: Set<ShortcutAction> = []
    /// True while the microphone is recording a dictation.
    var isListening = false
    var notesIsListening = false
    var notesRecordingStartedAt: Date?
    var notesFocusRequest: UInt64 = 0
    /// Open Scratchpad tabs. Saved to `settings.scratchpad` by slug.
    var scratchpadTabs = ScratchpadTabs()
    var scratchpadWindowIsVisible = false
    var scratchpadWindowIsKey = false
    /// The floating Scratchpad window. Set by the app delegate, which owns it.
    @ObservationIgnored weak var scratchpadWindow: ScratchpadWindowController?
    /// Notes made in the Scratchpad window this run; dropped when closed empty.
    @ObservationIgnored var scratchpadCreatedHere: Set<NoteID> = []
    /// The capsule at the bottom of the main window; see `showNotice`.
    var notice: String?
    @ObservationIgnored var noticeTask: Task<Void, Never>?
    var permissionsGranted = Permissions.allGranted
    var permissionStatus: [PermissionKind: Bool] = [:]
    var systemAudioPermissionFailed = false
    /// Core Audio could not list processes; meeting detection is off for this run.
    var meetingDetectionUnavailable = false
    /// The latest failure to save something (settings, Dictionary, history,
    /// API key, login item). The UI shows it and sets it back to nil once
    /// the user has seen it. Never cleared by a later success.
    var saveError: String? {
        didSet { if let saveError { Log.app.error("\(saveError, privacy: .public)") } }
    }

    @ObservationIgnored var onSettingsChanged: (() -> Void)?
    /// Brings up the main window. Set by the app delegate, which owns it.
    @ObservationIgnored var presentMainWindow: (() -> Void)?
    /// Brings up the Permissions window. Set by the app delegate.
    @ObservationIgnored var presentPermissionsWindow: (() -> Void)?
    /// Created by `bootstrap()` once settings are loaded.
    @ObservationIgnored private(set) var dictation: DictationController?
    @ObservationIgnored private(set) var meetings: MeetingController?
    @ObservationIgnored private(set) var meetingDetection: MeetingDetectionController?
    private(set) var uploads: UploadController?
    @ObservationIgnored private var isLoadingSettings = false
    @ObservationIgnored private var preparingEngine: WhisperKitTranscriber?
    @ObservationIgnored private var speechAPIKeyGeneration: UInt64 = 0
    @ObservationIgnored var meetingTextTasks: [MeetingID: Task<String, Error>] = [:]

    @ObservationIgnored let speakerSplitter = SpeakerSplitter(downloadBase: AppPaths.standard().models)
    @ObservationIgnored var speakerTasks: [MeetingID: Task<Void, Never>] = [:]
    @ObservationIgnored let voiceStore = KnownVoiceStore(url: AppPaths.standard().voices)
    @ObservationIgnored var voiceStoreErrorShown = false
    /// Saved voices for Settings › Meetings › Known voices.
    var knownVoices: [KnownVoice] = []

    init() {
        let notesStore = NotesStore(directory: AppPaths.standard().notes)
        self.notesStore = notesStore
        notesController = NotesController(store: notesStore)
        let engine = WhisperKitTranscriber(
            modelName: AppSettings().speech.whisperModel, downloadBase: AppPaths.standard().models)
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
        notesController.onSaved = { [weak self] id in self?.searchIndexer.schedule(.note(id), after: .seconds(30)) }
        notesController.onListLoaded = { [weak self] in
            self?.searchIndexer.listLoaded(.note)
            self?.pruneSelectedNote()
        }
        await notesController.reloadList()
        let loaded = store.load()
        importKeychainKeys(connections: loaded.models.connections)
        whisper = WhisperKitTranscriber(
            modelName: loaded.speech.whisperModel, downloadBase: paths.models)
        priorityTranscriber = PriorityTranscriber(
            base: ProviderFactory.transcriber(loaded.speech, whisper: whisper, credentials: credentials))
        await transcriptionRouter.replace(with: priorityTranscriber)
        // Loading is not a change: no save, no model reload, no login-item call.
        isLoadingSettings = true
        settings = loaded
        appearance.apply(loaded.appearance)
        applyAppIcon()
        isLoadingSettings = false
        applyPendingKeyMoves()
        await restoreScratchpadTabs()

        await loadDictionary()
        await loadInsights()
        await loadLibrary()
        startDictation()
        registerGlobalShortcuts()
        meetings = MeetingController(model: self)
        let detection = MeetingDetectionController(model: self)
        meetingDetection = detection
        detection.start()
        uploads = UploadController(model: self)
        refreshPermissions()
        if !permissionsGranted { openPermissionsWindow() }
        await applyRetention()
        await recoverUnfinishedMeetings()
        await applyMeetingRetention()
        // Only now are notes, meetings and history all loaded; no index file is pruned before this.
        searchIndexer.librariesDidLoad()
        Task { await prepareSpeech() }
        Task { await refreshCLIs() }
        // Last, so agents never see half-loaded notes or meetings.
        mcp.start()
        backup.startSchedule()
        if let restoreMessage {
            settingsTab = .storage
            openMainWindow(.settings)
            showNotice(restoreMessage)
            self.restoreMessage = nil
        }
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

    func openSpeechSettings() {
        settingsTab = .speech
        openMainWindow(.settings)
    }

    func openPermissionsWindow() {
        presentPermissionsWindow?()
    }

    private func applyAppIcon() {
        if let image = IconImages.appIcon(settings.appearance.appIcon) {
            NSApp.applicationIconImage = image
        }
    }

    // MARK: Settings

    private func settingsDidChange(from old: AppSettings) {
        appearance.apply(settings.appearance)
        if settings.appearance.appIcon != old.appearance.appIcon { applyAppIcon() }
        if settings.shortcuts != old.shortcuts { registerGlobalShortcuts() }
        if settings.models.search != old.models.search || settings.models.connections != old.models.connections {
            searchIndexer.backfill()
        }
        do {
            try store.save(settings)
        } catch {
            saveError = "Could not save settings: \(error.localizedDescription)"
        }
        if SpeechTranscriberConfiguration(
            settings: settings.speech, speechAPIKeyGeneration: speechAPIKeyGeneration)
            != SpeechTranscriberConfiguration(
                settings: old.speech, speechAPIKeyGeneration: speechAPIKeyGeneration)
        {
            rebuildSpeechTranscriber()
        }
        if settings.launchAtLogin != old.launchAtLogin { applyLaunchAtLogin() }
        if settings.historyRetention != old.historyRetention {
            Task { await applyRetention() }
        }
        if settings.meetings.deleteAfter != old.meetings.deleteAfter {
            Task { await applyMeetingRetention() }
        }
        if settings.scratchpad.keepOnTop != old.scratchpad.keepOnTop || settings.scratchpad.compact != old.scratchpad.compact {
            scratchpadWindow?.applyLayout()
        }
        if settings.backup != old.backup { backup.settingsChanged() }
        onSettingsChanged?()
    }

    private func rebuildSpeechTranscriber() {
        let speech = settings.speech
        let replacementWhisper = WhisperKitTranscriber(
            modelName: speech.whisperModel, downloadBase: paths.models)
        let replacement = PriorityTranscriber(
            base: ProviderFactory.transcriber(
                speech, whisper: replacementWhisper, credentials: credentials))
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

    func makePipeline(insertion: any InsertionTarget, feature: ModelFeature) -> DictationPipeline {
        DictationPipeline(
            transcriber: transcriptionRouter,
            cleanup: ProviderFactory.cleanupModel(
                plan(for: feature), credentials: credentials,
                fallbackTimeout: settings.models.dictationTimeoutSeconds
            ),
            insertion: insertion,
            focus: FocusInspector(),
            settings: settings,
            vocabulary: vocabulary
        )
    }

    // MARK: History

    func reloadHistory() async {
        history = await historyLog.load()
    }

    // MARK: Insights

    /// Loads `insights.json` and fills it from history the first time.
    /// Must finish before dictation starts, or a new dictation would be
    /// counted twice (once live, once from history).
    func loadInsights() async {
        let (file, issue) = await insightsStore.load()
        insights = file
        switch issue {
        case .none:
            break
        case .rebuiltFromCorrupt:
            saveError = "Insights file was damaged and has been rebuilt from history."
        case .newerVersion:
            insightsReadOnly = true
            return
        }
        do {
            insights = try await insightsStore.backfillIfNeeded(from: historyLog.load())
        } catch {
            saveError = "Could not save insights: \(error.localizedDescription)"
        }
    }

    func recordInsights(_ result: DictationResult, noteID: NoteID?) async {
        guard let delta = InsightsDelta.dictation(result, noteID: noteID) else { return }
        await addInsights(delta, at: result.startedAt)
    }

    func recordMeetingInsights(seconds: TimeInterval) async {
        guard let delta = InsightsDelta.meeting(seconds: seconds) else { return }
        await addInsights(delta, at: Date())
    }

    func resetInsights() async {
        guard !insightsReadOnly else { return }
        do {
            insights = try await insightsStore.reset()
        } catch {
            saveError = "Could not reset insights: \(error.localizedDescription)"
        }
    }

    private func addInsights(_ delta: InsightsDelta, at date: Date) async {
        guard !insightsReadOnly else { return }
        do {
            insights = try await insightsStore.add(delta, at: date)
        } catch {
            saveError = "Could not save insights: \(error.localizedDescription)"
        }
    }

    func deleteHistory(id: UUID) async {
        do {
            try await historyLog.delete(id: id)
        } catch {
            saveError = "Could not delete the dictation: \(error.localizedDescription)"
        }
        await reloadHistory()
        await searchIndexer.reconcileHistory()
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
        await searchIndexer.reconcileHistory()
    }

    // MARK: Dictionary

    func loadDictionary() async {
        do {
            try await dictionaryStore.migrateIfNeeded(vocabularyURL: paths.vocabulary)
        } catch {
            saveError = "Could not move vocabulary.txt into the Dictionary: \(error.localizedDescription)"
        }
        let (file, issue) = await dictionaryStore.load()
        dictionary = file
        vocabulary = Vocabulary(dictionary: file)
        dictionaryReadOnly = issue == .newerVersion
        switch issue {
        case .none, .newerVersion: break
        case .resetFromCorrupt:
            saveError = "Dictionary file was damaged and has been reset. The old file is kept next to it."
        }
    }

    func editDictionary(_ change: (inout DictionaryFile) throws -> Void) async rethrows {
        guard !dictionaryReadOnly else { return }
        var next = dictionary
        try change(&next)
        guard next != dictionary else { return }
        dictionary = next
        vocabulary = Vocabulary(dictionary: next)
        dictionaryRevision += 1
        do {
            try await dictionaryStore.save(next, revision: dictionaryRevision)
        } catch {
            saveError = "Could not save the Dictionary: \(error.localizedDescription)"
        }
    }

    // MARK: API keys

    /// Copies keys saved by older builds from the Keychain into
    /// `credentials.json` once, then deletes them from the Keychain. macOS
    /// asks for the login password one last time for each key it finds.
    private func importKeychainKeys(connections: [ModelConnection]) {
        guard !credentials.keychainImported else { return }
        let keychain = Keychain()
        let accounts = ["speech-openai", "openai", "anthropic"] + connections.map(\.credentialAccount)
        do {
            let moved = try credentials.importLegacy(accounts: accounts, read: keychain.read)
            for account in moved { try? keychain.write(nil, account: account) }
        } catch {
            saveError = "Could not copy the API keys from Keychain: \(error.localizedDescription)"
        }
    }

    /// Returns false, and sets `saveError`, when the key could not be saved.
    @discardableResult
    func saveKey(_ value: String, account: String) -> Bool {
        do {
            try credentials.write(value, account: account)
            if account == "speech-openai", settings.speech.engine == .openAICompatible {
                speechAPIKeyGeneration &+= 1
                rebuildSpeechTranscriber()
            }
            return true
        } catch {
            saveError = "Could not save the key: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: Permissions

    func refreshPermissions() {
        var status: [PermissionKind: Bool] = [:]
        for kind in PermissionKind.allCases {
            status[kind] =
                kind == .systemAudioRecording ? systemAudioGrantedThisRun : Permissions.isGranted(kind)
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
