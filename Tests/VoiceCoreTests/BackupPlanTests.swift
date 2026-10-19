import Foundation
import Testing
@testable import VoiceCore

struct BackupPlanTests {
    private func fixture(_ body: (URL, (String, String) throws -> Void) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root, { path, text in
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        })
    }

    @Test func includesLibraryFilesAndLeavesOutTheRest() throws {
        try fixture { root, write in
            let allowed = ["settings.json", "dictionary.json", "history.jsonl", "insights.json", "library.json"]
            for path in allowed + ["credentials.json", "last.wav", "vocabulary.migrated.txt", "settings.json.corrupt-1", "models/m.bin", "SearchIndex/i", "MCP/agent-uploads.json", "Restore safety copy 2026-10-19/settings.json"] {
                try write(path, "x")
            }
            #expect(try BackupPlan.make(root: root).files == allowed.sorted())
            #expect(BackupPlan.rootFiles == allowed + ["voices.json"])
            #expect(BackupPlan.rootFolders == ["Meetings", "Notes"])
            try write("voices.json", "x")
            #expect(try BackupPlan.make(root: root).files == (allowed + ["voices.json"]).sorted())
        }
    }

    @Test func notesSkipHiddenFiles() throws {
        try fixture { root, write in
            for path in ["Notes/a.md", "Notes/.DS_Store", "Notes/.trash/x"] { try write(path, "x") }
            let plan = try BackupPlan.make(root: root)
            #expect(plan.files == ["Notes/a.md"])
        }
    }

    @Test func meetingsKeepReadyAndFailedOnly() throws {
        try fixture { root, write in
            for (id, state) in [("r", "ready"), ("f", "failed"), ("t", "transcribing"), ("c", "ready")] {
                try write("Meetings/\(id)/meeting.json", "{\"state\":\"\(state)\"}")
            }
            for path in ["Meetings/r/audio.m4a", "Meetings/r/mic.pcm", "Meetings/r/checkpoint.json", "Meetings/r/.hidden/tmp", "Meetings/c/.upload-cancelled", "Meetings/n/audio.m4a"] { try write(path, "x") }
            let plan = try BackupPlan.make(root: root)
            #expect(plan.files == ["Meetings/f/meeting.json", "Meetings/r/audio.m4a", "Meetings/r/meeting.json"])
            #expect(plan.skippedMeetings == ["c", "n", "t"])
            try write("Meetings/bad/meeting.json", "not json")
            #expect(try BackupPlan.make(root: root).skippedMeetings == ["bad", "c", "n", "t"])
        }
    }

    @Test func totalBytesSumsIncludedFiles() throws {
        try fixture { root, write in
            try write("settings.json", "abc")
            try write("Notes/a.md", "1234")
            try write("credentials.json", "ignored")
            #expect(try BackupPlan.make(root: root).totalBytes == 7)
        }
    }

    @Test func emptyRootGivesEmptyPlan() throws {
        try fixture { (root: URL, _: (String, String) throws -> Void) throws in
            let empty = BackupPlan(files: [], skippedMeetings: [], totalBytes: 0)
            #expect(try BackupPlan.make(root: root) == empty)
            #expect(try BackupPlan.make(root: root.appendingPathComponent("missing")) == empty)
        }
    }
}
