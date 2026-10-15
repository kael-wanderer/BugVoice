import Foundation
import Testing
@testable import VoiceCore

struct ProcessRunnerTests {
    let runner = FoundationProcessRunner()

    @Test func stdinReachesTheProcess() async throws {
        let r = try await runner.run(executable: "/bin/cat", arguments: [], stdin: "hello\nworld", workingDirectory: nil, timeout: 5)
        #expect(r == ProcessResult(exitCode: 0, stdout: "hello\nworld", stderr: ""))
    }

    @Test func exitCodeAndStderr() async throws {
        let r = try await runner.run(executable: "/bin/sh", arguments: ["-c", "echo oops >&2; exit 3"], stdin: "", workingDirectory: nil, timeout: 5)
        #expect(r.exitCode == 3)
        #expect(r.stderr == "oops\n")
    }

    @Test func workingDirectoryIsUsed() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bv-run-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let r = try await runner.run(executable: "/bin/pwd", arguments: ["-P"], stdin: "", workingDirectory: dir, timeout: 5)
        #expect(r.stdout.trimmingCharacters(in: .newlines).hasSuffix(dir.lastPathComponent))
    }

    @Test func largeOutputDoesNotDeadlock() async throws {
        let r = try await runner.run(executable: "/bin/sh", arguments: ["-c", "head -c 200000 /dev/zero | tr '\\0' a"], stdin: "", workingDirectory: nil, timeout: 10)
        #expect(r.stdout.count == 200_000)
    }

    @Test func timeoutStopsTheProcess() async {
        let start = Date()
        await #expect(throws: ProcessRunnerError.timedOut) {
            try await runner.run(executable: "/bin/sleep", arguments: ["30"], stdin: "", workingDirectory: nil, timeout: 0.5)
        }
        #expect(Date().timeIntervalSince(start) < 5)
    }

    @Test func cancellationStopsTheProcess() async {
        let start = Date()
        let task = Task { try await runner.run(executable: "/bin/sleep", arguments: ["30"], stdin: "", workingDirectory: nil, timeout: 60) }
        try? await Task.sleep(for: .milliseconds(300))
        task.cancel()
        let result = await task.result
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(Date().timeIntervalSince(start) < 5)
    }

    @Test func missingExecutableFailsToLaunch() async {
        await #expect(throws: ProcessRunnerError.self) {
            try await runner.run(executable: "/no/such/tool", arguments: [], stdin: "", workingDirectory: nil, timeout: 5)
        }
    }
}
