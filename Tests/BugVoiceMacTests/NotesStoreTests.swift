import Foundation
import Testing
@testable import BugVoiceMac
import VoiceCore

struct NotesStoreTests {
    @Test func createsListsOpensAndDurablySavesCanonicalMarkdown() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotesStore(directory: root)

        let created = try await store.create(title: "First note", body: "Initial body")
        #expect(created.id.rawValue == "first-note")
        #expect(try String(contentsOf: root.appendingPathComponent("first-note.md"), encoding: .utf8) == "# First note\n\nInitial body")
        #expect(try await store.list().map(\.id) == [created.id])

        var edited = created
        edited.body = "Typed edit"
        edited.revision += 1
        let outcome = try await store.save(edited, expectedVersion: created.fileVersion, isDirty: true)
        guard case let .saved(saved, version) = outcome else {
            Issue.record("Expected a durable save")
            return
        }
        #expect(saved.body == "Typed edit")
        #expect(version == saved.fileVersion)
        let reopened = try await store.open(id: created.id)
        #expect(reopened.id == saved.id)
        #expect(reopened.title == saved.title)
        #expect(reopened.body == saved.body)
        #expect(reopened.revision == saved.revision)
        #expect(reopened.fileVersion == saved.fileVersion)
    }

    @Test func openUsesFilenameTitleForNonHeadingAndDoesNotRewriteFile() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = Data("plain body\nsecond line".utf8)
        try source.write(to: root.appendingPathComponent("external-note.md"))
        let store = NotesStore(directory: root)

        let note = try await store.open(id: NoteID(rawValue: "external-note"))
        #expect(note.title == "external note")
        #expect(note.body == "plain body\nsecond line")
        #expect(note.needsNormalization)
        #expect(try Data(contentsOf: root.appendingPathComponent("external-note.md")) == source)
    }

    @Test func actorAllocatesCollisionSafeNamesAndRenameKeepsContentAndIdentity() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotesStore(directory: root)
        let first = try await store.create(title: "Plan")
        let second = try await store.create(title: "PLAN")
        #expect(first.id.rawValue == "plan")
        #expect(second.id.rawValue == "plan-2")

        let renamed = try await store.rename(id: first.id, title: "Next Plan", revision: first.revision + 1, expectedVersion: first.fileVersion)
        #expect(renamed.id == first.id)
        #expect(renamed.title == "Next Plan")
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("next-plan.md").path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("plan.md").path))
    }

    @Test func delayedBodySaveCannotOverwriteCommittedTitleRename() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotesStore(directory: root)
        let original = try await store.create(title: "Before", body: "body")
        let renamed = try await store.rename(id: original.id, title: "After", revision: original.revision + 2, expectedVersion: original.fileVersion)
        var delayed = original
        delayed.body = "late body write"
        delayed.revision += 1

        guard case .stale = try await store.save(
            delayed,
            expectedVersion: original.fileVersion,
            isDirty: true
        ) else {
            Issue.record("Expected body save queued before rename to be stale")
            return
        }
        #expect(try await store.open(id: original.id).title == "After")
        #expect(renamed.revision > original.revision)
    }

    @Test func cleanExternalChangeReloadsAndDirtyExternalChangeConflicts() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotesStore(directory: root)
        let note = try await store.create(title: "Outside")
        let url = root.appendingPathComponent("outside.md")
        try Data("# Outside\n\nExternal edit".utf8).write(to: url)

        let clean = try await store.checkExternalChange(id: note.id, knownVersion: note.fileVersion, isDirty: false)
        guard case let .reloaded(reloaded, _) = clean else {
            Issue.record("Expected clean external changes to reload")
            return
        }
        #expect(reloaded.body == "External edit")

        try Data("# Outside\n\nSecond external edit".utf8).write(to: url)
        let dirty = try await store.checkExternalChange(id: note.id, knownVersion: note.fileVersion, isDirty: true)
        guard case .conflict = dirty else {
            Issue.record("Expected dirty external changes to conflict")
            return
        }
    }

    @Test func explicitKeepMineOverwritesChangedFileAndReturnsNewVersion() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotesStore(directory: root)
        let note = try await store.create(title: "Mine")
        let url = root.appendingPathComponent("mine.md")
        try Data("# Mine\n\nExternal".utf8).write(to: url)
        let conflict = try await store.checkExternalChange(id: note.id, knownVersion: note.fileVersion, isDirty: true)
        guard case let .conflict(externalVersion) = conflict else {
            Issue.record("Expected external conflict version")
            return
        }
        var local = note
        local.body = "Local confirmed"
        local.revision += 1

        let outcome = try await store.save(
            local,
            expectedVersion: note.fileVersion,
            isDirty: true,
            keepMine: true,
            confirmedExternalVersion: externalVersion
        )
        guard case let .saved(saved, version) = outcome else {
            Issue.record("Expected confirmed Keep mine to save")
            return
        }
        #expect(saved.body == "Local confirmed")
        #expect(version != note.fileVersion)
        #expect(try String(contentsOf: url, encoding: .utf8) == "# Mine\n\nLocal confirmed")
    }

    @Test func explicitKeepMineCanRecreateExternallyDeletedNote() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotesStore(directory: root)
        let note = try await store.create(title: "Missing", body: "local body")
        try FileManager.default.removeItem(at: root.appendingPathComponent("missing.md"))

        let conflict = try await store.checkExternalChange(id: note.id, knownVersion: note.fileVersion, isDirty: true)
        #expect(conflict == .missingConflict)
        var local = note
        local.revision += 1
        local.body = "kept local body"
        let outcome = try await store.save(
            local,
            expectedVersion: note.fileVersion,
            isDirty: true,
            keepMine: true,
            confirmedExternalVersion: nil
        )
        guard case .saved = outcome else {
            Issue.record("Expected confirmed Keep mine to recreate the note")
            return
        }
        #expect(try await store.open(id: note.id).body == "kept local body")
    }

    @Test func olderRevisionCannotReplaceNewerSavedRevision() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotesStore(directory: root)
        let original = try await store.create(title: "Revision")
        var newer = original
        newer.body = "newest"
        newer.revision = 2
        guard case let .saved(_, latestVersion) = try await store.save(
            newer,
            expectedVersion: original.fileVersion,
            isDirty: true
        ) else {
            Issue.record("Expected newest revision to save")
            return
        }

        var delayedOld = original
        delayedOld.body = "old"
        delayedOld.revision = 1
        let oldOutcome = try await store.save(
            delayedOld,
            expectedVersion: latestVersion,
            isDirty: true
        )
        guard case .stale = oldOutcome else {
            Issue.record("Expected old revision to be rejected")
            return
        }
        #expect(try await store.open(id: original.id).body == "newest")
    }

    @Test func overlappingSavesWithSharedBaselineAcceptOwnWriteAndKeepNewestRevision() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotesStore(directory: root)
        let original = try await store.create(title: "Overlap", body: "start")
        var first = original
        first.body = "first"
        first.revision += 1
        var second = original
        second.body = "second"
        second.revision += 2

        async let firstSave = store.save(first, expectedVersion: original.fileVersion, isDirty: true)
        async let secondSave = store.save(second, expectedVersion: original.fileVersion, isDirty: true)
        let outcomes = try await [firstSave, secondSave]
        #expect(!outcomes.contains { if case .conflict = $0 { true } else { false } })
        #expect(!outcomes.contains { if case .reloaded = $0 { true } else { false } })
        #expect(try await store.open(id: original.id).body == "second")
    }

    @Test func refreshAfterOwnSaveWithStaleBaselineIsUnchanged() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotesStore(directory: root)
        let original = try await store.create(title: "Refresh", body: "start")
        var edited = original
        edited.body = "saved by BugVoice"
        edited.revision += 1
        guard case .saved = try await store.save(
            edited,
            expectedVersion: original.fileVersion,
            isDirty: true
        ) else {
            Issue.record("Expected note save")
            return
        }

        let refresh = try await store.checkExternalChange(
            id: original.id,
            knownVersion: original.fileVersion,
            isDirty: false
        )
        guard case .unchanged = refresh else {
            Issue.record("A Store-owned write must not look external to a stale refresh")
            return
        }
    }

    @Test func renameAfterOwnSaveWithStaleBaselineIsAccepted() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotesStore(directory: root)
        let original = try await store.create(title: "Before save", body: "start")
        var edited = original
        edited.body = "saved body"
        edited.revision += 1
        guard case .saved = try await store.save(
            edited,
            expectedVersion: original.fileVersion,
            isDirty: true
        ) else {
            Issue.record("Expected note save")
            return
        }

        let renamed = try await store.rename(
            id: original.id,
            title: "After save",
            revision: edited.revision + 1,
            expectedVersion: original.fileVersion
        )
        #expect(renamed.title == "After save")
        #expect(renamed.body == "saved body")
    }

    @Test func deletionRequiresConfirmationAndMovesNoteOutOfNotesDirectory() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotesStore(directory: root)
        let note = try await store.create(title: "Delete me")
        try await store.delete(id: note.id, confirmed: false)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("delete-me.md").path))

        try await store.delete(id: note.id, confirmed: true)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("delete-me.md").path))
        #expect(try await store.list().isEmpty)
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BugVoiceNotesStore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
