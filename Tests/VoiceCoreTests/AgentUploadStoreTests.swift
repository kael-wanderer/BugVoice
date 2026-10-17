import Foundation
import Testing
@testable import VoiceCore

struct AgentUploadStoreTests {
    let now = Date(timeIntervalSince1970: 2_000_000_000)

    func makeStore() -> (AgentUploadStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bv-agent-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("MCP", isDirectory: true)
        let url = dir.appendingPathComponent("agent-uploads.json")
        return (AgentUploadStore(url: url), url)
    }

    func mode(_ path: String) throws -> Int {
        try (FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    func entry(_ state: UploadJobState, path: String = "/tmp/a.m4a", updated: Date? = nil) -> AgentUploadEntry {
        AgentUploadEntry(
            id: UUID(), path: path, title: "Standup", folderID: FolderID(rawValue: "f1"), tags: ["work"],
            client: "claude-code", state: state, updatedAt: updated ?? now)
    }

    @Test func missingOrCorruptFileLoadsEmpty() throws {
        let (store, url) = makeStore()
        #expect(store.load().isEmpty)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        #expect(store.load().isEmpty)
    }

    @Test func saveRoundTripsOwnerOnly() throws {
        let (store, url) = makeStore()
        var failed = entry(.failed)
        failed.meetingID = MeetingID(rawValue: "m1")
        failed.error = "Could not read this file."
        let entries = [entry(.queued), failed]
        try store.save(entries)
        #expect(store.load() == entries)
        #expect(try mode(url.path) == 0o600)
        #expect(try mode(url.deletingLastPathComponent().path) == 0o700)
        let keys = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        #expect(keys[1]["state"] as? String == "failed")
        #expect(keys[1]["meetingID"] as? String == "m1")
        #expect(Set(keys[0].keys) == ["id", "path", "title", "folderID", "tags", "client", "state", "updatedAt"])
    }

    @Test func pruneDropsOnlyOldFinishedEntries() {
        let old = now.addingTimeInterval(-8 * 86_400)
        let recent = now.addingTimeInterval(-6 * 86_400)
        let oldReady = entry(.ready, updated: old)
        let oldQueued = entry(.queued, updated: old)
        let recentFailed = entry(.failed, updated: recent)
        let oldCancelled = entry(.cancelled, updated: old)
        #expect(AgentUploadStore.pruned([oldReady, oldQueued, recentFailed, oldCancelled], now: now) == [oldQueued, recentFailed])
    }

    @Test func recoveryRequeuesWaitingFilesAndFailsMissingOnes() {
        let waiting = entry(.queued, path: "/here.m4a")
        let interrupted = entry(.reading, path: "/here2.m4a")
        let missing = entry(.queued, path: "/gone.m4a", updated: now.addingTimeInterval(-60))
        let transcribing = entry(.transcribing, path: "/gone.m4a")
        let done = entry(.ready, path: "/gone.m4a")
        let result = AgentUploadStore.recovered(
            [waiting, interrupted, missing, transcribing, done], now: now,
            fileExists: { $0 != "/gone.m4a" })
        #expect(result.requeue.map(\.id) == [waiting.id, interrupted.id])
        #expect(result.entries.count == 5)
        #expect(result.entries[1].state == .queued)
        #expect(result.entries[2].state == .failed)
        #expect(result.entries[2].error == "File not found: /gone.m4a.")
        #expect(result.entries[2].updatedAt == now)
        #expect(result.entries[3] == transcribing)
        #expect(result.entries[4] == done)
    }

    @Test func mergeCopiesQueueStateAndStampsChanges() {
        let a = entry(.queued)
        let b = entry(.queued)
        var job = UploadJob(id: a.id, fileName: "a.m4a", kind: .audio, duration: 1, byteSize: 1)
        job.state = .transcribing
        job.meetingID = MeetingID(rawValue: "m9")
        job.progress = 0.4
        let later = now.addingTimeInterval(10)
        let merged = AgentUploadStore.merged([a, b], jobs: [job], now: later)
        #expect(merged[0].state == .transcribing && merged[0].meetingID == MeetingID(rawValue: "m9"))
        #expect(merged[0].updatedAt == later)
        #expect(merged[1] == b)
        // Progress alone is not a change.
        job.progress = 0.8
        #expect(AgentUploadStore.merged(merged, jobs: [job], now: later.addingTimeInterval(5)) == merged)
        job.state = .failed
        job.errorMessage = "Could not read this file."
        let failed = AgentUploadStore.merged(merged, jobs: [job], now: later)
        #expect(failed[0].state == .failed && failed[0].error == "Could not read this file.")
    }

    @Test func entryBecomesAJob() {
        var e = entry(.failed, path: "/x/Standup.m4a")
        e.error = "File not found: /x/Standup.m4a."
        let job = e.job
        #expect(job.id == e.id && job.fileName == "Standup.m4a" && job.addedBy == "claude-code")
        #expect(job.state == .failed && job.errorMessage == e.error)
    }
}
