import Foundation
import Testing
import VoiceCore
@testable import MCPKit

/// Collects what the bridge writes to stdout and what the fake app saw.
final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _lines: [JSONValue] = []
    private var _requests: [MCPWireRequest] = []
    private var _launches = 0

    func output(_ data: Data) {
        let s = String(decoding: data, as: UTF8.self)
        #expect(s.hasSuffix("\n") && !s.dropLast().contains("\n"))
        let v = (try? JSONDecoder().decode(JSONValue.self, from: data)) ?? .null
        lock.lock(); _lines.append(v); lock.unlock()
    }
    func saw(_ r: MCPWireRequest) { lock.lock(); _requests.append(r); lock.unlock() }
    func launched() { lock.lock(); _launches += 1; lock.unlock() }

    var lines: [JSONValue] { lock.lock(); defer { lock.unlock() }; return _lines }
    var requests: [MCPWireRequest] { lock.lock(); defer { lock.unlock() }; return _requests }
    var launches: Int { lock.lock(); defer { lock.unlock() }; return _launches }
}

private func line(_ s: String) -> Data { Data(s.utf8) }

private func call(_ id: Int, _ name: String, _ arguments: String = "{}") -> Data {
    line(#"{"jsonrpc":"2.0","id":\#(id),"method":"tools/call","params":{"name":"\#(name)","arguments":\#(arguments)}}"#)
}

private let initialize = line(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","clientInfo":{"name":"claude-code"}}}"#)

private func fakeApp(_ paths: MCPSocketPaths, _ recorder: Recorder, text: String = "ok") -> MCPSocketServer {
    MCPSocketServer(paths: paths) { r in
        recorder.saw(r)
        return MCPWireResponse(id: r.id, text: text, isError: false)
    }
}

private func bridge(_ paths: MCPSocketPaths, _ recorder: Recorder, wait: Double = 2, launch: @escaping @Sendable () -> Void = {}) -> MCPBridge {
    MCPBridge(
        paths: paths, appVersion: "1.3",
        launchApp: { recorder.launched(); launch() },
        waitSeconds: wait, output: { recorder.output($0) })
}

@Suite(.serialized)
struct MCPBridgeTests {
    @Test func handshake() async {
        let paths = shortTempPaths()
        let recorder = Recorder()
        let b = bridge(paths, recorder)
        await b.handle(line: initialize)
        #expect(recorder.lines.count == 1)
        let first = recorder.lines.first
        #expect(first?["id"] == .number(1))
        #expect(first?["result"]?["protocolVersion"] == .string("2025-03-26"))
        #expect(first?["result"]?["serverInfo"]?["version"] == .string("1.3"))
        await b.handle(line: line(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#))
        #expect(recorder.lines.count == 1)
        await b.handle(line: line(#"{"jsonrpc":"2.0","id":"p","method":"ping"}"#))
        #expect(recorder.lines.last?["id"] == .string("p"))
        #expect(recorder.lines.last?["result"] == .object([:]))
    }

    @Test func toolsListWorksWithoutApp() async {
        let paths = shortTempPaths()
        let recorder = Recorder()
        await bridge(paths, recorder).handle(line: line(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#))
        #expect(recorder.lines.first?["result"]?["tools"]?.arrayValue?.count == 12)
        #expect(recorder.launches == 0)
    }

    @Test func forwardsToolCall() async throws {
        let paths = shortTempPaths()
        defer { removeTemp(paths) }
        let recorder = Recorder()
        let server = fakeApp(paths, recorder)
        try server.start()
        defer { server.stop() }
        let b = bridge(paths, recorder)
        await b.handle(line: initialize)
        await b.handle(line: call(7, "list_notes", #"{"limit":2}"#))
        let reply = recorder.lines.last
        #expect(reply?["id"] == .number(7))
        #expect(reply?["result"]?["content"]?.arrayValue?.first?["text"] == .string("ok"))
        #expect(reply?["result"]?["isError"] == .bool(false))
        #expect(recorder.requests.first?.client == "claude-code")
        #expect(recorder.requests.first?.tool == "list_notes")
        #expect(recorder.requests.first?.arguments == .object(["limit": .number(2)]))
        await b.handle(line: call(8, "list_folders"))
        #expect(recorder.requests.count == 2)
        #expect(recorder.launches == 0)
    }

    @Test func reconnectsAfterAppRestart() async throws {
        let paths = shortTempPaths()
        defer { removeTemp(paths) }
        let recorder = Recorder()
        let first = fakeApp(paths, recorder)
        try first.start()
        let b = bridge(paths, recorder)
        await b.handle(line: call(1, "list_folders"))
        first.stop()
        let second = fakeApp(paths, recorder, text: "again")
        try second.start()
        defer { second.stop() }
        try await Task.sleep(for: .milliseconds(100))
        await b.handle(line: call(2, "list_folders"))
        #expect(recorder.lines.last?["result"]?["content"]?.arrayValue?.first?["text"] == .string("again"))
    }

    @Test func writeToolIsNotResentAfterTheAppReceivedIt() async throws {
        let paths = shortTempPaths()
        defer { removeTemp(paths) }
        let raw = try RawServer(paths: paths)
        defer { raw.stop() }
        let recorder = Recorder()
        await bridge(paths, recorder).handle(line: call(10, "create_note", #"{"title":"T","body":"b"}"#))
        #expect(raw.lines == 1)
        let result = recorder.lines.last?["result"]
        #expect(result?["isError"] == .bool(true))
        #expect(result?["content"]?.arrayValue?.first?["text"] == .string(MCPBridge.lostAfterSending))
    }

    @Test func readToolIsResentOnce() async throws {
        let paths = shortTempPaths()
        defer { removeTemp(paths) }
        let raw = try RawServer(paths: paths)
        defer { raw.stop() }
        let recorder = Recorder()
        await bridge(paths, recorder).handle(line: call(11, "list_folders"))
        #expect(raw.lines == 2)
        #expect(recorder.lines.last?["result"]?["content"]?.arrayValue?.first?["text"] == .string(MCPBridge.connectionLost))
    }

    @Test func argumentErrorNotForwarded() async throws {
        let paths = shortTempPaths()
        defer { removeTemp(paths) }
        let recorder = Recorder()
        let server = fakeApp(paths, recorder)
        try server.start()
        defer { server.stop() }
        await bridge(paths, recorder).handle(line: call(3, "search"))
        let result = recorder.lines.last?["result"]
        #expect(result?["isError"] == .bool(true))
        #expect(result?["content"]?.arrayValue?.first?["text"] == .string("query must be a non-empty string."))
        #expect(recorder.requests.isEmpty)
    }

    @Test func launchesAppWhenSocketMissing() async throws {
        let paths = shortTempPaths()
        defer { removeTemp(paths) }
        let recorder = Recorder()
        let server = fakeApp(paths, recorder)
        defer { server.stop() }
        let b = bridge(paths, recorder, wait: 5) {
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { try? server.start() }
        }
        await b.handle(line: call(4, "list_folders"))
        #expect(recorder.lines.last?["result"]?["content"]?.arrayValue?.first?["text"] == .string("ok"))
        #expect(recorder.launches == 1)
    }

    @Test func reportsDidNotStart() async {
        let paths = shortTempPaths()
        let recorder = Recorder()
        let b = bridge(paths, recorder, wait: 0.5)
        await b.handle(line: call(5, "list_folders"))
        let result = recorder.lines.last?["result"]
        #expect(result?["isError"] == .bool(true))
        #expect(result?["content"]?.arrayValue?.first?["text"] == .string("BugVoice did not start. Open it and try again."))
        await b.handle(line: call(6, "list_folders"))
        #expect(recorder.launches == 1)
    }

    @Test func unknownMethod() async {
        let recorder = Recorder()
        await bridge(shortTempPaths(), recorder).handle(line: line(#"{"jsonrpc":"2.0","id":9,"method":"resources/list"}"#))
        #expect(recorder.lines.first?["error"]?["code"] == .number(-32601))
        #expect(recorder.lines.first?["id"] == .number(9))
    }

    @Test func garbageLine() async {
        let recorder = Recorder()
        await bridge(shortTempPaths(), recorder).handle(line: line("nope"))
        #expect(recorder.lines.first?["error"]?["code"] == .number(-32700))
        #expect(recorder.lines.first?["id"] == .null)
    }
}
