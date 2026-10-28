import Foundation
import Testing
@testable import VoiceCore

struct InflightDictationStoreTests {
    @Test func recoveryAndInvalidation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let marker = InflightDictationStore(url: root.appendingPathComponent("inflight.json"))
        let failed = FailedDictationStore(folder: root.appendingPathComponent("Failed"))
        let wav = root.appendingPathComponent("last.wav")
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let item = InflightDictation(id: UUID(), startedAt: now, appName: "Notion", bundleID: "notion", duration: 1)
        try marker.begin(item)
        #expect(try (FileManager.default.attributesOfItem(atPath: marker.url.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        try WAVEncoder.encode(AudioClip(samples: Array(repeating: 0, count: 16000))).write(to: wav)
        try marker.recover(into: failed, lastRecording: wav, now: now)
        #expect(failed.load(now: now).first?.id == item.id)
        #expect(failed.load(now: now).first?.reason == "BugVoice quit before this dictation finished.")
        try marker.recover(into: failed, lastRecording: wav, now: now)
        #expect(failed.load(now: now).count == 1)
        try marker.begin(item)
        try WAVEncoder.encode(AudioClip(samples: Array(repeating: 0, count: 32000))).write(to: wav)
        try marker.recover(into: failed, lastRecording: wav, now: now)
        #expect(!FileManager.default.fileExists(atPath: marker.url.path))
        try marker.begin(item)
        marker.end()
        #expect(!FileManager.default.fileExists(atPath: marker.url.path))
    }
    @Test func replacingOrDeletingLastRecordingClearsMarker() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = InflightDictationStore(url: root.appendingPathComponent("inflight.json"))
        let wav = root.appendingPathComponent("last.wav")
        let item = InflightDictation(id: UUID(), startedAt: Date(), appName: nil, bundleID: nil, duration: 1)
        try store.begin(item)
        try store.replaceLastRecording(at: wav, with: Data("new".utf8))
        #expect(!FileManager.default.fileExists(atPath: store.url.path))
        try store.begin(item)
        try store.replaceLastRecording(at: wav, with: nil)
        #expect(!FileManager.default.fileExists(atPath: store.url.path))
        #expect(!FileManager.default.fileExists(atPath: wav.path))
    }

    @Test func missingDamagedAndExpiredAreDiscarded() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let marker = InflightDictationStore(url: root.appendingPathComponent("inflight.json"))
        let failed = FailedDictationStore(folder: root.appendingPathComponent("Failed"))
        let wav = root.appendingPathComponent("last.wav")
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let item = InflightDictation(id: UUID(), startedAt: now, appName: nil, bundleID: nil, duration: 1)
        try marker.begin(item)
        #expect(try (FileManager.default.attributesOfItem(atPath: root.path)[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        try marker.recover(into: failed, lastRecording: wav, now: now)
        #expect(!FileManager.default.fileExists(atPath: marker.url.path))
        try marker.begin(item)
        try Data("bad".utf8).write(to: marker.url)
        try marker.recover(into: failed, lastRecording: wav, now: now)
        #expect(!FileManager.default.fileExists(atPath: marker.url.path))
        try marker.begin(item)
        try WAVEncoder.encode(AudioClip(samples: Array(repeating: 0, count: 16000))).write(to: wav)
        try marker.recover(into: failed, lastRecording: wav, now: now.addingTimeInterval(FailedDictationStore.maxAge + 1))
        #expect(!FileManager.default.fileExists(atPath: marker.url.path))
        #expect(failed.load(now: now).isEmpty)
    }

}
