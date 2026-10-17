import Foundation
import Testing
@testable import VoiceCore

struct MCPProtocolTests {
    @Test func negotiatesVersions() {
        #expect(MCPProtocol.negotiate("2025-03-26") == "2025-03-26")
        #expect(MCPProtocol.negotiate("1999-01-01") == "2025-06-18")
        #expect(MCPProtocol.negotiate(nil) == "2025-06-18")
    }
    @Test func initializeResultShape() {
        let r = MCPProtocol.initializeResult(version: "2025-06-18", appVersion: "1.3")
        #expect(r["protocolVersion"] == .string("2025-06-18"))
        #expect(r["serverInfo"]?["name"] == .string("bugvoice"))
        #expect(r["serverInfo"]?["version"] == .string("1.3"))
        #expect(r["capabilities"]?["tools"] == .object([:]))
    }
    @Test func parsesRequestAndRejectsGarbage() {
        let ok = JSONRPCMessage.parse(Data(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#.utf8))
        #expect((try? ok.get())?.method == "ping")
        #expect((try? ok.get())?.id == .number(1))
        guard case .failure(let e) = JSONRPCMessage.parse(Data("nope".utf8)) else { Issue.record("parsed"); return }
        #expect(e.code == JSONRPCError.parse)
    }
    @Test func notificationHasNoID() throws {
        let m = try JSONRPCMessage.parse(Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8)).get()
        #expect(m.id == nil)
        #expect(m.method == "notifications/initialized")
    }
    @Test func nonObjectIsInvalidRequest() {
        guard case .failure(let e) = JSONRPCMessage.parse(Data("[1,2]".utf8)) else { Issue.record("parsed"); return }
        #expect(e.code == JSONRPCError.invalidRequest)
    }
    @Test func encodedLineIsOneLine() {
        let d = JSONValue.object(["a": .string("x\ny")]).encodedLine()
        let s = String(decoding: d, as: UTF8.self)
        #expect(s.hasSuffix("\n") && s.dropLast().contains("\n") == false)
    }
    @Test func jsonValueRoundTrip() throws {
        let v = JSONValue.object([
            "n": .number(1.5), "i": .number(3), "b": .bool(true), "z": .null,
            "a": .array([.string("s"), .number(-2)]), "o": .object(["k": .string("v")]),
        ])
        let back = try JSONDecoder().decode(JSONValue.self, from: v.encodedLine())
        #expect(back == v)
        #expect(back["i"]?.intValue == 3)
        #expect(back["n"]?.intValue == nil)
        #expect(back["b"]?.boolValue == true)
    }
    @Test func responseEncodesIDAndError() throws {
        let line = JSONRPCMessage(id: .null, error: JSONRPCError(code: JSONRPCError.parse, message: "Parse error.")).encodedLine()
        let v = try JSONDecoder().decode(JSONValue.self, from: line)
        #expect(v["jsonrpc"] == .string("2.0"))
        #expect(v["id"] == .null)
        #expect(v["error"]?["code"]?.intValue == -32700)
    }
    @Test func toolResultShape() {
        let r = MCPProtocol.toolResult(text: "hi", isError: true)
        #expect(r["content"]?.arrayValue?.first?["type"] == .string("text"))
        #expect(r["content"]?.arrayValue?.first?["text"] == .string("hi"))
        #expect(r["isError"] == .bool(true))
    }
}
