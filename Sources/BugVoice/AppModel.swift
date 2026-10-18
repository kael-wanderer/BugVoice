import AppKit
import BugVoiceMac
import Carbon
import Foundation
import Observation
import ServiceManagement
import SwiftUI
import VoiceCore
import WhisperEngine

private enum MeetingGenerationError: LocalizedError {
    case noTextModel
    var errorDescription: String? { "Choose a model for Meeting notes in Settings → Models." }
}

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
    case capture, library, personalize, connect, bottom

    var title: String? {
        switch self {
        case .capture: "Capture"
        case .library: "Library"
        case .personalize: "Personalize"
        case .connect: "Connect"
        case .bottom: nil
        }
    }

    var pages: [Page] {
        switch self {
        case .capture: [.dictation, .insights]
        case .library: [.meetings, .notes, .upload]
        case .personalize: [.style, .dictionary]
        case .connect: [.integrations]
        case .bottom: [.settings, .help]
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
    @ObservationIgnored private var meetingStore: MeetingStore { MeetingStore(root: paths.meetings) }
    @ObservationIgnored private(set) var whisper: WhisperKitTranscriber
    @ObservationIgnored private(set) var priorityTranscriber: PriorityTranscriber
    @ObservationIgnored let transcriptionRouter: TranscriptionRouter
    @ObservationIgnored private var systemAudioGrantedThisRun = false

    @ObservationIgnored lazy var searchIndexer = SearchIndexer(model: self)
    /// The MCP server for coding agents (Settings › Agents).
    @ObservationIgnored lazy var mcp = MCPService(model: self)

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
    var saveError: String?

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
    @ObservationIgnored private var meetingTextTasks: [MeetingID: Task<String, Error>] = [:]

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
    private func applyPendingKeyMoves() {
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

    private func loadLibrary() async {
        switch await libraryStore.load() {
        case .loaded(let file):
            library = file
        case .missing:
            library = LibraryFile()
        case .reset(let backupName):
            library = LibraryFile()
            saveError = "Folders file was damaged and has been reset. The old file was kept as \(backupName)."
        case .newer(let file):
            library = file
            libraryReadOnly = true
            saveError = LibraryFolderError.readOnly.errorDescription
        }
    }

    private func saveLibrary() async {
        guard !libraryReadOnly else { return }
        do {
            try await libraryStore.save(library)
        } catch {
            saveError = "Could not save folders: \(error.localizedDescription)"
        }
    }

    var sortedFolders: [LibraryFolder] { LibraryFolders.sorted(library.folders) }

    /// nil for Unfiled, including ids of deleted folders.
    func folderName(_ id: FolderID?) -> String? { library.folder(id)?.name }

    var meetingsFolderFilter: FolderFilter {
        get { FolderFilter(rawValue: settings.library.meetingsFolderFilter).resolved(known: library.knownIDs) }
        set { settings.library.meetingsFolderFilter = newValue.rawValue }
    }

    var notesFolderFilter: FolderFilter {
        get { FolderFilter(rawValue: settings.library.notesFolderFilter).resolved(known: library.knownIDs) }
        set { settings.library.notesFolderFilter = newValue.rawValue }
    }

    var meetingTagCatalog: [TagCount] { LibraryProjection.catalog(meetingManifests) }
    var noteTagCatalog: [TagCount] { LibraryProjection.catalog(notesController.notes) }
    var allTagCatalog: [TagCount] {
        var totals: [String: Int] = [:]
        for tag in meetingTagCatalog + noteTagCatalog { totals[tag.name, default: 0] += tag.count }
        return totals.map { TagCount(name: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
    }

    var tagRows: [TagRow] {
        LibraryProjection.tagRows(notes: noteTagCatalog, meetings: meetingTagCatalog, file: library)
    }

    var tagColors: [String: TagColor] {
        var colors: [String: TagColor] = [:]
        for tag in library.tags { colors[tag.name] = tag.color }
        return colors
    }

    func createTag(_ raw: String) async -> TagCreateResult {
        guard !libraryReadOnly else { return .invalid }
        let result = LibraryTags.create(raw, inUse: Set(allTagCatalog.map(\.name)), in: &library)
        if case .created = result { await saveLibrary() }
        return result
    }

    func setTagColor(_ color: TagColor?, for name: String) async {
        guard !libraryReadOnly else { return }
        LibraryTags.setColor(color, for: name, in: &library)
        await saveLibrary()
    }

    func renameTag(_ old: String, to raw: String) async -> TagRenameOutcome {
        guard !libraryReadOnly else { return .failed(count: 0) }
        guard let new = TagName.normalize(raw) else { return .invalid }
        guard old != new else { return .unchanged }
        if allTagCatalog.contains(where: { $0.name == new }) || library.tags.contains(where: { $0.name == new }) {
            return .needsMerge(target: new,
                              notes: notesController.notes.filter { $0.frontMatter.tags.contains(old) }.count,
                              meetings: meetingManifests.filter { $0.tags.contains(old) }.count)
        }
        return await applyTagEdit(old, to: new)
    }

    func mergeTag(_ old: String, into new: String) async -> TagRenameOutcome {
        guard !libraryReadOnly else { return .failed(count: 0) }
        guard old != new else { return .unchanged }
        return await applyTagEdit(old, to: new)
    }

    func deleteTag(_ name: String) async -> TagRenameOutcome {
        guard !libraryReadOnly else { return .failed(count: 0) }
        return await applyTagEdit(name, to: nil)
    }

    private func applyTagEdit(_ old: String, to new: String?) async -> TagRenameOutcome {
        func edited(_ tags: [String]) -> [String] {
            if let new { return TagEdit.rename(old, to: new, in: tags) }
            return TagEdit.remove(old, from: tags)
        }
        var failures = 0
        for note in notesController.notes where note.frontMatter.tags.contains(old) {
            do {
                try await notesController.setLabels(id: note.id, folderID: note.frontMatter.folderID,
                                                    tags: edited(note.frontMatter.tags))
                if !(await notesController.flush(id: note.id)) {
                    // Keep the old tag visible on failed items so the same
                    // action can be retried. The editor's body stays intact.
                    try await notesController.setLabels(id: note.id, folderID: note.frontMatter.folderID,
                                                        tags: note.frontMatter.tags)
                    failures += 1
                }
            } catch {
                failures += 1
            }
        }
        for meeting in meetingManifests where meeting.tags.contains(old) || meeting.suggestedTags.contains(old) {
            let tags = edited(meeting.tags)
            let suggestions = edited(meeting.suggestedTags).filter { !tags.contains($0) }
            await setMeetingLabels(id: meeting.id, folderID: meeting.folderID, tags: tags, suggestedTags: suggestions)
            await reloadMeetings()
            guard let current = meetingManifests.first(where: { $0.id == meeting.id }) else {
                failures += 1
                continue
            }
            if current.tags.contains(old) || current.suggestedTags.contains(old) { failures += 1 }
        }
        guard failures == 0 else {
            saveError = "Could not update \(failures) items. Try again."
            return .failed(count: failures)
        }
        if let new { LibraryTags.rename(old, to: new, in: &library) }
        else { LibraryTags.delete(old, in: &library) }
        await saveLibrary()
        notesTagFilter = edited(notesTagFilter)
        meetingTagFilter = edited(meetingTagFilter)
        return .renamed
    }

    func createFolder(_ name: String) async -> Result<LibraryFolder, LibraryFolderError> {
        guard !libraryReadOnly else { return .failure(.readOnly) }
        do {
            let folder = try LibraryFolders.create(name, in: &library)
            await saveLibrary()
            return .success(folder)
        } catch let error as LibraryFolderError {
            return .failure(error)
        } catch {
            return .failure(.empty)
        }
    }

    func renameFolder(_ id: FolderID, to name: String) async -> LibraryFolderError? {
        guard !libraryReadOnly else { return .readOnly }
        do {
            try LibraryFolders.rename(id, to: name, in: &library)
            await saveLibrary()
            return nil
        } catch let error as LibraryFolderError {
            return error
        } catch {
            return .missing
        }
    }

    /// Removes the folder from `library.json` only; its items show as Unfiled.
    func deleteFolder(_ id: FolderID) async {
        guard !libraryReadOnly else { return }
        LibraryFolders.delete(id, in: &library)
        if FolderFilter(rawValue: settings.library.meetingsFolderFilter) == .folder(id) { meetingsFolderFilter = .all }
        if FolderFilter(rawValue: settings.library.notesFolderFilter) == .folder(id) { notesFolderFilter = .all }
        await saveLibrary()
    }

    func setLastUploadFolder(_ id: FolderID?) async {
        guard library.lastUploadFolderID != id else { return }
        library.lastUploadFolderID = id
        await saveLibrary()
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

    // MARK: Meetings

    var selectedMeeting: MeetingManifest? {
        meetingManifests.first { $0.id == selectedMeetingID }
    }

    func reloadMeetings() async {
        do {
            let directories = try FileManager.default.contentsOfDirectory(
                at: paths.meetings,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            var listed: [MeetingManifest] = []
            for directory in directories {
                guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                    !FileManager.default.fileExists(
                        atPath: directory.appendingPathComponent(".upload-cancelled").path),
                    FileManager.default.fileExists(
                        atPath: directory.appendingPathComponent("meeting.json").path)
                else { continue }
                do {
                    let meeting = try await meetingStore.load(
                        id: MeetingID(rawValue: directory.lastPathComponent))
                    if !(meeting.source == .upload && meeting.state == .interrupted) {
                        listed.append(meeting)
                    }
                } catch {
                    saveError = "Could not load meetings: \(error.localizedDescription)"
                }
            }
            meetingManifests = listed.sorted { $0.startedAt > $1.startedAt }
            // Every meeting folder on disk keeps its voices, even one that failed to load.
            await pruneKnownVoices(keeping: Set(directories.map { MeetingID(rawValue: $0.lastPathComponent) }))
            uploads?.reconcile(meetingManifests)
            searchIndexer.listLoaded(.meeting)
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
        if let uploads {
            do {
                if try await uploads.renameSession(id: id, title: cleaned) {
                    await reloadMeetings()
                    return
                }
            } catch {
                saveError = "Could not rename meeting: \(error.localizedDescription)"
                return
            }
        }
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
        guard !cleaned.isEmpty, var meeting = meetingManifests.first(where: { $0.id == id }) else {
            return
        }
        meeting.title = cleaned
        do {
            try await meetingStore.save(meeting)
            await reloadMeetings()
        } catch {
            saveError = "Could not rename meeting: \(error.localizedDescription)"
        }
    }

    /// Same routing as rename: a live recording or upload session owns its manifest.
    func setMeetingLabels(id: MeetingID, folderID: FolderID?, tags: [String], suggestedTags: [String]? = nil) async {
        let remainingSuggestions = suggestedTags
            ?? meetingManifests.first(where: { $0.id == id }).map { meeting in
                meeting.suggestedTags.filter { !tags.contains($0) }
            }
        do {
            if let uploads,
               try await uploads.setLabelsInSession(id: id, folderID: folderID, tags: tags, suggestedTags: remainingSuggestions) {
                await reloadMeetings()
                return
            }
            if let meetings,
               try await meetings.setLabelsInSession(id: id, folderID: folderID, tags: tags, suggestedTags: remainingSuggestions) {
                await reloadMeetings()
                return
            }
            var meeting = try await meetingStore.load(id: id)
            meeting.folderID = folderID
            meeting.tags = tags
            if let remainingSuggestions { meeting.suggestedTags = remainingSuggestions }
            try await meetingStore.save(meeting)
            await reloadMeetings()
        } catch {
            saveError = "Could not update meeting: \(error.localizedDescription)"
        }
    }

    /// Notes from the meeting detail page. The meeting window's session saves them while it owns the meeting.
    func setMeetingNotes(id: MeetingID, notes: String) async {
        do {
            if let meetings, try await meetings.setNotesInSession(id: id, notes: notes) {
                await reloadMeetings()
                return
            }
            var meeting = try await meetingStore.load(id: id)
            guard meeting.notes != notes else { return }
            meeting.notes = notes
            try await meetingStore.save(meeting)
            await reloadMeetings()
        } catch {
            saveError = "Could not save notes: \(error.localizedDescription)"
        }
    }

    /// Show English from the meeting detail page. Routed like notes.
    func setMeetingShowEnglish(id: MeetingID, show: Bool) async {
        do {
            if let meetings, try await meetings.setShowEnglishInSession(id: id, show: show) {
                await reloadMeetings()
                return
            }
            var meeting = try await meetingStore.load(id: id)
            guard meeting.showEnglish != show else { return }
            meeting.showEnglish = show
            try await meetingStore.save(meeting)
            await reloadMeetings()
        } catch {
            saveError = "Could not update meeting: \(error.localizedDescription)"
        }
    }

    func setNoteLabels(id: NoteID, folderID: FolderID?, tags: [String]) async {
        do {
            try await notesController.setLabels(id: id, folderID: folderID, tags: tags)
        } catch {
            saveError = "Could not update note: \(error.localizedDescription)"
        }
    }

    func deleteMeeting(id: MeetingID) async {
        // A finished window may still own the manifest while a split is running.
        // Drain it before deleting so its eventual session save cannot recreate the folder.
        if let task = speakerTasks[id] {
            task.cancel()
            await task.value
        }
        if let uploads,
            let job = uploads.queue.jobs.first(where: { $0.meetingID == id && !$0.state.isTerminal })
        {
            await uploads.cancel(job.id)
            return
        }
        do {
            if meetingManifests.first(where: { $0.id == id })?.source == .upload {
                let directory = paths.meetings.appendingPathComponent(id.rawValue)
                let marker = directory.appendingPathComponent(".upload-cancelled")
                try Data().write(to: marker)
                let handle = try FileHandle(forWritingTo: marker)
                try handle.synchronize()
                try handle.close()
                try UploadCancellationMarker.sync(directory)
            }
            await cancelMeetingText(id: id)
            try await meetingStore.delete(id: id)
            if selectedMeetingID == id { selectedMeetingID = nil }
            await reloadMeetings()
        } catch {
            saveError = "Could not delete meeting: \(error.localizedDescription)"
        }
    }

    func retryMeeting(_ meeting: MeetingManifest) {
        if meeting.source == .upload {
            uploads?.retry(meeting)
        } else {
            Task { await meetings?.recover(id: meeting.id) }
        }
    }

    func generateMeetingText(
        id: MeetingID,
        kind: MeetingTextKind,
        progress: @escaping @Sendable (MeetingTextProgress) -> Void
    ) async throws -> String {
        let directory = paths.meetings.appendingPathComponent(id.rawValue)
        guard meetingTextTasks[id] == nil,
            FileManager.default.fileExists(atPath: directory.appendingPathComponent("meeting.json").path),
            !FileManager.default.fileExists(
                atPath: directory.appendingPathComponent(".upload-cancelled").path)
        else {
            throw CancellationError()
        }
        let task = Task { try await self.performMeetingText(id: id, kind: kind, progress: progress) }
        meetingTextTasks[id] = task
        defer { meetingTextTasks[id] = nil }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// True while a summary or action-items text is being written for this meeting.
    func isWritingMeetingText(id: MeetingID) -> Bool {
        meetingTextTasks[id] != nil
    }

    func cancelMeetingText(id: MeetingID) async {
        let task = meetingTextTasks[id]
        task?.cancel()
        _ = try? await task?.value
    }

    private func performMeetingText(
        id: MeetingID,
        kind: MeetingTextKind,
        progress: @escaping @Sendable (MeetingTextProgress) -> Void
    ) async throws -> String {
        let original = try await meetingStore.load(id: id)
        let names = MeetingSpeakers.names(in: original)
        guard let textModel = await meetingTextModel() else {
            throw MeetingGenerationError.noTextModel
        }
        let text = try await MeetingTextGenerator().generate(
            transcript: original.segments,
            kind: kind,
            budget: MeetingTextBudget(settings: settings.meetings),
            notes: original.notes,
            model: textModel,
            progress: progress
        )
        try Task.checkCancellation()
        if let uploads, try await uploads.saveGeneratedTextToSession(id: id, text: text, kind: kind, names: names) {
            await reloadMeetings()
            if kind == .summary {
                let suggestionModel = textModel
                Task { await suggestTags(for: id, summary: text, model: suggestionModel) }
            }
            return text
        }
        if let meetings, try await meetings.saveGeneratedTextToSession(id: id, text: text, kind: kind, names: names) {
            await reloadMeetings()
            if kind == .summary {
                let suggestionModel = textModel
                Task { await suggestTags(for: id, summary: text, model: suggestionModel) }
            }
            return text
        }
        var current = try await meetingStore.load(id: id)
        try Task.checkCancellation()
        current.setGeneratedText(text, kind: kind, names: names)
        try await meetingStore.save(current)
        await reloadMeetings()
        if kind == .summary {
            let suggestionModel = textModel
            Task { await suggestTags(for: id, summary: text, model: suggestionModel) }
        }
        return text
    }

    /// The Meetings model (Settings › Models), or nil when none is set.
    func meetingTextModel() async -> (any TextModel)? {
        if case .cli(let tool) = settings.models.meetings.engine, cliInfo[tool] == nil {
            await refreshCLIs()
        }
        let plan = plan(for: .meetings)
        guard var textModel = ProviderFactory.textModel(plan, credentials: credentials) else { return nil }
        if case .connection(_, _, _, let disableThinking, _) = plan, disableThinking {
            textModel = ThinkingOverride(base: textModel, disableThinking: true)
        }
        return textModel
    }

    /// Asks the Meetings model for up to 3 existing tags. Failures stay silent.
    private func suggestTags(for id: MeetingID, summary: String, model textModel: any TextModel) async {
        let allowed = allTagCatalog.map(\.name)
        guard !allowed.isEmpty, !summary.isEmpty,
              let meeting = meetingManifests.first(where: { $0.id == id }) else { return }
        guard let answer = try? await textModel.clean(TagSuggestion.request(summary: summary, allowed: allowed)) else { return }
        let suggestions = TagSuggestion.parse(answer, allowed: allowed, existing: meeting.tags)
        guard !suggestions.isEmpty else { return }
        let current = meetingManifests.first(where: { $0.id == id }) ?? meeting
        await setMeetingLabels(id: id, folderID: current.folderID, tags: current.tags, suggestedTags: suggestions)
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
        await searchIndexer.reconcileHistory()
    }

    private func recoverUnfinishedMeetings() async {
        do {
            // Scan marker paths BEFORE decoding manifests, even if a manifest is corrupt.
            let directories = try FileManager.default.contentsOfDirectory(
                at: paths.meetings,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            var blocked: Set<MeetingID> = []
            for directory in directories {
                guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                    continue
                }
                let marker = directory.appendingPathComponent(".upload-cancelled")
                if FileManager.default.fileExists(atPath: marker.path) {
                    do {
                        try FileManager.default.removeItem(at: directory)
                    } catch {
                        blocked.insert(MeetingID(rawValue: directory.lastPathComponent))
                        saveError = UploadFailure.cleanup.localizedDescription
                    }
                }
            }
            // Load individually: a marked folder is never loaded; one corrupt folder cannot stop all recovery.
            var all: [MeetingManifest] = []
            for directory in directories {
                let id = MeetingID(rawValue: directory.lastPathComponent)
                guard !blocked.contains(id),
                    FileManager.default.fileExists(
                        atPath: directory.appendingPathComponent("meeting.json").path)
                else { continue }
                do {
                    all.append(try await meetingStore.load(id: id))
                } catch {
                    saveError = "Could not recover meetings: \(error.localizedDescription)"
                }
            }
            let plan = UploadRecoveryPlan(all)
            for id in plan.discard {
                let directory = paths.meetings.appendingPathComponent(id.rawValue)
                // Mark before removing, so an unsuccessful cleanup remains excluded on the next launch.
                let marker = directory.appendingPathComponent(".upload-cancelled")
                do {
                    try Data().write(to: marker)
                    let handle = try FileHandle(forWritingTo: marker)
                    try handle.synchronize()
                    try handle.close()
                    try UploadCancellationMarker.sync(directory)
                    try await meetingStore.delete(id: id)
                } catch {
                    blocked.insert(id)
                    saveError = UploadFailure.cleanup.localizedDescription
                }
            }
            for meeting in plan.ready {
                let directory = paths.meetings.appendingPathComponent(meeting.id.rawValue)
                let audio = directory.appendingPathComponent("audio.m4a")
                // Validate the durable replacement before discarding a redundant journal.
                if let metadata = try? await MediaAudioDecoder.probe(audio),
                    abs(metadata.duration - meeting.duration) < 0.2
                {
                    do {
                        try await UploadAudioFinalizer(meetingDirectory: directory).cleanupCapture()
                    } catch {
                        saveError = "Could not remove redundant upload audio: \(error.localizedDescription)"
                    }
                }
            }
            for var meeting in all
            where meeting.source == .recording
                && (meeting.state == .recording || meeting.state == .paused)
            {
                meeting.state = .interrupted
                meeting.endedAt = meeting.endedAt ?? Date()
                try await meetingStore.save(meeting)
            }
            uploads?.restore(plan.resume.filter { !blocked.contains($0.id) })
            await reloadMeetings()
        } catch {
            saveError = "Could not recover meetings: \(error.localizedDescription)"
            uploads?.restore([])
        }
    }

    private func applyMeetingRetention() async {
        await reloadMeetings()
        do {
            let expired = MeetingRetention.pruneCandidates(
                meetingManifests, policy: settings.meetings.deleteAfter, now: Date())
            for id in expired { try await meetingStore.delete(id: id) }
            await reloadMeetings()
        } catch {
            saveError = "Could not remove old meetings: \(error.localizedDescription)"
        }
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
