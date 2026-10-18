import AppKit
import BugVoiceMac
import Foundation
import NaturalLanguage
import os
import VoiceCore

/// Ask logs counts only, never question, passage or answer text.
private let askLog = Logger(subsystem: "com.kael.bugvoice", category: "ask")

enum ScratchpadAIError: LocalizedError {
    case noModel, tooLong, empty

    var errorDescription: String? {
        switch self {
        case .noModel: "Choose a Notes model in Settings → Models."
        case .tooLong: "Select less text. Transforms handle up to 12,000 characters."
        case .empty: "The Notes model returned nothing."
        }
    }
}

/// One answer from the Notes model for the AI bar.
struct ScratchpadAnswer: Sendable {
    let output: String
    let modelName: String
    let seconds: Int
}

extension AppModel {
    // MARK: Tabs

    private var noteSlugs: [NoteID: String] {
        Dictionary(notesController.notes.map { ($0.id, $0.slug) }, uniquingKeysWith: { first, _ in first })
    }

    /// At launch: tabs from the saved slugs, or the first note when none were saved.
    func restoreScratchpadTabs() async {
        let saved = settings.scratchpad
        scratchpadTabs = .restore(openTabs: saved.openTabs, activeTab: saved.activeTab, slugs: noteSlugs)
        if saved.openTabs.isEmpty, let first = notesController.notes.first {
            scratchpadTabs.open(first.id)
        }
        if let active = scratchpadTabs.active { try? await notesController.select(id: active) }
    }

    func persistScratchpadTabs() {
        let saved = scratchpadTabs.saved(slugs: noteSlugs)
        if settings.scratchpad.openTabs != saved.openTabs { settings.scratchpad.openTabs = saved.openTabs }
        if settings.scratchpad.activeTab != saved.activeTab { settings.scratchpad.activeTab = saved.activeTab }
    }

    /// After the note list changes: drops tabs of deleted notes and saves
    /// new slugs after a rename.
    func pruneSelectedNote() {
        guard notesController.listError == nil else { return }
        if let selectedNoteID, !notesController.notes.contains(where: { $0.id == selectedNoteID }) {
            self.selectedNoteID = nil
        }
    }

    func syncScratchpadTabs() {
        pruneSelectedNote()
        guard notesController.listError == nil else { return }
        let before = scratchpadTabs.active
        scratchpadTabs.prune(existing: Set(notesController.notes.map(\.id)))
        if scratchpadTabs.active != before { Task { await showActiveTab() } }
        persistScratchpadTabs()
    }

    func openNoteTab(_ id: NoteID) async throws {
        try await notesController.select(id: id)
        scratchpadTabs.open(id)
        persistScratchpadTabs()
    }

    func closeNoteTab(_ id: NoteID) async {
        _ = await notesController.flush(id: id)
        scratchpadTabs.close(id)
        persistScratchpadTabs()
        await showActiveTab()
        await discardIfEmpty(id)
    }

    // MARK: Window

    /// Shows the Scratchpad window, on a new note when asked or when no tab is open.
    func openScratchpadWindow(newNote: Bool) async {
        scratchpadWindow?.show()
        if newNote || scratchpadTabs.active == nil {
            await newScratchpadNoteInWindow()
        } else if let active = scratchpadTabs.active, notesController.selectedNoteID != active {
            try? await notesController.select(id: active)
        }
        notesFocusRequest &+= 1
    }

    func openScratchpadAsk() async {
        await openScratchpadWindow(newNote: false)
        settings.scratchpad.aiBarShown = true
        scratchpadAskRequest &+= 1
    }

    /// A new note in the page's current folder, opened in a tab.
    func newScratchpadNoteInWindow() async {
        do {
            let note = try await createScratchpadNote(
                frontMatter: NoteFrontMatter(folderID: notesFolderFilter.newItemFolderID))
            scratchpadCreatedHere.insert(note.id)
            notesFocusRequest &+= 1
        } catch {
            saveError = "Could not create note: \(error.localizedDescription)"
        }
    }

    /// Edit on a card: the note in a tab of the window.
    func openNoteInWindow(_ id: NoteID) async {
        scratchpadWindow?.show()
        do {
            try await openNoteTab(id)
            notesFocusRequest &+= 1
        } catch {
            saveError = "Could not save the current note: \(error.localizedDescription)"
        }
    }

    func closeScratchpadWindow(returnToPreviousApp: Bool) {
        scratchpadWindow?.close(returnToPreviousApp: returnToPreviousApp)
    }

    /// After the window closed: save everything and drop empty new notes.
    func scratchpadWindowClosed() async {
        if !(await notesController.flushAll()) {
            saveError = "Could not save notes when closing the Scratchpad window."
        }
        for id in scratchpadTabs.ids { await discardIfEmpty(id) }
    }

