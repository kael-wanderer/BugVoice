import BugVoiceMac
import Darwin
import Foundation
import Security
import VoiceCore

/// Runs the bundled llama-server for the built-in cleanup model: one process
/// at a time, bound to 127.0.0.1 with a random per-launch key, started on
/// first use and stopped after the idle time in Settings.
@MainActor
final class BuiltInServerController: BuiltInServing {
    nonisolated static let notInBuild = "The built-in model is not installed in this build."
    nonisolated static let didNotStart = "The built-in model did not start."
    /// An exit sooner than this after launch counts as "did not run".
    nonisolated static let immediateExitSeconds: TimeInterval = 3
    /// The helper could not run or quit at once: likely quarantine left on
    /// Contents/Helpers after Open Anyway.
    nonisolated static let didNotRun =
        "The built-in model did not start. If you opened BugVoice with Open Anyway, run the Terminal command from the Read Me (Way B) once."

    /// `Contents/Helpers/llama-server` in the app bundle; nil under `swift run`.
    static var bundledHelper: URL? {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/llama-server")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    private struct Running {
        let process: Process
        let modelID: String
        let endpoint: BuiltInEndpoint
        let stop: StopRequest
    }

    /// Set when BugVoice itself ends a server, so a start it cuts short is a
    /// cancellation rather than a load failure.
    private final class StopRequest {
        var requested = false
    }

    private enum StartFailure: Error {
        /// The helper quit before it answered.
        case exited
        /// No answer within the start limit.
        case timedOut
    }

    private let helper: URL?
    private let modelsDirectory: URL
    private let pidFile: URL
    private let idleMinutes: @MainActor () -> Int
    private let healthSession: URLSession

    private var running: Running?
    private var starting: (modelID: String, generation: UInt64, task: Task<BuiltInEndpoint, Error>)?
    private var generation: UInt64 = 0
    private var lastUse = Date()
    /// Cleanup requests sent and not yet answered. The idle stop waits for them.
    private var inFlight = 0
    private var idleTask: Task<Void, Never>?

    /// - Parameters:
    ///   - helper: the llama-server executable, or nil when this build has none.
    ///   - modelsDirectory: where downloaded models sit as `<fileName>`.
    ///   - pidFile: written while a server runs, so a crash leaves a trail to clean up.
    init(helper: URL?, modelsDirectory: URL, pidFile: URL, idleMinutes: @escaping @MainActor () -> Int) {
        self.helper = helper
        self.modelsDirectory = modelsDirectory
        self.pidFile = pidFile
        self.idleMinutes = idleMinutes
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2
        healthSession = URLSession(configuration: config)
    }

    /// Told the outcome of every `endpoint(for:)`: nil on success, else the error.
    /// AppModel uses it for the readiness card. Covers preload, Try it, dictation and Notes.
    var onLoadResult: ((_ modelID: String, _ error: Error?) -> Void)?

    // MARK: BuiltInServing

    func endpoint(for model: BuiltInModel) async throws -> BuiltInEndpoint {
        do {
            let endpoint = try await startOrReuse(model)
            onLoadResult?(model.id, nil)
            return endpoint
        } catch is CancellationError {
            // Stopped by BugVoice (another model, quit, delete): not a load failure.
            throw CancellationError()
        } catch {
            onLoadResult?(model.id, error)
            throw error
        }
    }

    /// The model the server runs or is starting, if any.
    var activeModelID: String? { starting?.modelID ?? running?.modelID }

    private func startOrReuse(_ model: BuiltInModel) async throws -> BuiltInEndpoint {
        lastUse = Date()
        // Callers that race share one start. A start for another model finishes first.
        while let pending = starting {
            if pending.modelID == model.id { return try await pending.task.value }
            _ = try? await pending.task.value
        }
        if let running, running.modelID == model.id, running.process.isRunning {
            return running.endpoint
        }
        stop()
        generation &+= 1
        let id = generation
        let task = Task { [weak self] () throws -> BuiltInEndpoint in
            guard let self else { throw ProviderError.unavailable(Self.didNotStart) }
            defer { if self.starting?.generation == id { self.starting = nil } }
            return try await self.launch(model)
        }
        starting = (model.id, id, task)
        return try await task.value
    }

    func beginRequest() async {
        inFlight += 1
        lastUse = Date()
    }

