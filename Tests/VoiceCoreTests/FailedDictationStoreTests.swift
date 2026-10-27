import Foundation
import Testing
@testable import VoiceCore

struct FailedDictationStoreTests {
    let now = Date(timeIntervalSince1970: 2_000_000_000)

    func makeStore() -> (FailedDictationStore, URL) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("bv-failed-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Failed", isDirectory: true)
        return (FailedDictationStore(folder: folder), folder)
    }

    func item(_ age: TimeInterval = 0, app: String = "Notion") -> FailedDictation {
        FailedDictation(id: UUID(), startedAt: now.addingTimeInterval(-age), appName: app,
                        bundleID: "notion.id", duration: 4.2, reason: "The service had an error.")
    }

    func mode(_ url: URL) throws -> Int {
        try (FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    @Test func emptyFolderLoadsNothing() {
        let (store, _) = makeStore()
        #expect(store.load(now: now).isEmpty)
    }

    @Test func saveRoundTripsOwnerOnly() throws {
        let (store, folder) = makeStore()
        let saved = item()
        try store.save(saved, audio: Data("RIFF".utf8), now: now)
        #expect(store.load(now: now) == [saved])
        #expect(try Data(contentsOf: store.audioURL(saved.id)) == Data("RIFF".utf8))
        #expect(try mode(folder) == 0o700)
        #expect(try mode(store.audioURL(saved.id)) == 0o600)
        #expect(try mode(store.recordURL(saved.id)) == 0o600)
    }

    @Test func newestFirst() throws {
        let (store, _) = makeStore()
        let old = item(600), new = item(60)
        try store.save(old, audio: Data(), now: now)
        try store.save(new, audio: Data(), now: now)
        #expect(store.load(now: now).map(\.id) == [new.id, old.id])
    }

    @Test func capRemovesOldest() throws {
        let (store, _) = makeStore()
        let items = (0..<(FailedDictationStore.maxCount + 2)).map { item(TimeInterval($0) * 60) }
        for entry in items { try store.save(entry, audio: Data(), now: now) }
        let kept = store.load(now: now)
        #expect(kept.map(\.id) == Array(items.prefix(FailedDictationStore.maxCount)).map(\.id))
        for dropped in items.suffix(2) {
            #expect(!FileManager.default.fileExists(atPath: store.audioURL(dropped.id).path))
        }
    }

    @Test func expiresAfterMaxAge() throws {
        let (store, _) = makeStore()
        let stale = item(FailedDictationStore.maxAge + 1), fresh = item(60)
        try store.save(stale, audio: Data(), now: now.addingTimeInterval(-FailedDictationStore.maxAge))
        try store.save(fresh, audio: Data(), now: now)
        #expect(store.load(now: now) == [fresh])
        #expect(!FileManager.default.fileExists(atPath: store.audioURL(stale.id).path))
        #expect(!FileManager.default.fileExists(atPath: store.recordURL(stale.id).path))
    }

    @Test func corruptRecordAndMissingAudioAreDropped() throws {
        let (store, folder) = makeStore()
        let good = item(), noAudio = item(30)
        try store.save(good, audio: Data(), now: now)
        try store.save(noAudio, audio: Data(), now: now)
        try FileManager.default.removeItem(at: store.audioURL(noAudio.id))
        let corrupt = UUID()
        try Data("not json".utf8).write(to: folder.appendingPathComponent("\(corrupt.uuidString).json"))
        try Data().write(to: folder.appendingPathComponent("\(corrupt.uuidString).wav"))
        #expect(store.load(now: now) == [good])
        #expect(!FileManager.default.fileExists(atPath: store.recordURL(noAudio.id).path))
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("\(corrupt.uuidString).wav").path))
    }

    @Test func orphanAudioIsRemoved() throws {
        let (store, folder) = makeStore()
        try store.save(item(), audio: Data(), now: now)
        let orphan = folder.appendingPathComponent("\(UUID().uuidString).wav")
        try Data().write(to: orphan)
        _ = store.load(now: now)
        #expect(!FileManager.default.fileExists(atPath: orphan.path))
    }

    @Test func updateKeepsAudioAndReplacesRecord() throws {
        let (store, _) = makeStore()
        var entry = item()
        try store.save(entry, audio: Data("RIFF".utf8), now: now)
        entry.reason = "The key was refused."
        try store.update(entry)
        #expect(store.load(now: now) == [entry])
        #expect(try Data(contentsOf: store.audioURL(entry.id)) == Data("RIFF".utf8))
    }

    @Test func removeAndRemoveAll() throws {
        let (store, _) = makeStore()
        let a = item(), b = item(30)
        try store.save(a, audio: Data(), now: now)
        try store.save(b, audio: Data(), now: now)
        store.remove(a.id)
        #expect(store.load(now: now) == [b])
        store.removeAll()
        #expect(store.load(now: now).isEmpty)
    }

    @Test func ignoresFilesThatAreNotItsOwn() throws {
        let (store, folder) = makeStore()
        try store.save(item(), audio: Data(), now: now)
        let stray = folder.appendingPathComponent(".DS_Store")
        try Data().write(to: stray)
        _ = store.load(now: now)
        #expect(FileManager.default.fileExists(atPath: stray.path))
    }
}