    /// A note made in the window that is still "Untitled" with an empty body
    /// goes to the Trash. Notes made anywhere else are never touched.
    func discardIfEmpty(_ id: NoteID) async {
        guard scratchpadCreatedHere.contains(id),
              let note = notesController.note(id: id) ?? notesController.notes.first(where: { $0.id == id }),
              note.title == "Untitled",
              note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        scratchpadCreatedHere.remove(id)
        try? await deleteNote(id)
    }

    func setNotePinned(_ id: NoteID, pinned: Bool) async {
        do {
            try await notesController.setPinned(id: id, pinned: pinned)
        } catch {
            saveError = "Could not update note: \(error.localizedDescription)"
        }
    }

    private func showActiveTab() async {
        if let active = scratchpadTabs.active {
            if notesController.selectedNoteID != active { try? await notesController.select(id: active) }
        } else if notesController.selectedNoteID != nil {
            await notesController.clearSelection()
        }
    }

    @discardableResult
    func createScratchpadNote(title: String = "Untitled", body: String = "", frontMatter: NoteFrontMatter) async throws -> NoteDocument {
        let note = try await notesController.create(title: title, body: body, frontMatter: frontMatter)
        scratchpadTabs.open(note.id)
        persistScratchpadTabs()
        return note
    }

    func deleteNote(_ id: NoteID) async throws {
        try await notesController.delete(id: id, confirmed: true)
        pruneSelectedNote()
        scratchpadTabs.close(id)
        persistScratchpadTabs()
        await showActiveTab()
    }

    var scratchpadView: NoteViewMode {
        get { settings.scratchpad.view }
        set { settings.scratchpad.view = newValue }
    }

    // MARK: Notices

    func showNotice(_ text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    // MARK: Send to Scratchpad

    func sendToScratchpad(_ kind: ScratchpadSendKind, meeting: MeetingManifest) async {
        guard let text = kind.text(of: meeting) else { return }
        do {
            let note = try await createScratchpadNote(
                title: kind.noteTitle(meetingTitle: meeting.title), body: text,
                frontMatter: NoteFrontMatter(folderID: meeting.folderID, tags: meeting.tags))
            showNotice("Sent to Scratchpad as “\(note.title)”")
        } catch {
            saveError = "Could not send to Scratchpad: \(error.localizedDescription)"
        }
    }

    // MARK: Notes model

    var transformPlan: ModelPlan {
        ModelResolver.transformPlan(
            settings: settings.models, cliPaths: cliInfo.mapValues(\.path),
            appleIntelligenceAvailable: appleIntelligenceAvailable)
    }

    /// Calls the Notes model with the long time limit. `build` gets the model
    /// id and the thinking switch.
    func askNotesModel(_ build: (_ modelID: String, _ disableThinking: Bool) -> CleanupRequest) async throws -> ScratchpadAnswer {
        let plan = transformPlan
        guard let model = ProviderFactory.textModel(plan, credentials: credentials) else { throw ScratchpadAIError.noModel }
        let (modelID, disableThinking, timeout): (String, Bool, TimeInterval) = switch plan {
        case .connection(_, _, let id, let off, let timeout): (id, off, timeout)
        case .appleIntelligence(let timeout): ("apple-intelligence", false, timeout)
        default: ("", false, 120)
        }
        let request = build(modelID, disableThinking)
        let started = Date()
        let output = try await withTimeout(seconds: timeout) {
            try await abandoningOnCancel { try await model.clean(request) }
        }
        return ScratchpadAnswer(
            output: output, modelName: plan.shortName ?? "Notes model",
            seconds: max(1, Int(Date().timeIntervalSince(started).rounded())))
    }
}

extension AppModel {
    var canAskAcross: Bool {
        switch transformPlan {
        case .none, .unavailable: false
        default: true
        }
    }

    func askAcross(question: String, history: [NoteChatTurn], scope: AskScope,
                   progress: @escaping @Sendable (AskStep) -> Void) async throws -> AskOutcome {
        guard let pipeline = makeAskPipeline() else { return .failed(.model) }
        let corpus = await searchIndexer.corpus(scope: scope)
        try Task.checkCancellation()
        return try await runAsk(pipeline, question: question, history: history, corpus: corpus, progress: progress)
    }

    /// Ask's pipeline with the Notes model, or nil when none is set. Agents' `ask` uses the same one.
    func makeAskPipeline() -> AskPipeline? {
        let plan = transformPlan
        guard canAskAcross, let model = ProviderFactory.textModel(plan, credentials: credentials) else { return nil }
        let modelID: String
        let disableThinking: Bool
        switch plan {
        case .connection(_, _, let id, let off, _): modelID = id; disableThinking = off
        case .appleIntelligence: modelID = "apple-intelligence"; disableThinking = false
        default: modelID = ""; disableThinking = false
        }
        return AskPipeline(
            model: model, modelID: modelID, disableThinking: disableThinking,
            embedder: ProviderFactory.embedder(settings: settings.models, credentials: credentials),
            contextTokens: settings.models.search.askContextTokens, now: { Date() },
            trace: { t in
                askLog.notice("""
                    ask terms=\(t.terms, privacy: .public) dates=\(t.hasDateRange, privacy: .public) \
                    fromDaysAgo=\(t.fromDaysAgo.map(String.init) ?? "-", privacy: .public) \
                    toDaysAgo=\(t.toDaysAgo.map(String.init) ?? "-", privacy: .public) \
                    inRange=\(t.inRange, privacy: .public) wordHits=\(t.wordHits, privacy: .public) \
                    meaningHits=\(t.meaningHits.map(String.init) ?? "off", privacy: .public) \
                    read=\(t.read, privacy: .public) cited=\(t.citedLines.map(String.init) ?? "-", privacy: .public) \
                    kept=\(t.keptCitations.map(String.init) ?? "-", privacy: .public)
                    """)
            })
    }