    func endRequest() async {
        inFlight = max(0, inFlight - 1)
        lastUse = Date()
    }

    // MARK: Lifecycle

    /// Stops the server now. On quit: SIGTERM, then SIGKILL after 2 seconds.
    func shutdown() {
        starting?.task.cancel()
        starting = nil
        idleTask?.cancel()
        idleTask = nil
        guard let running else { return removePIDFile() }
        self.running = nil
        running.stop.requested = true
        let pid = running.process.processIdentifier
        // The main thread blocks here, so ask the kernel rather than Process.
        if Self.isAlive(pid) {
            kill(pid, SIGTERM)
            if !Self.waitForExit(pid, seconds: 2) {
                kill(pid, SIGKILL)
                _ = Self.waitForExit(pid, seconds: 1)
            }
        }
        if !Self.isAlive(pid) { removePIDFile() }
        Log.app.notice("built-in server stopped on quit")
    }

    /// Stops the server if it runs, or is starting, `modelID`, so its file can
    /// be deleted. A start for that model is let finish first, then stopped.
    func release(modelID: String) async {
        while let pending = starting, pending.modelID == modelID {
            _ = try? await pending.task.value
        }
        guard running?.modelID == modelID else { return }
        stop()
        Log.app.notice("built-in server stopped to delete \(modelID, privacy: .public)")
    }

