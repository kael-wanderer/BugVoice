import Darwin
import Foundation

/// The app's end of the bridge socket. Accepts up to `maxConnections` bridges of
/// the same macOS user and answers each request line with one response line.
/// Requests on one connection run concurrently and may be answered out of order.
public final class MCPSocketServer: @unchecked Sendable {
    public typealias Handler = @Sendable (MCPWireRequest) async -> MCPWireResponse

    private let paths: MCPSocketPaths
    private let maxConnections: Int
    private let peerCheck: @Sendable (Int32) -> Bool
    private let handler: Handler
    private let queue = DispatchQueue(label: "com.kael.bugvoice.mcp.server")
    // Touched only on `queue`.
    private var listener: DispatchSourceRead?
    private var connections: [ObjectIdentifier: Connection] = [:]
    /// The socket file this server bound, so `stop` never removes another app's socket.
    private var boundFile: (device: dev_t, inode: ino_t)?

    public init(
        paths: MCPSocketPaths, maxConnections: Int = 4,
        peerCheck: @escaping @Sendable (Int32) -> Bool = MCPSocketServer.sameUser,
        handler: @escaping Handler
    ) {
        self.paths = paths
        self.maxConnections = maxConnections
        self.peerCheck = peerCheck
        self.handler = handler
    }

    /// True when the process on the other end runs as this user.
    public static func sameUser(_ fd: Int32) -> Bool {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0 else { return false }
        return uid == getuid()
    }

    public func start() throws {
        try queue.sync { try listen() }
    }

    public func stop() {
        queue.sync {
            listener?.cancel()
            listener = nil
            for connection in connections.values { connection.close() }
            connections = [:]
            if let boundFile, let current = Self.identity(paths.socket.path),
               current.device == boundFile.device, current.inode == boundFile.inode {
                unlink(paths.socket.path)
            }
            boundFile = nil
        }
    }

    private static func identity(_ path: String) -> (device: dev_t, inode: ino_t)? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return (info.st_dev, info.st_ino)
    }

    /// True when a process accepts connections at `path`.
    private static func answers(_ path: String) -> Bool {
        guard var addr = try? MCPSocketAddress.make(path) else { return false }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        return result == 0
    }

    private func listen() throws {
        guard listener == nil else { return }
        let path = paths.socket.path
        var addr = try MCPSocketAddress.make(path)
        try FileManager.default.createDirectory(
            at: paths.folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard chmod(paths.folder.path, 0o700) == 0 else { throw Self.posixError() }
        // Dev and installed builds share the path: never take it from a live app.
        // A socket file left by a crash refuses connections; replace it.
        if Self.identity(path) != nil {
            guard !Self.answers(path) else { throw MCPSocketError.inUse }
            unlink(path)
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Self.posixError() }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, chmod(path, 0o600) == 0, Darwin.listen(fd, 16) == 0 else {
            let error = Self.posixError()
            Darwin.close(fd)
            unlink(path)
            throw error
        }
        boundFile = Self.identity(path)
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptPending(fd) }
        source.setCancelHandler { Darwin.close(fd) }
        listener = source
        source.resume()
    }

    private func acceptPending(_ listenFD: Int32) {
        while true {
            let fd = accept(listenFD, nil, nil)
            guard fd >= 0 else { return }
            // Accepted sockets inherit O_NONBLOCK on macOS; reads run only when data is ready.
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK)
            MCPWire.noSigPipe(fd)
            guard connections.count < maxConnections, peerCheck(fd) else {
                Darwin.close(fd)
                continue
            }
            open(fd)
        }
    }

    private func open(_ fd: Int32) {
        let connection = Connection(fd: fd)
        let key = ObjectIdentifier(connection)
        connections[key] = connection
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.readAvailable(connection) }
        source.setCancelHandler { [weak self] in
            connection.closeDescriptor()
            self?.connections.removeValue(forKey: key)
        }
        connection.attach(source)
        source.resume()
    }

    private func readAvailable(_ connection: Connection) {
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        let n = read(connection.fd, &chunk, chunk.count)
        if n < 0, errno == EINTR || errno == EAGAIN { return }
        guard n > 0, let lines = connection.buffer.append(Array(chunk[0..<n])) else {
            connection.close()
            return
        }
        for line in lines where !line.isEmpty {
            guard let request = try? JSONDecoder().decode(MCPWireRequest.self, from: line) else {
                connection.send(MCPWire.line(MCPWireResponse(id: "", text: "Bad request.", isError: true)))
                continue
            }
            let handler = handler
            Task {
                let response = await handler(request)
                connection.send(MCPWire.line(response))
            }
        }
    }

    private static func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}

/// One accepted bridge. Writes run on their own queue so a slow reader never
/// blocks the server; the descriptor closes after the last queued write.
private final class Connection: @unchecked Sendable {
    let fd: Int32
    // Touched only on the server queue.
    var buffer = MCPLineBuffer(limit: MCPWire.maxLine)

    private let lock = NSLock()
    private var closed = false
    private var source: DispatchSourceRead?
    private let writes = DispatchQueue(label: "com.kael.bugvoice.mcp.connection")

    init(fd: Int32) {
        self.fd = fd
    }

    private var isClosed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return closed
    }

    func attach(_ source: DispatchSourceRead) {
        lock.lock()
        self.source = source
        lock.unlock()
    }

    func send(_ data: Data) {
        writes.async { [self] in
            guard !isClosed else { return }
            if !MCPWire.writeAll(fd, data) { close() }
        }
    }

    /// Stops reading and writing; the descriptor itself closes in `closeDescriptor`.
    func close() {
        lock.lock()
        let wasClosed = closed
        closed = true
        let source = source
        lock.unlock()
        guard !wasClosed else { return }
        shutdown(fd, SHUT_RDWR)
        source?.cancel()
    }

    /// Called from the read source's cancel handler.
    func closeDescriptor() {
        lock.lock()
        source = nil
        lock.unlock()
        writes.async { [fd] in _ = Darwin.close(fd) }
    }
}
