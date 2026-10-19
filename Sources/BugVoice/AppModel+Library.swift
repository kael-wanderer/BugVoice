import AppKit
import BugVoiceMac
import Foundation
import SwiftUI
import VoiceCore
import WhisperEngine

extension AppModel {
    // MARK: Folders and tags

    func loadLibrary() async {
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
        // Tags made with New tag in the Manage library sheet, not on any item yet.
        for tag in library.tags where totals[tag.name] == nil { totals[tag.name] = 0 }
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
}