    /// Runs Ask over `corpus` and logs counts only.
    func runAsk(_ pipeline: AskPipeline, question: String, history: [NoteChatTurn], corpus: AskCorpus,
                progress: @escaping @Sendable (AskStep) -> Void) async throws -> AskOutcome {
        let started = Date()
        let outcome = try await pipeline.run(question: question, history: history, corpus: corpus, progress: progress)
        let kind: String = switch outcome {
        case .answered: "answered"
        case .nothingFound: "nothingFound"
        case .failed(let failure): "failed.\(failure)"
        }
        askLog.notice("""
            ask outcome=\(kind, privacy: .public) passages=\(corpus.passages.count, privacy: .public) \
            vectors=\(corpus.vectors.count, privacy: .public) seconds=\(Int(Date().timeIntervalSince(started)), privacy: .public)
            """)
        return outcome
    }

    func askScopeTitle(_ scope: AskScope) -> String {
        switch scope {
        case .note: "This note"
        case .folder(let id): id.flatMap { folder in library.folders.first { $0.id == folder }?.name }.map { "This folder (\($0))" } ?? "Unfiled notes and meetings"
        case .meeting(let id): meetingManifests.first { $0.id == id }?.title ?? "A meeting…"
        case .all: "All notes and meetings"
        }
    }

    func newNoteFromAsk(question: String, result: AskResult) async {
        do {
            _ = try await createScratchpadNote(title: question,
                body: AskMarkdown.render(question: question, result: result, calendar: .current), frontMatter: NoteFrontMatter())
            notesFocusRequest &+= 1
        } catch { saveError = "Could not create note: \(error.localizedDescription)" }
    }
}

extension AppModel {
    /// The existing speaker-update path also owns translation changes, including open sessions.
    func translateCitation(meetingID: MeetingID, lineIDs: Set<String>) async -> [String: String]? {
        do {
            let snapshot = try await MeetingStore(root: paths.meetings).load(id: meetingID)
            let lines = snapshot.segments.filter { lineIDs.contains($0.id) && $0.translation == nil }
            if lines.isEmpty {
                return Dictionary(snapshot.segments.filter { lineIDs.contains($0.id) }.compactMap { line in
                    line.translation.map { (line.id, $0) }
                }, uniquingKeysWith: { first, _ in first })
            }
            var translations: [String: String] = [:]
            var pending: [MeetingSegment] = []
            for line in lines {
                let recognizer = NLLanguageRecognizer()
                recognizer.processString(line.text)
                if recognizer.dominantLanguage == .english { translations[line.id] = "" }
                else { pending.append(line) }
            }
            if !pending.isEmpty {
                let request = MeetingTranslation.request(lines: pending,
                    budget: MeetingTextBudget(contextTokens: settings.models.search.askContextTokens))
                let answer = try await askNotesModel { _, _ in request }
                try Task.checkCancellation()
                let parsed = MeetingTranslation.parse(answer.output, lines: pending)
                guard pending.allSatisfy({ parsed[$0.id] != nil }) else { return nil }
                translations.merge(parsed) { _, new in new }
            }
            try Task.checkCancellation()
            let english = translations
            let original = Dictionary(lines.map { ($0.id, $0.text) }, uniquingKeysWith: { first, _ in first })
            let change = try await updateMeetingSpeakers(id: meetingID) { current in
                var updated = current
                for index in updated.segments.indices {
                    let line = updated.segments[index]
                    if line.translation == nil, original[line.id] == line.text, let text = english[line.id] {
                        updated.segments[index].translation = text
                    }
                }
                return updated
            }
            await reloadMeetings()
            return Dictionary(change.after.segments.filter { lineIDs.contains($0.id) }.compactMap { line in
                line.translation.map { (line.id, $0) }
            }, uniquingKeysWith: { first, _ in first })
        } catch {
            if !Task.isCancelled { await reloadMeetings() }
            return nil
        }
    }

    func openAskMeeting(id: MeetingID, citation: AskCitation) {
        guard meetingManifests.contains(where: { $0.id == id }),
              FileManager.default.fileExists(atPath: paths.meetings.appendingPathComponent(id.rawValue).appendingPathComponent("meeting.json").path) else { return }
        openMeeting(MeetingJump(id: id, start: citation.start ?? 0, lineIDs: Set(citation.lines.map(\.id))))
    }
}
