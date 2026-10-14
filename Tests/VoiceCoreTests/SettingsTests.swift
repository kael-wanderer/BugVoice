import Foundation
import Testing
@testable import VoiceCore

struct SettingsTests {
    func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bv-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func defaultsMatchSpec() {
        let s = AppSettings()
        #expect(s.hotkey == .rightOption)
        #expect(s.handsFreeLimitMinutes == 10)
        #expect(s.cleanupEnabled)
        #expect(s.speech.whisperModel == "large-v3-v20240930_turbo")
        #expect(s.textModel.provider == .openAICompatible)
        #expect(s.textModel.baseURL == "http://localhost:1234")
        #expect(s.textModel.model == "qwen3.8-27b-mlx")
        #expect(s.textModel.timeoutSeconds == 3)
        #expect(s.styles.isCleanupEnabled(for: .terminal) == false)
        #expect(s.styles.isCleanupEnabled(for: .document))
    }

    @Test func roundTripsThroughStore() throws {
        let store = SettingsStore(url: tempDir().appendingPathComponent("settings.json"))
        var s = AppSettings()
        s.speech.language = .vi
        s.styles.appOverrides["com.example.app"] = .document
        s.styles.customRules["document"] = "Be brief."
        try store.save(s)
        #expect(store.load() == s)
    }

    @Test func missingKeysFallBackToDefaults() throws {
        let url = tempDir().appendingPathComponent("settings.json")
        try Data(#"{"hotkey":"fn","textModel":{"model":"other"}}"#.utf8).write(to: url)
        let s = SettingsStore(url: url).load()
        #expect(s.hotkey == .fn)
        #expect(s.textModel.model == "other")
        #expect(s.textModel.baseURL == "http://localhost:1234")
        #expect(s.speech.language == SpeechSettings().language)
    }

    @Test func unknownEnumValueFallsBackToDefault() throws {
        let url = tempDir().appendingPathComponent("settings.json")
        try Data(#"{"hotkey":"capsLock"}"#.utf8).write(to: url)
        #expect(SettingsStore(url: url).load().hotkey == .rightOption)
    }

    @Test func corruptFileIsSetAsideAndDefaultsLoad() throws {
        let dir = tempDir()
        let url = dir.appendingPathComponent("settings.json")
        try Data("{not json".utf8).write(to: url)
        #expect(SettingsStore(url: url).load() == AppSettings())
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(names.contains { $0.hasPrefix("settings.json.corrupt-") })
    }

    @Test func pathsAreUnderRoot() throws {
        let root = tempDir()
        let paths = AppPaths(root: root)
        try paths.ensureExists()
        #expect(paths.history.lastPathComponent == "history.jsonl")
        #expect(paths.lastRecording.lastPathComponent == "last.wav")
        #expect(FileManager.default.fileExists(atPath: paths.models.path))
        #expect(paths.meetings.lastPathComponent == "Meetings")
        #expect(FileManager.default.fileExists(atPath: paths.meetings.path))
        #expect(paths.notes.lastPathComponent == "Notes")
    }

    @Test func retentionMaxAge() {
        #expect(Retention.forever.maxAge == nil)
        #expect(Retention.days7.maxAge == 7 * 86_400.0)
    }
}
