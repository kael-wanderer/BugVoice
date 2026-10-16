import AppKit
import BugVoiceMac
import Foundation
import VoiceCore

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
    func syncScratchpadTabs() {
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
