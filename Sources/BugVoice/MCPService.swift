import BugVoiceMac
import Foundation
import MCPKit
import Observation
import VoiceCore

/// The app's side of the MCP server: listens on the local socket and runs each
/// agent tool call through the same code paths as the app's own buttons.
/// Logs and the activity list carry tool, client, time and the error sentence only.
@MainActor
@Observable
final class MCPService {
    static let offMessage = "MCP is off. Turn it on in BugVoice Settings › Agents."
    static let noNotesModel = "Choose a Notes model in BugVoice Settings › Models."
    static let summaryBusy = "BugVoice is already writing this meeting's summary. Try again in a minute."
    static let summaryFailed = "Could not write the summary. Try again."
    static let summaryTooSlow = "Writing the summary took longer than 5 minutes. Try again."
    static let otherInstance = "another BugVoice is answering agents."
    static let editsOff = "Creating and editing notes is turned off in BugVoice Settings › Agents."
    static let uploadsOff = "Uploading is turned off in BugVoice Settings › Agents."

    private(set) var activity = MCPActivity()
    /// "Listening", "Not started" or "Could not start: <reason>".
    private(set) var status = "Not started"

    private unowned let model: AppModel
    @ObservationIgnored private var server: MCPSocketServer?
    /// `ask` and `summarize_meeting` run one at a time across all agents.
    @ObservationIgnored private let modelGate = SerialGate()

    init(model: AppModel) {
        self.model = model
    }

    /// Listens whether MCP is on or off, so a bridge can tell "off" from "not running".
    func start() {
        guard server == nil else { return }
        let server = MCPSocketServer(paths: .standard()) { [weak self] request in
            guard let self else { return MCPWireResponse(id: request.id, text: "BugVoice is quitting.", isError: true) }
            return await self.handle(request)
        }
        do {
            try server.start()
            self.server = server
            status = "Listening"
        } catch {
            status = "Could not start: \(Self.reason(error))"
            Log.mcp.error("mcp start failed: \(Self.reason(error), privacy: .public)")
        }
    }

    func stop() {
        server?.stop()
        server = nil
    }

    private static func reason(_ error: Error) -> String {
        if case MCPSocketError.pathTooLong = error { return "the socket path is too long." }
        if case MCPSocketError.inUse = error { return otherInstance }
        return error.localizedDescription
    }

    // MARK: Calls

    func handle(_ r: MCPWireRequest) async -> MCPWireResponse {
        let started = Date()
        let result: Result<String, MCPFailure>
        if !model.settings.agents.mcpEnabled {
            result = .failure(MCPFailure(Self.offMessage))
        } else {
            // The socket is a trust boundary too: check again what the bridge checked.
            switch MCPTools.check(r.tool, r.arguments) {
            case .failure(let error): result = .failure(MCPFailure(error.message))
            case .success(let call): result = await run(call, client: r.client).map { MCPFormat.fitted($0, for: call) }
            }
        }
        let error: String? = if case .failure(let failure) = result { failure.message } else { nil }
        activity.record(MCPActivityEntry(time: started, client: r.client, tool: r.tool, error: error))
        Log.mcp.notice("""
            mcp tool=\(r.tool, privacy: .public) client=\(r.client, privacy: .public) \
            seconds=\(Int(Date().timeIntervalSince(started)), privacy: .public) ok=\(error == nil, privacy: .public)
            """)
        switch result {
        case .success(let text): return MCPWireResponse(id: r.id, text: text, isError: false)
        case .failure(let failure): return MCPWireResponse(id: r.id, text: failure.message, isError: true)
        }
    }

