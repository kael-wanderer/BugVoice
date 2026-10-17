import Darwin
import Foundation

/// The bridge's end of the app socket. Several requests may wait at once;
/// each response finds its request by `id`.
public final class MCPSocketClient: @unchecked Sendable {
    private let fd: Int32
    private let lock = NSLock()
    private var closed = false
    private var pending: [String: Pending] = [:]
    private var source: DispatchSourceRead?
    private let reads = DispatchQueue(label: "com.kael.bugvoice.mcp.client.read")
    private let writes = DispatchQueue(label: "com.kael.bugvoice.mcp.client.write")
    // Touched only on `reads`.
    private var buffer = MCPLineBuffer(limit: MCPWire.maxResponseLine)

    private struct Pending {
        let continuation: CheckedContinuation<MCPWireResponse, any Error>
        /// Writing began and did not fail.
        var written = false
    }

    private init(fd: Int32) {
        self.fd = fd
    }

    deinit {
        source?.cancel()
    }

    /// Throws `.notListening` when no app is listening at `paths`.
    public static func connect(paths: MCPSocketPaths) throws -> MCPSocketClient {
        var addr = try MCPSocketAddress.make(paths.socket.path)
        guard FileManager.default.fileExists(atPath: paths.socket.path) else { throw MCPSocketError.notListening }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw MCPSocketError.notListening }
        MCPWire.noSigPipe(fd)
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            Darwin.close(fd)
            throw MCPSocketError.notListening
        }
        let client = MCPSocketClient(fd: fd)
        client.startReading()
        return client
    }

    /// Throws `.notSent` when the request never fully reached the app, and
    /// `.closed` when the app closed the connection after receiving it.
    public func send(_ r: MCPWireRequest) async throws -> MCPWireResponse {
        let line = MCPWire.line(r)
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            guard !closed else {
                lock.unlock()
                continuation.resume(throwing: MCPSocketError.notSent)
                return
            }
            pending[r.id] = Pending(continuation: continuation)
            lock.unlock()
            writes.async { [self] in
                // Counted as sent from the first byte, so a close that races the
                // write never makes the bridge run a request twice.
                let stillWaiting = lock.withLock {
                    pending[r.id]?.written = true
                    return pending[r.id] != nil
                }
                guard stillWaiting else { return }
                if !MCPWire.writeAll(fd, line) {
                    lock.withLock { pending[r.id]?.written = false }
                    close()
                }
            }
        }
    }

    public func close() {
        lock.lock()
        let wasClosed = closed
        closed = true
        let waiting = pending
        pending = [:]
        let source = source
        lock.unlock()
        guard !wasClosed else { return }
        shutdown(fd, SHUT_RDWR)
        source?.cancel()
        for request in waiting.values {
            request.continuation.resume(throwing: request.written ? MCPSocketError.closed : MCPSocketError.notSent)
        }
    }

    public var isClosed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return closed
    }

    private func startReading() {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: reads)
        source.setEventHandler { [weak self] in self?.readAvailable() }
        // Close after queued writes so a write never reaches a reused descriptor.
        source.setCancelHandler { [fd, writes] in writes.async { _ = Darwin.close(fd) } }
        lock.lock()
        self.source = source
        lock.unlock()
        source.resume()
    }

    private func readAvailable() {
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        let n = read(fd, &chunk, chunk.count)
        if n < 0, errno == EINTR || errno == EAGAIN { return }
        guard n > 0, let lines = buffer.append(Array(chunk[0..<n])) else {
            close()
            return
        }
        for line in lines {
            guard let response = try? JSONDecoder().decode(MCPWireResponse.self, from: line) else { continue }
            lock.lock()
            let request = pending.removeValue(forKey: response.id)
            lock.unlock()
            request?.continuation.resume(returning: response)
        }
    }
}
