import Foundation
import VoiceCore

/// The stdio side of `bugvoice-mcp`: answers the MCP handshake and tool list
/// itself and forwards each tool call to the app over the socket.
public final class MCPBridge: @unchecked Sendable {
    public static let didNotStart = "BugVoice did not start. Open it and try again."
    public static let connectionLost = "BugVoice closed the connection. Try again."
    public static let lostAfterSending = "BugVoice closed the connection before answering. Check BugVoice before you try again."

    /// Tools that change nothing, so sending one twice is harmless.
    static let readOnly: Set<MCPTool> = [.listFolders, .listNotes, .getNote, .listMeetings, .getMeeting, .search, .ask, .getJob]

    private let paths: MCPSocketPaths
    private let appVersion: String
    private let launchApp: @Sendable () -> Void
    private let waitSeconds: Double
    private let output: @Sendable (Data) -> Void

    private let lock = NSLock()
    private var clientName = "agent"
    private var client: MCPSocketClient?
    private var launched = false

    public init(
        paths: MCPSocketPaths, appVersion: String, launchApp: @escaping @Sendable () -> Void,
        waitSeconds: Double = 20, output: @escaping @Sendable (Data) -> Void
    ) {
        self.paths = paths
        self.appVersion = appVersion
        self.launchApp = launchApp
        self.waitSeconds = waitSeconds
        self.output = output
    }

    /// One stdin line in; zero or one stdout line out.
    public func handle(line: Data) async {
        let message: JSONRPCMessage
        switch JSONRPCMessage.parse(line) {
        case .failure(let error):
            output(JSONRPCMessage(id: .null, error: error).encodedLine())
            return
        case .success(let parsed):
            message = parsed
        }
        // Responses from the client and notifications get no reply.
        guard let method = message.method, let id = message.id else { return }

        switch method {
        case "initialize":
            let name = message.params?["clientInfo"]?["name"]?.stringValue ?? ""
            lock.withLock { clientName = name.isEmpty ? "agent" : name }
            let version = MCPProtocol.negotiate(message.params?["protocolVersion"]?.stringValue)
            reply(id, MCPProtocol.initializeResult(version: version, appVersion: appVersion))
        case "ping":
            reply(id, .object([:]))
        case "tools/list":
            reply(id, MCPTools.definitions)
        case "tools/call":
            guard let name = message.params?["name"]?.stringValue else {
                output(JSONRPCMessage(
                    id: id, error: JSONRPCError(code: JSONRPCError.invalidParams, message: "Missing tool name.")
                ).encodedLine())
                return
            }
            let arguments = message.params?["arguments"]
            if case .failure(let error) = MCPTools.check(name, arguments) {
                reply(id, MCPProtocol.toolResult(text: error.message, isError: true))
                return
            }
            let (text, isError) = await forward(tool: name, arguments: arguments)
            reply(id, MCPProtocol.toolResult(text: text, isError: isError))
        default:
            output(JSONRPCMessage(
                id: id, error: JSONRPCError(code: JSONRPCError.methodNotFound, message: "Method not found: \(method).")
            ).encodedLine())
        }
    }

    private func reply(_ id: JSONValue, _ result: JSONValue) {
        output(JSONRPCMessage(id: id, result: result).encodedLine())
    }

    private func forward(tool: String, arguments: JSONValue?) async -> (String, Bool) {
        let name = lock.withLock { clientName }
        let request = MCPWireRequest(id: UUID().uuidString, tool: tool, arguments: arguments, client: name)
        // A closed connection usually means the app restarted: reconnect once. A
        // tool that changes something is resent only when the app never got it.
        let mayResend = MCPTool(rawValue: tool).map(Self.readOnly.contains) ?? false
        for _ in 0..<2 {
            guard let client = await connection() else { return (Self.didNotStart, true) }
            do {
                let response = try await client.send(request)
                return (response.text, response.isError)
            } catch {
                drop(client)
                if !mayResend, error as? MCPSocketError != .notSent { return (Self.lostAfterSending, true) }
            }
        }
        return (Self.connectionLost, true)
    }

    /// The open connection, or a new one. Launches the app once per bridge
    /// process when nothing listens, then waits up to `waitSeconds`.
    private func connection() async -> MCPSocketClient? {
        if let open = lock.withLock({ client.flatMap { $0.isClosed ? nil : $0 } }) { return open }
        if let fresh = try? MCPSocketClient.connect(paths: paths) { return keep(fresh) }

        let shouldLaunch = lock.withLock {
            defer { launched = true }
            return !launched
        }
        if shouldLaunch { launchApp() }

        let deadline = Date().addingTimeInterval(waitSeconds)
        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(250))
            if let fresh = try? MCPSocketClient.connect(paths: paths) { return keep(fresh) }
        }
        return nil
    }

    private func keep(_ fresh: MCPSocketClient) -> MCPSocketClient {
        // Another call may have connected meanwhile; keep one connection.
        let kept = lock.withLock {
            if let client, !client.isClosed { return client }
            client = fresh
            return fresh
        }
        if kept !== fresh { fresh.close() }
        return kept
    }

    private func drop(_ stale: MCPSocketClient) {
        stale.close()
        lock.withLock { if client === stale { client = nil } }
    }
}