    private func run(_ call: MCPCall, client: String) async -> Result<String, MCPFailure> {
        switch call {
        case .listFolders:
            return .success(listFolders())
        case .listNotes(let folder, let tag, let text, let limit):
            return listNotes(folder: folder, tag: tag, text: text, limit: limit)
        case .getNote(let id):
            return await getNote(NoteID(rawValue: id))
        case .listActionItems(let status, let meeting, let limit):
            let done = await ActionItemStore(url: model.paths.actionItems).load()
            let board = ActionItemBoard(meetings: model.meetingManifests.filter { meeting == nil || $0.id.rawValue == meeting },
                                        done: done, status: status, owner: .anyone, range: .all, query: "", now: Date())
            let rows = board.groups.flatMap { group in
                group.rows.map { MCPFormat.actionItem($0, meetingTitle: group.title, meetingDate: group.date) }
            }
            return .success(MCPFormat.jsonRows(Array(rows.prefix(limit))))
        case .listMeetings(let folder, let tag, let from, let to, let text, let limit):
            return listMeetings(folder: folder, tag: tag, from: from, to: to, text: text, limit: limit)
        case .getMeeting(let id, let parts, let fromLine):
            return await getMeeting(MeetingID(rawValue: id), parts: parts, fromLine: fromLine)
        case .search(let query, let scope, let limit):
            return await search(query: query, scope: scope, limit: limit)
        case .ask(let question, let scope):
            await modelGate.enter()
            // MCP may have been turned off while this call waited its turn.
            guard model.settings.agents.mcpEnabled else {
                await modelGate.leave()
                return .failure(MCPFailure(Self.offMessage))
            }
            let result = await ask(question: question, scope: scope)
            await modelGate.leave()
            return result
        case .summarizeMeeting(let id, let kind, let replace):
            await modelGate.enter()
            guard model.settings.agents.mcpEnabled else {
                await modelGate.leave()
                return .failure(MCPFailure(Self.offMessage))
            }
            let result = await summarize(MeetingID(rawValue: id), kind: kind, replace: replace)
            await modelGate.leave()
            return result
        case .createNote(let title, let body, let folder, let tags):
            guard model.settings.agents.allowNoteEdits else { return .failure(MCPFailure(Self.editsOff)) }
            return await createNote(title: title, body: body, folder: folder, tags: tags)
        case .editNote(let id, let body, let mode, let title, let folder, let tags):
            guard model.settings.agents.allowNoteEdits else { return .failure(MCPFailure(Self.editsOff)) }
            return await editNote(NoteID(rawValue: id), body: body, mode: mode, title: title, folder: folder, tags: tags)
        case .uploadAudio(let path, let title, let folder, let tags):
            guard model.settings.agents.allowUploads else { return .failure(MCPFailure(Self.uploadsOff)) }
            return await upload(path: path, title: title, folder: folder, tags: tags, client: client)
        case .getJob(let jobID):
            return getJob(jobID)
        }
    }

    // MARK: Folders

    private var folders: [LibraryFolder] { model.library.folders }

    private func folderName(_ id: FolderID?) -> String? {
        id.flatMap { id in folders.first { $0.id == id }?.name }
    }

    private func listFolders() -> String {
        let notes = model.notesController.notes
        let meetings = model.meetingManifests
        let rows: [JSONValue] = LibraryFolders.sorted(folders).map { folder in
            .object([
                "id": .string(folder.id.rawValue),
                "name": .string(folder.name),
                "notes": .number(Double(notes.filter { $0.frontMatter.folderID == folder.id }.count)),
                "meetings": .number(Double(meetings.filter { $0.folderID == folder.id }.count)),
            ])
        }
        return MCPFormat.json(.array(rows))
    }

    /// A folder argument: nil when absent, otherwise resolved or an error.
    private func folderID(_ folder: String?) -> Result<FolderID?, MCPFailure> {
        guard let folder else { return .success(nil) }
        return MCPResolve.folder(folder, in: folders).map { $0 }
    }

    /// Normalized as the tag field does; invalid and extra tags are dropped.
    private static func labels(folderID: FolderID?, tags: [String]) -> ItemLabels {
        var labels = ItemLabels(folderID: folderID)
        for tag in tags { labels.addTag(tag) }
        return labels
    }

    private static func matchesTag(_ tags: [String], _ tag: String?) -> Bool {
        guard let tag else { return true }
        guard let wanted = TagName.normalize(tag) else { return false }
        return tags.contains(wanted)
    }

    private static func matchesText(_ title: String, _ text: String?) -> Bool {
        guard let text, !text.isEmpty else { return true }
        return AskText.fold(title).contains(AskText.fold(text))
    }

    // MARK: Notes

