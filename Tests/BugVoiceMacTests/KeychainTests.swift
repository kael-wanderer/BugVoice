import Foundation
import Testing
@testable import BugVoiceMac

struct KeychainTests {
    /// Test-only service: never touches the real "BugVoice" items.
    private func makeKeychain() -> Keychain {
        Keychain(service: "BugVoiceTests-\(UUID().uuidString)")
    }

    @Test func writeReadOverwriteDelete() throws {
        let keychain = makeKeychain()
        defer { try? keychain.write(nil, account: "openai") }
        #expect(keychain.read("openai") == nil)
        try keychain.write("sk-1", account: "openai")
        #expect(keychain.read("openai") == "sk-1")
        try keychain.write("sk-2", account: "openai")
        #expect(keychain.read("openai") == "sk-2")
        try keychain.write(nil, account: "openai")
        #expect(keychain.read("openai") == nil)
    }

    @Test func overwriteKeepsOtherAccountsAndUpdatesInPlace() throws {
        let keychain = makeKeychain()
        defer {
            try? keychain.write(nil, account: "a")
            try? keychain.write(nil, account: "b")
        }
        try keychain.write("one", account: "a")
        try keychain.write("other", account: "b")
        try keychain.write("two", account: "a")
        #expect(keychain.read("a") == "two")
        #expect(keychain.read("b") == "other")
    }

    @Test func deletingMissingItemAndEmptyValueDoNotThrow() throws {
        let keychain = makeKeychain()
        defer { try? keychain.write(nil, account: "a") }
        try keychain.write(nil, account: "a")
        try keychain.write("x", account: "a")
        try keychain.write("", account: "a")
        #expect(keychain.read("a") == nil)
    }
}
