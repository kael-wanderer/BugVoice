import Darwin
import Foundation
import VoiceCore

/// Where the app listens for bridges. Dev and installed builds share it.
public struct MCPSocketPaths: Sendable {
    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    public var socket: URL { folder.appendingPathComponent("bugvoice.sock") }

    public static func standard() -> MCPSocketPaths {
        MCPSocketPaths(folder: AppPaths.standard().root.appendingPathComponent("MCP", isDirectory: true))
    }
}

/// Bridge to app: one JSON object per line.
public struct MCPWireRequest: Codable, Equatable, Sendable {
    public var id: String
    public var tool: String
    public var arguments: JSONValue?
    /// `clientInfo.name` from the agent's `initialize`.
    public var client: String

    public init(id: String, tool: String, arguments: JSONValue?, client: String) {
        self.id = id
        self.tool = tool
        self.arguments = arguments
        self.client = client
    }
}

/// App to bridge: one JSON object per line, matched to its request by `id`.
public struct MCPWireResponse: Codable, Equatable, Sendable {
    public var id: String
    public var text: String
    public var isError: Bool

    public init(id: String, text: String, isError: Bool) {
        self.id = id
        self.text = text
        self.isError = isError
    }
}

public enum MCPSocketError: Error, Equatable {
    case notListening
    /// The connection closed after the request was fully written: the app may have run it.
    case closed
    /// The request was not fully written before the connection failed: the app never ran it.
    case notSent
    case pathTooLong
    /// Another process already answers on the socket path.
    case inUse
}

enum MCPWire {
    /// Longest request line the app accepts.
    static let maxLine = 4 * 1024 * 1024
    /// Longest response line the bridge accepts. The app caps reply text well
    /// below this; JSON escaping can still grow it several times.
    static let maxResponseLine = 32 * 1024 * 1024

    static func line<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = (try? encoder.encode(value)) ?? Data()
        data.append(0x0A)
        return data
    }

    /// Writes every byte, retrying short writes. False when the peer is gone.
    static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw in
            guard var p = raw.baseAddress else { return true }
            var left = raw.count
            while left > 0 {
                let n = Darwin.write(fd, p, left)
                if n < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                p += n
                left -= n
            }
            return true
        }
    }

    /// Writing to a closed socket must fail with EPIPE, not kill the process.
    static func noSigPipe(_ fd: Int32) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }
}

enum MCPSocketAddress {
    /// `sun_path` holds 104 bytes including the terminating zero.
    static func make(_ path: String) throws -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { throw MCPSocketError.pathTooLong }
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes) }
        return addr
    }
}

/// Splits a byte stream into lines without the newline. Nil once an unfinished line passes `limit`.
struct MCPLineBuffer {
    let limit: Int
    private var pending: [UInt8] = []

    init(limit: Int) {
        self.limit = limit
    }

    mutating func append(_ chunk: [UInt8]) -> [Data]? {
        var lines: [Data] = []
        var start = 0
        for i in chunk.indices where chunk[i] == 0x0A {
            pending.append(contentsOf: chunk[start..<i])
            guard pending.count <= limit else { return nil }
            lines.append(Data(pending))
            pending.removeAll(keepingCapacity: true)
            start = i + 1
        }
        pending.append(contentsOf: chunk[start...])
        guard pending.count <= limit else { return nil }
        return lines
    }
}