    private func listNotes(folder: String?, tag: String?, text: String?, limit: Int) -> Result<String, MCPFailure> {
        var folderID: FolderID?
        if let folder {
            switch MCPResolve.folder(folder, in: folders) {
            case .success(let id): folderID = id
            case .failure(let failure): return .failure(failure)
            }
        }
        let rows: [JSONValue] = model.notesController.notes
            .filter { folderID == nil || $0.frontMatter.folderID == folderID }
            .filter { Self.matchesTag($0.frontMatter.tags, tag) && Self.matchesText($0.title, text) }
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(limit)
            .map { note in
                .object([
                    "id": .string(note.id.rawValue),
                    "title": .string(note.title),
                    "folder": folderName(note.frontMatter.folderID).map(JSONValue.string) ?? .null,
                    "tags": .array(note.frontMatter.tags.map(JSONValue.string)),
                    "modified": .string(MCPFormat.iso(note.modifiedAt)),
                    "words": .number(Double(note.body.split(whereSeparator: \.isWhitespace).count)),
                ])
            }
        return .success(MCPFormat.json(.array(rows)))
    }

    private func getNote(_ id: NoteID) async -> Result<String, MCPFailure> {
        let controller = model.notesController
        if controller.hasUnsavedChanges(id: id), let open = controller.note(id: id) {
            return .success(MCPFormat.note(
                title: open.title, folder: folderName(open.frontMatter.folderID), tags: open.frontMatter.tags,
                modified: open.modifiedAt, body: open.body, unsaved: true))
        }
        let disk = try? await model.notesStore.open(id: id)
        guard let note = disk ?? controller.notes.first(where: { $0.id == id }) else {
            return .failure(MCPFailure("No note with id \(id.rawValue)."))
        }
        return .success(MCPFormat.note(
            title: note.title, folder: folderName(note.frontMatter.folderID), tags: note.frontMatter.tags,
            modified: note.modifiedAt, body: note.body, unsaved: false))
    }

    private func createNote(title: String, body: String, folder: String?, tags: [String]) async -> Result<String, MCPFailure> {
        let folderID: FolderID?
        switch self.folderID(folder) {
        case .success(let id): folderID = id
        case .failure(let failure): return .failure(failure)
        }
        let labels = Self.labels(folderID: folderID, tags: tags)
        do {
            let note = try await model.notesController.createForAgent(
                title: title, body: body, frontMatter: NoteFrontMatter(folderID: labels.folderID, tags: labels.tags))
            return .success(MCPFormat.json(.object(["id": .string(note.id.rawValue), "title": .string(note.title)])))
        } catch {
            return .failure(MCPFailure("Could not create the note: \(error.localizedDescription)"))
        }
    }

    private func editNote(
        _ id: NoteID, body: String, mode: MCPEditMode, title: String?, folder: String?, tags: [String]?
    ) async -> Result<String, MCPFailure> {
        let controller = model.notesController
        guard let current = controller.note(id: id) ?? controller.notes.first(where: { $0.id == id }) else {
            return .failure(MCPFailure("No note with id \(id.rawValue)."))
        }
        var labels: (folderID: FolderID?, tags: [String])?
        if folder != nil || tags != nil {
            var folderID = current.frontMatter.folderID
            if folder != nil {
                switch self.folderID(folder) {
                case .success(let id): folderID = id
                case .failure(let failure): return .failure(failure)
                }
            }
            let resolved = Self.labels(folderID: folderID, tags: tags ?? current.frontMatter.tags)
            labels = (folderID: resolved.folderID, tags: resolved.tags)
        }
        do {
            let note = try await controller.agentEdit(id: id, body: body, append: mode == .append, title: title, labels: labels)
            return .success(MCPFormat.json(.object([
                "id": .string(note.id.rawValue), "modified": .string(MCPFormat.iso(note.modifiedAt)),
            ])))
        } catch let refusal as AgentEditRefusal {
            return .failure(MCPFailure(refusal.message))
        } catch NotesStoreError.missing {
            return .failure(MCPFailure("No note with id \(id.rawValue)."))
        } catch {
            return .failure(MCPFailure("Could not save the note. Try again."))
        }
    }

    // MARK: Uploads

