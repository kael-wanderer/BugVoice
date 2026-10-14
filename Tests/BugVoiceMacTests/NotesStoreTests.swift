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

        let renamed = try await store.rename(id: first.id, title: "Next Plan", expectedVersion: first.fileVersion)
        #expect(renamed.id == first.id)
        #expect(renamed.title == "Next Plan")
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("next-plan.md").path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("plan.md").path))
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
        var local = note
        local.body = "Local confirmed"
        local.revision += 1

        let outcome = try await store.save(local, expectedVersion: note.fileVersion, isDirty: true, keepMine: true)
        guard case let .saved(saved, version) = outcome else {
            Issue.record("Expected confirmed Keep mine to save")
            return
        }
        #expect(saved.body == "Local confirmed")
        #expect(version != note.fileVersion)
        #expect(try String(contentsOf: url, encoding: .utf8) == "# Mine\n\nLocal confirmed")
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
