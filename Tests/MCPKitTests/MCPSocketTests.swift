import Darwin
import Foundation
import Testing
@testable import MCPKit

/// A short folder under /tmp: `sun_path` holds 104 bytes.
func shortTempPaths() -> MCPSocketPaths {
    let hex = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8).lowercased()
    return MCPSocketPaths(folder: URL(fileURLWithPath: "/tmp/bv-\(hex)", isDirectory: true))
}

func removeTemp(_ paths: MCPSocketPaths) {
    try? FileManager.default.removeItem(at: paths.folder)
}

func echoServer(_ paths: MCPSocketPaths, maxConnections: Int = 4, peerCheck: @escaping @Sendable (Int32) -> Bool = MCPSocketServer.sameUser) -> MCPSocketServer {
    MCPSocketServer(paths: paths, maxConnections: maxConnections, peerCheck: peerCheck) { r in
        MCPWireResponse(id: r.id, text: r.tool, isError: false)
    }
}

func request(_ tool: String = "ask") -> MCPWireRequest {
    MCPWireRequest(id: UUID().uuidString, tool: tool, arguments: nil, client: "test")
}

/// A raw connected socket for writing bytes the client never would.
func rawConnect(_ paths: MCPSocketPaths) throws -> Int32 {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    var on: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    var addr = try MCPSocketAddress.make(paths.socket.path)
    let result = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    guard result == 0 else { Darwin.close(fd); throw MCPSocketError.notListening }
    return fd
}

/// Reads until a newline or end of file.
func rawReadLine(_ fd: Int32) -> String? {
    var bytes: [UInt8] = []
    var byte: UInt8 = 0
    while read(fd, &byte, 1) == 1 {
        if byte == 0x0A { return String(decoding: bytes, as: UTF8.self) }
        bytes.append(byte)
    }
    return nil
}

@Suite(.serialized)
struct MCPSocketTests {
    @Test func roundTrip() async throws {
        let paths = shortTempPaths()
        defer { removeTemp(paths) }
        let server = echoServer(paths)
        try server.start()
        defer { server.stop() }
        let client = try MCPSocketClient.connect(paths: paths)
        defer { client.close() }
        let r = request("ask")
        let response = try await client.send(r)
        #expect(response == MCPWireResponse(id: r.id, text: "ask", isError: false))
        let second = try await client.send(request("search"))
        #expect(second.text == "search")
    }

    @Test func concurrentRequestsMatchByID() async throws {
        let paths = shortTempPaths()
        defer { removeTemp(paths) }
        let server = MCPSocketServer(paths: paths) { r in
            if r.tool == "slow" { try? await Task.sleep(for: .milliseconds(300)) }
            return MCPWireResponse(id: r.id, text: r.tool, isError: false)
        }
        try server.start()
        defer { server.stop() }
        let client = try MCPSocketClient.connect(paths: paths)
        defer { client.close() }
        async let slow = client.send(request("slow"))
        try await Task.sleep(for: .milliseconds(50))
        let fast = try await client.send(request("fast"))
        #expect(fast.text == "fast")
        #expect(try await slow.text == "slow")
    }

