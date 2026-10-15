import Foundation
import Testing
@testable import VoiceCore

struct CredentialStoreTests {
    func makeStore() -> (CredentialStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bv-cred-\(UUID().uuidString)", isDirectory: true)
        let url = dir.appendingPathComponent("credentials.json")
        return (CredentialStore(url: url), url)
    }

    func mode(_ url: URL) throws -> Int {
        try (FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    @Test func missingFileReadsNothing() {
        let (store, _) = makeStore()
        #expect(store.read("openai") == nil)
        #expect(store.keychainImported == false)
    }

    @Test func writeReadReplaceDelete() throws {
        let (store, _) = makeStore()
        try store.write("sk-1", account: "a")
        try store.write("other", account: "b")
        try store.write("sk-2", account: "a")
        #expect(store.read("a") == "sk-2")
        #expect(store.read("b") == "other")
        try store.write(nil, account: "a")
        try store.write("", account: "b")
        #expect(store.read("a") == nil)
        #expect(store.read("b") == nil)
        try store.write(nil, account: "never-written")
    }

    @Test func fileAndFolderAreOwnerOnly() throws {
        let (store, url) = makeStore()
        try store.write("sk-1", account: "a")
        #expect(try mode(url) == 0o600)
        #expect(try mode(url.deletingLastPathComponent()) == 0o700)
    }

    @Test func looserFileIsTightenedOnWrite() throws {
        let (store, url) = makeStore()
        try store.write("sk-1", account: "a")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        try store.write("sk-2", account: "a")
        #expect(try mode(url) == 0o600)
    }

    @Test func formatIsVersionedJSON() throws {
        let (store, url) = makeStore()
        try store.write("sk-1", account: "connection-x")
        try store.markKeychainImported()
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        #expect(object?["version"] as? Int == 1)
        #expect(object?["keychainImported"] as? Bool == true)
        #expect((object?["entries"] as? [String: String])?["connection-x"] == "sk-1")
        #expect(CredentialStore(url: url).keychainImported)
    }

    /// A file this build cannot read is never overwritten: that would lose every key in it.
    @Test func unreadableFileIsNotOverwritten() throws {
        let (store, url) = makeStore()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        #expect(store.read("a") == nil)
        #expect(throws: CredentialStoreError.unreadable) { try store.write("sk", account: "a") }
        #expect(try String(contentsOf: url, encoding: .utf8) == "not json")
    }

    @Test func newerVersionIsNotOverwritten() throws {
        let (store, url) = makeStore()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"version":2,"entries":{"a":"x"}}"#.utf8).write(to: url)
        #expect(throws: CredentialStoreError.unreadable) { try store.write("sk", account: "a") }
    }

    @Test func importMovesOnlyMissingKeysAndReportsWhatToDelete() throws {
        let (store, _) = makeStore()
        try store.write("kept", account: "openai")
        let legacy = ["openai": "old", "anthropic": "sk-ant", "speech-openai": ""]
        let moved = try store.importLegacy(accounts: ["openai", "anthropic", "speech-openai", "connection-z"]) { legacy[$0] }
        #expect(store.read("openai") == "kept")
        #expect(store.read("anthropic") == "sk-ant")
        #expect(store.read("speech-openai") == nil)
        #expect(moved == ["anthropic"])
        #expect(store.keychainImported)
    }
}
