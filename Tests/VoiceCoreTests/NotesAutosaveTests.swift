import Foundation
import Testing
@testable import VoiceCore

struct NotesAutosaveTests {
    @Test func bodySaveDeadlineIsExactlyFiveHundredMilliseconds() {
        let edit = date(0)
        #expect(NotesAutosavePolicy.deadline(afterBodyEditAt: edit) == date(0.5))
        #expect(!NotesAutosavePolicy.bodySaveIsDue(now: date(0.499), lastBodyEditAt: edit))
        #expect(NotesAutosavePolicy.bodySaveIsDue(now: date(0.5), lastBodyEditAt: edit))
    }

    @Test func laterBodyEditResetsDebounceDeadline() {
        let firstEdit = date(0)
        let laterEdit = date(0.3)
        #expect(NotesAutosavePolicy.deadline(afterBodyEditAt: laterEdit) == date(0.8))
        #expect(!NotesAutosavePolicy.bodySaveIsDue(now: date(0.5), lastBodyEditAt: laterEdit))
        #expect(NotesAutosavePolicy.bodySaveIsDue(now: date(0.8), lastBodyEditAt: laterEdit))
        #expect(NotesAutosavePolicy.deadline(afterBodyEditAt: laterEdit) != NotesAutosavePolicy.deadline(afterBodyEditAt: firstEdit))
    }

    @Test func bodyDebounceKeepsLastCommittedTitleUntilTitleEditingEnds() {
        #expect(NotesAutosavePolicy.titleForBodySave(committedTitle: "Old title", draftTitle: "New title", titleEditing: true) == "Old title")
        #expect(NotesAutosavePolicy.committedTitle(previous: "Old title", draft: "New title", reason: .bodyDebounce) == "Old title")
        #expect(NotesAutosavePolicy.committedTitle(previous: "Old title", draft: "New title", reason: .returnKey) == "New title")
        #expect(NotesAutosavePolicy.committedTitle(previous: "Old title", draft: "New title", reason: .focusOut) == "New title")
    }

    @Test func saveRevisionPolicyRejectsAnOlderQueuedSave() {
        #expect(NotesAutosavePolicy.mayWrite(requestedRevision: 8, storedRevision: 7))
        #expect(!NotesAutosavePolicy.mayWrite(requestedRevision: 6, storedRevision: 7))
        #expect(NotesAutosavePolicy.mayWrite(requestedRevision: 7, storedRevision: 7))
    }

    @Test func fnv1aFingerprintIsStableForKnownBytes() {
        let version = NoteFileVersion.fingerprint(data: Data("hello".utf8), modifiedAt: date(10))
        #expect(version.contentHash == 0xa430d84680aabd0b)
        #expect(version.byteCount == 5)
        #expect(version.modifiedAt == date(10))
        #expect(NoteFileVersion.fingerprint(data: Data(), modifiedAt: date(10)).contentHash == 0xcbf29ce484222325)
    }

    @Test func contentHashDetectsSameSizeEditWithSameModificationTime() {
        let timestamp = date(10)
        let first = NoteFileVersion.fingerprint(data: Data("note".utf8), modifiedAt: timestamp)
        let second = NoteFileVersion.fingerprint(data: Data("NOTE".utf8), modifiedAt: timestamp)
        #expect(first.byteCount == second.byteCount)
        #expect(first.modifiedAt == second.modifiedAt)
        #expect(first.contentHash != second.contentHash)
        #expect(NotesAutosavePolicy.fileVersionChanged(from: first, to: second))
    }

    @Test func fileVersionAlsoDetectsModificationTimeAndSizeChanges() {
        let baseline = NoteFileVersion.fingerprint(data: Data("note".utf8), modifiedAt: date(10))
        let changedDate = NoteFileVersion.fingerprint(data: Data("note".utf8), modifiedAt: date(11))
        let changedSize = NoteFileVersion.fingerprint(data: Data("longer".utf8), modifiedAt: date(10))
        #expect(NotesAutosavePolicy.fileVersionChanged(from: baseline, to: changedDate))
        #expect(NotesAutosavePolicy.fileVersionChanged(from: baseline, to: changedSize))
        #expect(!NotesAutosavePolicy.fileVersionChanged(from: baseline, to: baseline))
    }

    @Test func refreshChecksAreEventDrivenWithoutPolling() {
        #expect(NotesRefreshTrigger.allCases == [.selection, .appActivation, .beforeSave])
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }
}