    /// Kills a server left by an earlier launch that crashed, but only when
    /// the pid still belongs to our bundled helper.
    func cleanUpStale() {
        guard let helper, let text = try? String(contentsOf: pidFile, encoding: .utf8) else { return }
        defer { removePIDFile() }
        guard let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 0,
              Self.isHelper(pid: pid, helper: helper) else { return }
        Log.app.notice("built-in server: stopping a server left by an earlier launch")
        kill(pid, SIGTERM)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            // The pid may now belong to a server this launch started.
            guard self?.running?.process.processIdentifier != pid else { return }
            if Self.isHelper(pid: pid, helper: helper) { kill(pid, SIGKILL) }
        }
    }

    // MARK: Private

    /// Ends the current server without waiting: SIGTERM, then SIGKILL after 2 seconds.
    /// The pid file goes once the process has exited (`processExited`).
    private func stop() {
        idleTask?.cancel()
        idleTask = nil
        guard let running else { return }
        self.running = nil
        running.stop.requested = true
        let process = running.process
        guard process.isRunning else {
            removePIDFile(ifHolding: process.processIdentifier)
            return
        }
        process.terminate()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }

    private func launch(_ model: BuiltInModel) async throws -> BuiltInEndpoint {
        guard let helper else { throw ProviderError.unavailable(Self.notInBuild) }
        let file = BuiltInDownloadPlan.finalURL(for: model, in: modelsDirectory)
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw ProviderError.unavailable("\(model.name) is not downloaded. Download it in Settings → Models.")
        }
        let port = try Self.freePort()
        let key = try Self.randomKey()
        guard let baseURL = URL(string: "http://127.0.0.1:\(port)") else { throw ProviderError.unavailable(Self.didNotStart) }
        let endpoint = BuiltInEndpoint(baseURL: baseURL, apiKey: key)

        let process = Process()
        process.executableURL = helper
        process.arguments = BuiltInServerArguments.make(modelPath: file.path, port: Int(port), apiKey: key)
        // The server's output can hold prompt text; it is not kept.
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] ended in
            let pid = ended.processIdentifier
            let status = ended.terminationStatus
            Task { @MainActor in self?.processExited(pid: pid, status: status) }
        }
        do {
            try process.run()
        } catch {
            // The error text can hold the helper's path: log only its domain and code.
            let ns = error as NSError
            Log.app.error("built-in server could not launch: \(ns.domain, privacy: .public) \(ns.code, privacy: .public)")
            throw ProviderError.unavailable(Self.didNotRun)
        }
        let stopRequest = StopRequest()
        running = Running(process: process, modelID: model.id, endpoint: endpoint, stop: stopRequest)
        writePIDFile(process.processIdentifier)
        Log.app.notice("built-in server starting model=\(model.id, privacy: .public)")

        let started = Date()
        do {
            try await waitForHealth(endpoint, process: process, stop: stopRequest)
        } catch is CancellationError {
            if running?.process === process { stop() }
            Log.app.notice("built-in server start cancelled")
            throw CancellationError()
        } catch StartFailure.exited {
            if running?.process === process { stop() }
            Log.app.error("built-in server exited before it was ready")
            // Quarantine kills the helper at once; a later exit is a load problem.
            let atOnce = Date().timeIntervalSince(started) < Self.immediateExitSeconds
            throw ProviderError.unavailable(atOnce ? Self.didNotRun : Self.didNotStart)
        } catch {
            if running?.process === process { stop() }
            Log.app.error("built-in server did not become healthy")
            throw ProviderError.unavailable(Self.didNotStart)
        }
        Log.app.notice("built-in server ready seconds=\(Int(Date().timeIntervalSince(started)), privacy: .public)")
        lastUse = Date()
        startIdleCheck()
        return endpoint
    }

    /// Polls `GET /health` every 100 ms for up to 60 seconds.
    /// Throws `CancellationError` when BugVoice stopped the start, and
    /// `StartFailure` when the helper quit or never answered.
    private func waitForHealth(_ endpoint: BuiltInEndpoint, process: Process, stop: StopRequest) async throws {
        var request = URLRequest(url: endpoint.baseURL.appendingPathComponent("health"))
        request.setValue("Bearer \(endpoint.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 2
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            try Task.checkCancellation()
            if stop.requested { throw CancellationError() }
            guard process.isRunning else { throw StartFailure.exited }
            if let (_, response) = try? await healthSession.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200 {
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw StartFailure.timedOut
    }

    private func processExited(pid: Int32, status: Int32) {
        // A server BugVoice stopped is gone now: its pid file can go.
        removePIDFile(ifHolding: pid)
        guard let running, running.process.processIdentifier == pid else { return }
        Log.app.notice("built-in server exited status=\(status, privacy: .public)")
        self.running = nil
        idleTask?.cancel()
        idleTask = nil
    }

    private func startIdleCheck() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self, !Task.isCancelled else { return }
                if self.running != nil, self.starting == nil,
                   BuiltInIdle.shouldStop(lastUse: self.lastUse, now: Date(), idleMinutes: self.idleMinutes(),
                                          inFlight: self.inFlight) {
                    Log.app.notice("built-in server stopped after idle")
                    self.stop()
                    return
                }
            }
        }
    }

    private func writePIDFile(_ pid: Int32) {
        do {
            try Data("\(pid)\n".utf8).write(to: pidFile, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: pidFile.path)
        } catch {
            Log.app.error("built-in server: could not write the pid file")
        }
    }

    private func removePIDFile() {
        try? FileManager.default.removeItem(at: pidFile)
    }

    /// Removes the pid file only while it still names `pid`, so a newer server's file stays.
    private func removePIDFile(ifHolding pid: Int32) {
        guard let text = try? String(contentsOf: pidFile, encoding: .utf8),
              Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) == pid else { return }
        removePIDFile()
    }

    // MARK: Helpers

    /// True while `pid` exists. Works with the main thread blocked, unlike `Process.isRunning`.
    nonisolated static func isAlive(_ pid: Int32) -> Bool {
        !(kill(pid, 0) == -1 && errno == ESRCH)
    }

    /// Polls every 50 ms until `pid` is gone; false when it is still there after `seconds`.
    nonisolated static func waitForExit(_ pid: Int32, seconds: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while isAlive(pid) {
            guard Date() < deadline else { return false }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return true
    }

    /// True when `pid` is alive and runs the executable at `helper`.
    nonisolated static func isHelper(pid: Int32, helper: URL) -> Bool {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return false }
        let path = String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            == helper.resolvingSymlinksInPath().path
    }

    /// A port the system says is free, found by binding 127.0.0.1:0.
    nonisolated static func freePort() throws -> UInt16 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ProviderError.unavailable(didNotStart) }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, length) }
        }
        guard bound == 0 else { throw ProviderError.unavailable(didNotStart) }
        let named = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        guard named == 0 else { throw ProviderError.unavailable(didNotStart) }
        let port = UInt16(bigEndian: addr.sin_port)
        guard port > 0 else { throw ProviderError.unavailable(didNotStart) }
        return port
    }

    /// 32 random bytes as hex.
    nonisolated static func randomKey() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw ProviderError.unavailable(didNotStart)
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