    @Test func permissions() throws {
        let paths = shortTempPaths()
        defer { removeTemp(paths) }
        try FileManager.default.createDirectory(at: paths.folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        let server = echoServer(paths)
        try server.start()
        defer { server.stop() }
        let folder = try FileManager.default.attributesOfItem(atPath: paths.folder.path)[.posixPermissions] as? Int
        let socket = try FileManager.default.attributesOfItem(atPath: paths.socket.path)[.posixPermissions] as? Int
        #expect(folder == 0o700)
        #expect(socket == 0o600)
    }

    @Test func staleSocketReplaced() async throws {
        let paths = shortTempPaths()
        defer { removeTemp(paths) }
        try FileManager.default.createDirectory(at: paths.folder, withIntermediateDirectories: true)
        try Data("stale".utf8).write(to: paths.socket)
        let server = echoServer(paths)
        try server.start()
        defer { server.stop() }
        let client = try MCPSocketClient.connect(paths: paths)
        defer { client.close() }
        #expect(try await client.send(request()).text == "ask")
    }

    @Test func rejectsForeignPeer() async throws {
        let paths = shortTempPaths()
        defer { removeTemp(paths) }
        let server = echoServer(paths, peerCheck: { _ in false })
        try server.start()
        defer { server.stop() }
        let client = try MCPSocketClient.connect(paths: paths)
        defer { client.close() }
        await expectClosedOrNotSent { try await client.send(request()) }
    }

    @Test func sameUserAcceptsThisProcess() async throws {
        let paths = shortTempPaths()
        defer { removeTemp(paths) }
        let seen = Flag()
        let server = echoServer(paths, peerCheck: { fd in
            let ok = MCPSocketServer.sameUser(fd)
            seen.set(ok)
            return ok
        })
        try server.start()
        defer { server.stop() }
        let client = try MCPSocketClient.connect(paths: paths)
        defer { client.close() }
        #expect(try await client.send(request()).text == "ask")
        #expect(seen.value)
    }

    @Test func fifthConnectionRefused() async throws {
        let paths = shortTempPaths()
        defer { removeTemp(paths) }
        let server = echoServer(paths)
        try server.start()
        defer { server.stop() }
        var clients: [MCPSocketClient] = []
        for _ in 0..<4 {
            let c = try MCPSocketClient.connect(paths: paths)
            _ = try await c.send(request())
            clients.append(c)
        }
        let fifth = try MCPSocketClient.connect(paths: paths)
        await expectClosedOrNotSent { try await fifth.send(request()) }
        fifth.close()
        clients.removeFirst().close()
        var worked = false
        for _ in 0..<40 where !worked {
            try await Task.sleep(for: .milliseconds(50))
            let c = try MCPSocketClient.connect(paths: paths)
            worked = (try? await c.send(request())) != nil
            c.close()
        }
        #expect(worked)
        clients.forEach { $0.close() }
    }

    @Test func oversizeLineClosesConnection() async throws {
        let paths = shortTempPaths()
        defer { removeTemp(paths) }
        let server = echoServer(paths)
        try server.start()
        defer { server.stop() }
        let fd = try rawConnect(paths)
        defer { Darwin.close(fd) }
        let writer = Thread {
            let chunk = [UInt8](repeating: 0x61, count: 64 * 1024)
            for _ in 0..<80 { if write(fd, chunk, chunk.count) < 0 { break } }
        }
        writer.start()
        #expect(rawReadLine(fd) == nil)
        let client = try MCPSocketClient.connect(paths: paths)
        defer { client.close() }
        #expect(try await client.send(request()).text == "ask")
    }

    @Test func badLineGetsError() throws {
        let paths = shortTempPaths()
        defer { removeTemp(paths) }
        let server = echoServer(paths)
        try server.start()
        defer { server.stop() }
        let fd = try rawConnect(paths)
        defer { Darwin.close(fd) }
        _ = write(fd, "nope\n", 5)
        let line = try #require(rawReadLine(fd))
        let response = try JSONDecoder().decode(MCPWireResponse.self, from: Data(line.utf8))
        #expect(response == MCPWireResponse(id: "", text: "Bad request.", isError: true))
    }

    @Test func clientNotListening() {
        let paths = shortTempPaths()
        #expect(throws: MCPSocketError.notListening) { try MCPSocketClient.connect(paths: paths) }
    }

    @Test func longPathFailsClearly() {
        let paths = MCPSocketPaths(folder: URL(fileURLWithPath: "/tmp/" + String(repeating: "x", count: 120), isDirectory: true))
        #expect(throws: MCPSocketError.pathTooLong) { try MCPSocketClient.connect(paths: paths) }
        #expect(throws: MCPSocketError.pathTooLong) { try echoServer(paths).start() }
        try? FileManager.default.removeItem(at: paths.folder)
    }

    @Test func stopRemovesSocket() throws {
        let paths = shortTempPaths()
        defer { removeTemp(paths) }
        let server = echoServer(paths)
        try server.start()
        #expect(FileManager.default.fileExists(atPath: paths.socket.path))
        server.stop()
        #expect(!FileManager.default.fileExists(atPath: paths.socket.path))
    }

    @Test func sendAfterCloseIsNotSent() async throws {
        let paths = shortTempPaths()
        defer { removeTemp(paths) }
        let server = echoServer(paths)
        try server.start()
        defer { server.stop() }
        let client = try MCPSocketClient.connect(paths: paths)
        client.close()
        await #expect(throws: MCPSocketError.notSent) { try await client.send(request()) }
    }

    @Test func writtenThenClosedIsClosed() async throws {
        let paths = shortTempPaths()
        defer { removeTemp(paths) }
        let raw = try RawServer(paths: paths)
        defer { raw.stop() }
        let client = try MCPSocketClient.connect(paths: paths)
        defer { client.close() }
        await #expect(throws: MCPSocketError.closed) { try await client.send(request("create_note")) }
        #expect(raw.lines == 1)
    }

    @Test func longResponseIsRead() async throws {
        let paths = shortTempPaths()
        defer { removeTemp(paths) }
        let big = String(repeating: "a", count: 5 * 1024 * 1024)
        let server = MCPSocketServer(paths: paths) { r in MCPWireResponse(id: r.id, text: big, isError: false) }
        try server.start()
        defer { server.stop() }
        let client = try MCPSocketClient.connect(paths: paths)
        defer { client.close() }
        #expect(try await client.send(request()).text.utf8.count == big.utf8.count)
    }

    @Test func secondServerIsRefusedWhileFirstAnswers() async throws {
        let paths = shortTempPaths()
        defer { removeTemp(paths) }
        let first = echoServer(paths)
        try first.start()
        defer { first.stop() }
        let second = MCPSocketServer(paths: paths) { r in MCPWireResponse(id: r.id, text: "second", isError: false) }
        #expect(throws: MCPSocketError.inUse) { try second.start() }
        let client = try MCPSocketClient.connect(paths: paths)
        defer { client.close() }
        #expect(try await client.send(request()).text == "ask")
    }

    @Test func stopKeepsAReplacedSocketFile() throws {
        let paths = shortTempPaths()
        defer { removeTemp(paths) }
        let first = echoServer(paths)
        try first.start()
        try FileManager.default.removeItem(at: paths.socket)
        try Data("other".utf8).write(to: paths.socket)
        first.stop()
        #expect(FileManager.default.fileExists(atPath: paths.socket.path))
    }

    @Test func standardPathIsUnderAppSupport() {
        #expect(MCPSocketPaths.standard().socket.path.hasSuffix("/BugVoice/MCP/bugvoice.sock"))
    }

    @Test func lineBufferSplitsAndLimits() {
        var b = MCPLineBuffer(limit: 8)
        #expect(b.append(Array("ab\ncd".utf8)) == [Data("ab".utf8)])
        #expect(b.append(Array("e\n".utf8)) == [Data("cde".utf8)])
        #expect(b.append(Array("123456789".utf8)) == nil)
    }
}

final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    func set(_ v: Bool) { lock.lock(); _value = v; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return _value }
}

