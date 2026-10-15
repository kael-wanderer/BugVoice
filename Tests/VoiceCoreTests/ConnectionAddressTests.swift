import Foundation
import Testing
@testable import VoiceCore

struct ConnectionAddressTests {
    func connection(_ kind: ConnectionKind, _ url: String) -> ModelConnection {
        ModelConnection(id: "c-1", name: "C", kind: kind, baseURL: url, model: "m")
    }

    @Test func fixedKindsIgnoreTheStoredAddress() {
        #expect(ConnectionAddress.baseURL(for: connection(.openAI, "http://evil.example")) == URL(string: "https://api.openai.com"))
        #expect(ConnectionAddress.baseURL(for: connection(.anthropic, "")) == URL(string: "https://api.anthropic.com"))
        #expect(ConnectionAddress.baseURL(for: connection(.openRouter, "x")) == URL(string: "https://openrouter.ai/api"))
    }

    @Test(arguments: ["http://localhost:1234", "http://127.0.0.1:8080", "http://[::1]:11434", "https://llm.example.com", " https://llm.example.com/v1 "])
    func acceptedAddresses(url: String) {
        #expect(ConnectionAddress.problem(url) == nil)
        #expect(ConnectionAddress.baseURL(for: connection(.openAICompatible, url)) != nil)
    }

    @Test(arguments: [
        ("http://192.168.1.5:8000", "Use https:// for a server that is not on this Mac."),
        ("http://localhost.example.com", "Use https:// for a server that is not on this Mac."),
        ("https://user:pass@llm.example.com", "Remove the user name and password from the address."),
        ("https://llm.example.com/?key=1", "Remove the ? or # part of the address."),
        ("https://llm.example.com/#x", "Remove the ? or # part of the address."),
        ("ftp://llm.example.com", "Enter an address like http://localhost:1234."),
        ("https://", "Enter an address like http://localhost:1234."),
        ("", "Enter an address like http://localhost:1234."),
    ])
    func refusedAddresses(url: String, message: String) {
        #expect(ConnectionAddress.problem(url) == message)
        #expect(ConnectionAddress.baseURL(for: connection(.anthropicCompatible, url)) == nil)
    }

    @Test func localMeansLoopback() {
        #expect(ConnectionAddress.isLocal(URL(string: "http://localhost:1234")!))
        #expect(ConnectionAddress.isLocal(URL(string: "http://[::1]:1")!))
        #expect(!ConnectionAddress.isLocal(URL(string: "https://api.openai.com")!))
    }
}
