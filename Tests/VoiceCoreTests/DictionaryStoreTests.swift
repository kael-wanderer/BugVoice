import Foundation
import Testing
@testable import VoiceCore

struct DictionaryStoreTests {
    func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bv-dict-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func sample() -> DictionaryFile {
        var f = DictionaryFile()
        f.addWords("Kael")
        _ = try? f.addSnippet(trigger: "sign off", text: "Best,\nKael")
        return f
    }

    @Test func missingFileLoadsEmpty() async {
        let (file, issue) = await DictionaryStore(url: tempDir().appendingPathComponent("dictionary.json")).load()
        #expect(file == DictionaryFile())
        #expect(issue == .none)
    }

    @Test func saveRoundTrips() async throws {
        let url = tempDir().appendingPathComponent("dictionary.json")
        let saved = sample()
        try await DictionaryStore(url: url).save(saved)
        let (file, issue) = await DictionaryStore(url: url).load()
        #expect(file == saved)
        #expect(file.snippets.first?.text == "Best,\nKael")
        #expect(issue == .none)
    }

    @Test func damagedFileIsRenamedAndStartsEmpty() async throws {
        let dir = tempDir()
        let url = dir.appendingPathComponent("dictionary.json")
        try Data("{nope".utf8).write(to: url)
        let (file, issue) = await DictionaryStore(url: url).load(now: Date(timeIntervalSince1970: 1_700_000_000))
        #expect(file == DictionaryFile())
        #expect(issue == .resetFromCorrupt)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(names == ["dictionary.corrupt-1700000000.json"])
    }

    @Test func newerSchemaIsReadOnly() async throws {
        let url = tempDir().appendingPathComponent("dictionary.json")
        let original = Data(#"{"schemaVersion":2,"words":[{"word":"Kael"}]}"#.utf8)
        try original.write(to: url)
        let store = DictionaryStore(url: url)
        let (_, issue) = await store.load()
        #expect(issue == .newerVersion)
        await #expect(throws: DictionaryStoreError.newerVersion) { try await store.save(sample()) }
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func olderRevisionIsIgnored() async throws {
        let url = tempDir().appendingPathComponent("dictionary.json")
        let store = DictionaryStore(url: url)
        var newer = DictionaryFile()
        newer.addWords("Kael, BugVoice")
        var older = DictionaryFile()
        older.addWords("Kael")
        try await store.save(newer, revision: 2)
        try await store.save(older, revision: 1)
        let (file, _) = await DictionaryStore(url: url).load()
        #expect(file.words.map(\.word) == ["Kael", "BugVoice"])
    }

    @Test func migratesVocabularyTxtAndRenamesIt() async throws {
        let dir = tempDir()
        let url = dir.appendingPathComponent("dictionary.json")
        let vocab = dir.appendingPathComponent("vocabulary.txt")
        try "# terms\nBugVoice\nWhisperKit\n\nmy linkedin => linkedin.com/in/kael\nsign off => Best,\\nKael\n".write(to: vocab, atomically: true, encoding: .utf8)
        let store = DictionaryStore(url: url)
        #expect(try await store.migrateIfNeeded(vocabularyURL: vocab))
        let (file, issue) = await store.load()
        #expect(issue == .none)
        #expect(file.words.map(\.word) == ["WhisperKit", "BugVoice"])
        #expect(file.snippets.map(\.trigger) == ["sign off", "my linkedin"])
        #expect(file.snippets[0].text == "Best,\nKael")
        #expect(!FileManager.default.fileExists(atPath: vocab.path))
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("vocabulary.migrated.txt").path))
    }

    @Test func existingMigratedFileGetsATimestampedName() async throws {
        let dir = tempDir()
        let vocab = dir.appendingPathComponent("vocabulary.txt")
        try "Kael\n".write(to: vocab, atomically: true, encoding: .utf8)
        try "old\n".write(to: dir.appendingPathComponent("vocabulary.migrated.txt"), atomically: true, encoding: .utf8)
        let store = DictionaryStore(url: dir.appendingPathComponent("dictionary.json"))
        #expect(try await store.migrateIfNeeded(vocabularyURL: vocab, now: Date(timeIntervalSince1970: 1_700_000_000)))
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("vocabulary.migrated-1700000000.txt").path))
        #expect(try String(contentsOf: dir.appendingPathComponent("vocabulary.migrated.txt"), encoding: .utf8) == "old\n")
    }

    @Test func noMigrationWhenDictionaryExists() async throws {
        let dir = tempDir()
        let url = dir.appendingPathComponent("dictionary.json")
        let vocab = dir.appendingPathComponent("vocabulary.txt")
        try await DictionaryStore(url: url).save(sample())
        try "BugVoice\n".write(to: vocab, atomically: true, encoding: .utf8)
        let store = DictionaryStore(url: url)
        let migrated = try await store.migrateIfNeeded(vocabularyURL: vocab)
        #expect(!migrated)
        #expect(FileManager.default.fileExists(atPath: vocab.path))
        #expect(await store.load().0.words.map(\.word) == ["Kael"])
    }

    @Test func noVocabularyMeansNoFile() async throws {
        let dir = tempDir()
        let url = dir.appendingPathComponent("dictionary.json")
        let migrated = try await DictionaryStore(url: url).migrateIfNeeded(vocabularyURL: dir.appendingPathComponent("vocabulary.txt"))
        #expect(!migrated)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