func expectClosedOrNotSent(_ body: () async throws -> MCPWireResponse, sourceLocation: SourceLocation = #_sourceLocation) async {
    do {
        _ = try await body()
        Issue.record("no error", sourceLocation: sourceLocation)
    } catch let error as MCPSocketError {
        #expect(error == .closed || error == .notSent, sourceLocation: sourceLocation)
    } catch {
        Issue.record("unexpected \(error)", sourceLocation: sourceLocation)
    }
}

/// Accepts connections, reads one line from each, counts it and closes without answering.
final class RawServer: @unchecked Sendable {
    private let fd: Int32
    private let lock = NSLock()
    private var count = 0
    private var stopped = false

    init(paths: MCPSocketPaths) throws {
        try FileManager.default.createDirectory(at: paths.folder, withIntermediateDirectories: true)
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = try MCPSocketAddress.make(paths.socket.path)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(fd, 8) == 0 else { throw MCPSocketError.notListening }
        Thread { [self] in loop() }.start()
    }

    var lines: Int { lock.withLock { count } }

    func stop() {
        lock.withLock { stopped = true }
    }

    private func loop() {
        while !lock.withLock({ stopped }) {
            var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard poll(&p, 1, 50) > 0 else { continue }
            let c = accept(fd, nil, nil)
            guard c >= 0 else { continue }
            if rawReadLine(c) != nil { lock.withLock { count += 1 } }
            Darwin.close(c)
        }
        Darwin.close(fd)
    }
}
