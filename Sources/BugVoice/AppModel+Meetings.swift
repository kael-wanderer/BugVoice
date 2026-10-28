import AppKit
import BugVoiceMac
import Foundation
import SwiftUI
import VoiceCore
import WhisperEngine

private enum MeetingGenerationError: LocalizedError {
    case noTextModel
    var errorDescription: String? { "Choose a model for Meeting notes in Settings → Models." }
}

extension AppModel {
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

    func editMeetingSegment(meeting id: MeetingID, segment: String, text: String?) async {
        do {
            let date = Date()
            let change: @Sendable (MeetingManifest) throws -> MeetingManifest = { current in
                var updated = current
                if let text { try updated.editSegment(id: segment, text: text, at: date) }
                else { try updated.revertSegment(id: segment) }
                return updated
            }
            if let meetings, try await meetings.updateSpeakersInSession(id: id, change: change) {
                // The live session owns the manifest.
            } else if let uploads, try await uploads.updateSpeakersInSession(id: id, change: change) {
                // The upload session owns the manifest.
            } else {
                try await meetingStore.editSegment(meeting: id, segment: segment, text: text, at: date)
            }
            await reloadMeetings()
            searchIndexer.schedule(.meeting(id))
            if meetingManifests.first(where: { $0.id == id })?.showEnglish == true {
                _ = await translateCitation(meetingID: id, lineIDs: [segment])
            }
        } catch { saveError = "Could not edit transcript: \(error.localizedDescription)" }
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
        let generatedAt = Date()
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
        if let uploads, try await uploads.saveGeneratedTextToSession(id: id, text: text, kind: kind, names: names, generatedAt: generatedAt) {
            await reloadMeetings()
            if kind == .summary {
                let suggestionModel = textModel
                Task { await suggestTags(for: id, summary: text, model: suggestionModel) }
            }
            return text
        }
        if let meetings, try await meetings.saveGeneratedTextToSession(id: id, text: text, kind: kind, names: names, generatedAt: generatedAt) {
            await reloadMeetings()
            if kind == .summary {
                let suggestionModel = textModel
                Task { await suggestTags(for: id, summary: text, model: suggestionModel) }
            }
            return text
        }
        try Task.checkCancellation()
        try await meetingStore.saveGeneratedText(meeting: id, text: text, kind: kind, names: names, generatedAt: generatedAt)
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
    func applyRetention() async {
        if settings.historyRetention == .off { clearFailedDictations() }
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

    func recoverUnfinishedMeetings() async {
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

    func applyMeetingRetention() async {
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
}
