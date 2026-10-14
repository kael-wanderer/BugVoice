import Foundation
import Testing
@testable import BugVoiceMac

struct KeychainTests {
    @Test func writeReadOverwriteDelete() {
        // Test-only service: never touches the real "BugVoice" items.
        let keychain = Keychain(service: "BugVoiceTests-\(UUID().uuidString)")
        defer { keychain.write(nil, account: "openai") }
        #expect(keychain.read("openai") == nil)
        keychain.write("sk-1", account: "openai")
        #expect(keychain.read("openai") == "sk-1")
        keychain.write("sk-2", account: "openai")
        #expect(keychain.read("openai") == "sk-2")
        keychain.write(nil, account: "openai")
        #expect(keychain.read("openai") == nil)
    }
}