    private func upload(path: String, title: String?, folder: String?, tags: [String], client: String) async -> Result<String, MCPFailure> {
        let url = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue,
              FileManager.default.isReadableFile(atPath: url.path)
        else { return .failure(MCPFailure("File not found: \(path).")) }
        let ext = url.pathExtension.lowercased()
        guard MCPTools.uploadExtensions.contains(ext) else { return .failure(MCPFailure(MCPTools.unsupportedType(ext))) }
        let folderID: FolderID?
        switch self.folderID(folder) {
        case .success(let id): folderID = id
        case .failure(let failure): return .failure(failure)
        }
        guard let uploads = model.uploads else { return .failure(MCPFailure(UploadController.AgentUploadError.notReady.localizedDescription)) }
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let id = try await uploads.submitForAgent(
                url: url, title: trimmed?.isEmpty == false ? trimmed : nil,
                labels: Self.labels(folderID: folderID, tags: tags), client: client)
            return .success(MCPFormat.json(.object(["job_id": .string(id.uuidString)])))
        } catch {
            return .failure(MCPFailure(error.localizedDescription))
        }
    }

    private func getJob(_ jobID: String) -> Result<String, MCPFailure> {
        guard let id = UUID(uuidString: jobID), let job = model.uploads?.jobStatus(id: id) else {
            return .failure(MCPFailure("No upload job with id \(jobID)."))
        }
        let state: String = switch job.state {
        case .queued: "queued"
        case .reading: "reading"
        case .transcribing: "transcribing"
        case .ready: job.meetingID.map { model.speakerTasks[$0] != nil } == true ? "finding_speakers" : "ready"
        case .failed: "failed"
        case .cancelled: "cancelled"
        }
        var out: [String: JSONValue] = ["state": .string(state)]
        if let progress = job.progress, !job.state.isTerminal { out["progress"] = .number(progress) }
        if let meetingID = job.meetingID, job.state == .ready { out["meeting_id"] = .string(meetingID.rawValue) }
        if job.state == .failed { out["error"] = .string(job.errorMessage ?? UploadFailure.unreadable.localizedDescription) }
        return .success(MCPFormat.json(.object(out)))
    }

    // MARK: Meetings

    private func listMeetings(
        folder: String?, tag: String?, from: Date?, to: Date?, text: String?, limit: Int
    ) -> Result<String, MCPFailure> {
        var folderID: FolderID?
        if let folder {
            switch MCPResolve.folder(folder, in: folders) {
            case .success(let id): folderID = id
            case .failure(let failure): return .failure(failure)
            }
        }
        let rows: [JSONValue] = model.meetingManifests
            .filter { folderID == nil || $0.folderID == folderID }
            .filter { Self.matchesTag($0.tags, tag) && Self.matchesText($0.title, text) }
            .filter { m in (from.map { m.startedAt >= $0 } ?? true) && (to.map { m.startedAt <= $0 } ?? true) }
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(limit)
            .map { m in
                .object([
                    "id": .string(m.id.rawValue),
                    "title": .string(m.title),
                    "started": .string(MCPFormat.iso(m.startedAt)),
                    "duration_seconds": .number(m.duration.rounded()),
                    "kind": .string(m.source == .upload ? "uploaded" : "recorded"),
                    "people": .array(MCPFormat.people(m).map(JSONValue.string)),
                    "has_summary": .bool(!(m.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
                    "has_action_items": .bool(!(m.actionItems ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
                    "state": .string(m.state.rawValue),
                ])
            }
        return .success(MCPFormat.json(.array(rows)))
    }

    /// The saved manifest, so a summary written a moment ago is included.
    private func loadMeeting(_ id: MeetingID) async -> MeetingManifest? {
        guard model.meetingManifests.contains(where: { $0.id == id }) else { return nil }
        return try? await MeetingStore(root: model.paths.meetings).load(id: id)
    }

    private func getMeeting(_ id: MeetingID, parts: Set<MCPMeetingPart>, fromLine: Int) async -> Result<String, MCPFailure> {
        guard let meeting = await loadMeeting(id) else { return .failure(MCPFailure("No meeting with id \(id.rawValue).")) }
        return .success(MCPFormat.meeting(meeting, folder: folderName(meeting.folderID), parts: parts, fromLine: fromLine))
    }

    // MARK: Search and Ask

    private func askScope(_ argument: MCPScopeArgument) -> Result<AskScope, MCPFailure> {
        switch MCPResolve.scope(argument, folders: folders) {
        case .success(.meeting(let id)) where !model.meetingManifests.contains(where: { $0.id == id }):
            .failure(MCPFailure("No meeting with id \(id.rawValue)."))
        case .success(.note(let id)) where !model.notesController.notes.contains(where: { $0.id == id }):
            .failure(MCPFailure("No note with id \(id.rawValue)."))
        case let other:
            other
        }
    }

    private func search(query: String, scope: MCPScopeArgument, limit: Int) async -> Result<String, MCPFailure> {
        let resolved: AskScope
        switch askScope(scope) {
        case .success(let s): resolved = s
        case .failure(let failure): return .failure(failure)
        }
        // Search calls no model; the pipeline only needs the embedder.
        let pipeline = AskPipeline(
            model: NoTextModel(), modelID: "", disableThinking: true,
            embedder: ProviderFactory.embedder(settings: model.settings.models, credentials: model.credentials),
            contextTokens: model.settings.models.search.askContextTokens, now: { Date() })
        let corpus = await model.searchIndexer.corpus(scope: resolved)
        do {
            let result = try await pipeline.search(query: query, corpus: corpus, limit: limit)
            return .success(MCPFormat.json(MCPFormat.searchResult(result, info: corpus.info)))
        } catch {
            return .failure(MCPFailure("Search stopped. Try again."))
        }
    }

    private func ask(question: String, scope: MCPScopeArgument) async -> Result<String, MCPFailure> {
        let resolved: AskScope
        switch askScope(scope) {
        case .success(let s): resolved = s
        case .failure(let failure): return .failure(failure)
        }
        guard !resolved.questionIsTooLong(question) else {
            return .failure(MCPFailure("question must be at most \(AskScope.maxQuestionLength) characters."))
        }
        guard let pipeline = model.makeAskPipeline() else { return .failure(MCPFailure(Self.noNotesModel)) }
        let corpus = await model.searchIndexer.corpus(scope: resolved)
        do {
            let outcome = try await model.runAsk(pipeline, question: question, history: [], corpus: corpus, progress: { _ in })
            return MCPFormat.askResult(outcome, meetings: corpus.meetings, notes: corpus.notes, dictations: corpus.dictations)
                .map(MCPFormat.json)
        } catch {
            return .failure(MCPFailure("Ask stopped before it finished. Try again."))
        }
    }

    // MARK: Summary

    static let summaryTimeLimit: Double = 300

    private func summarize(_ id: MeetingID, kind: MCPTextKind, replace: Bool) async -> Result<String, MCPFailure> {
        guard let meeting = await loadMeeting(id) else { return .failure(MCPFailure("No meeting with id \(id.rawValue).")) }
        let existing = (kind == .summary ? meeting.summary : meeting.actionItems) ?? ""
        if !replace, !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .success(existing) }
        guard meeting.state == .ready, !meeting.segments.isEmpty else {
            return .failure(MCPFailure("This meeting has no transcript yet."))
        }
        // The app's own Summarize button may be writing this meeting's text now.
        if model.isWritingMeetingText(id: id) { return .failure(MCPFailure(Self.summaryBusy)) }
        let textKind: MeetingTextKind = kind == .summary ? .summary : .actionItems
        let model = model
        do {
            // abandoningOnCancel lets the time limit return, and free the model gate,
            // even when the model call does not stop at once.
            let text = try await withTimeout(seconds: Self.summaryTimeLimit) {
                try await abandoningOnCancel {
                    try await model.generateMeetingText(id: id, kind: textKind, progress: { _ in })
                }
            }
            return .success(text)
        } catch is TimeoutError {
            return .failure(MCPFailure(Self.summaryTooSlow))
        } catch is CancellationError {
            return .failure(MCPFailure(Self.summaryFailed))
        } catch {
            return .failure(MCPFailure(error.localizedDescription))
        }
    }
}

/// First come, first served: one holder at a time.
private actor SerialGate {
    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func enter() async {
        guard busy else {
            busy = true
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    func leave() {
        if waiting.isEmpty { busy = false } else { waiting.removeFirst().resume() }
    }
}

/// Stands in for the Notes model where Ask's pipeline only searches.
private struct NoTextModel: TextModel {
    func clean(_ request: CleanupRequest) async throws -> String {
        throw ProviderError.unavailable("No model is used for search.")
    }
}
