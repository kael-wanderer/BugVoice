import Foundation
import Testing
@testable import VoiceCore

/// Records the call and answers with a fixed result; can write codex's answer file.
final class FakeRunner: ProcessRunner, @unchecked Sendable {
    var result: ProcessResult
    var codexAnswer: String?
    private(set) var calls: [(executable: String, arguments: [String], stdin: String, workingDirectory: URL?, timeout: TimeInterval)] = []
    /// Keyed by `arguments + [executable]` joined with spaces.
    var results: [String: ProcessResult] = [:]

    init(result: ProcessResult = ProcessResult(exitCode: 0, stdout: "", stderr: ""), codexAnswer: String? = nil) {
        self.result = result
        self.codexAnswer = codexAnswer
    }

    func run(executable: String, arguments: [String], stdin: String, workingDirectory: URL?, timeout: TimeInterval) async throws -> ProcessResult {
        calls.append((executable, arguments, stdin, workingDirectory, timeout))
        if let codexAnswer, let i = arguments.firstIndex(of: "--output-last-message") {
            try codexAnswer.write(toFile: arguments[i + 1], atomically: true, encoding: .utf8)
        }
        return results[(arguments + [executable]).joined(separator: " ")] ?? result
    }
}

struct CLITextModelTests {
    let dir = URL(fileURLWithPath: "/tmp/bv-x")

    func answer(_ tool: CLITool, exit: Int32 = 0, stdout: String = "", stderr: String = "", codex: String? = nil) throws -> String {
        try CLIOutput.answer(tool: tool, result: ProcessResult(exitCode: exit, stdout: stdout, stderr: stderr), codexAnswer: codex)
    }

    @Test func claudeArguments() {
        let a = CLIArguments.arguments(for: .claude, model: "sonnet", effort: "high", workingDirectory: dir)
        #expect(Array(a.prefix(6)) == ["-p", "--output-format", "json", "--restricted", "--strict-mcp-config", "--no-session-persistence"])
        #expect(a[a.firstIndex(of: "--model")! + 1] == "sonnet")
        #expect(a[a.firstIndex(of: "--effort")! + 1] == "high")
        // The denylist is variadic, so it must be last.
        let deny = a.firstIndex(of: "--disallowed-tools")!
        #expect(Array(a[(deny + 1)...]) == CLIArguments.claudeDeniedTools)
        #expect(CLIArguments.claudeDeniedTools.contains("Bash"))
        #expect(CLIArguments.claudeDeniedTools.contains("ToolSearch"))
    }

    @Test func codexArguments() {
        let a = CLIArguments.arguments(for: .codex, model: "gpt-5.5", effort: "medium", workingDirectory: dir)
        #expect(Array(a.prefix(9)) == ["exec", "-s", "read-only", "--skip-git-repo-check", "--ephemeral", "--ignore-user-config", "--ignore-rules", "-C", "/tmp/bv-x"])
        #expect(a[a.firstIndex(of: "--output-last-message")! + 1] == "/tmp/bv-x/answer.txt")
        #expect(a[a.firstIndex(of: "-m")! + 1] == "gpt-5.5")
        #expect(a.contains(#"model_reasoning_effort="medium""#))
        #expect(a.last == "-")
    }

    @Test func piArguments() {
        let a = CLIArguments.arguments(for: .pi, model: "sonnet", effort: "low", workingDirectory: dir)
        #expect(a == ["-ne", "-nt", "--no-session", "--mode", "json", "--model", "sonnet", "--thinking", "low", "-p"])
    }

    @Test(arguments: CLITool.allCases)
    func flagLikeModelAndUnknownEffortAreDropped(tool: CLITool) {
        let a = CLIArguments.arguments(for: tool, model: "--dangerous", effort: "turbo", workingDirectory: dir)
        #expect(!a.contains("--dangerous"))
        #expect(!a.contains("turbo"))
        #expect(!a.contains(#"model_reasoning_effort="turbo""#))
        #expect(!a.contains("--model") && !a.contains("-m"))
    }

    @Test func claudeOutput() throws {
        #expect(try answer(.claude, stdout: #"{"result":"  Summary.  ","is_error":false}"#) == "Summary.")
        #expect(throws: CLIOutputError.toolFailed(.claude)) {
            try answer(.claude, stdout: #"{"result":"x","is_error":true}"#)
        }
    }

    @Test func codexOutput() throws {
        #expect(try answer(.codex, stdout: "log noise", codex: "Answer\n") == "Answer")
        #expect(throws: CLIOutputError.self) { try answer(.codex, exit: 1, stderr: "boom") }
    }

    @Test func nonZeroExitCannotReturnAnAnswer() {
        #expect(throws: CLIOutputError.noAnswer(.claude, detail: "boom")) {
            try answer(.claude, exit: 1, stdout: #"{"result":"Should not be used"}"#, stderr: "boom")
        }
        #expect(throws: CLIOutputError.noAnswer(.pi, detail: "boom")) {
            try answer(.pi, exit: 1, stdout: #"{"type":"message_end","message":{"role":"assistant","content":[{"type":"text","text":"Should not be used"}]}}"#, stderr: "boom")
        }
    }

    @Test func piOutputTakesLastAssistantNotThePrompt() throws {
        let stdout = """
        {"type":"message_end","message":{"role":"user","content":[{"type":"text","text":"the prompt"}]}}
        not json
        {"type":"message_end","message":{"role":"assistant","content":[{"type":"text","text":"first"}],"stopReason":"stop"}}
        {"type":"message_end","message":{"role":"assistant","content":[{"type":"text","text":"final "},{"type":"text","text":"answer"}],"stopReason":"stop"}}
        """
        #expect(try answer(.pi, stdout: stdout) == "final answer")
    }

    /// Pi reports provider failures in stdout, not stderr.
    @Test func piErrorMessageIsShown() {
        let stdout = #"{"type":"agent_end","messages":[{"role":"assistant","content":[],"stopReason":"error","errorMessage":"401: Invalid API key"}]}"#
            + "\n" + #"{"type":"message_end","message":{"role":"assistant","content":[],"stopReason":"error","errorMessage":"401: Invalid API key"}}"#
        #expect(throws: CLIOutputError.noAnswer(.pi, detail: "401: Invalid API key")) { try answer(.pi, stdout: stdout) }
    }

    /// A meeting about access control is still a summary, not a sign-in problem.
    @Test(arguments: CLITool.allCases)
    func answerMentioningLoginWordsIsKept(tool: CLITool) throws {
        let text = "Unauthorized access was found; everyone must /login again."
        let stdout: String = switch tool {
        case .claude: #"{"result":"\#(text)","is_error":false}"#
        case .codex: ""
        case .pi: #"{"type":"message_end","message":{"role":"assistant","content":[{"type":"text","text":"\#(text)"}],"stopReason":"stop"}}"#
        }
        #expect(try answer(tool, stdout: stdout, codex: tool == .codex ? text : nil) == text)
    }

    @Test func signedOutAndNoAnswerMessages() {
        #expect(throws: CLIOutputError.signedOut(.claude)) { try answer(.claude, exit: 1, stderr: "Please run /login") }
        #expect(CLIOutputError.signedOut(.codex).localizedDescription == "codex is signed out. Run codex in Terminal to sign in.")
        let long = String(repeating: "x", count: 400) + "END"
        let error = CLIOutputError.noAnswer(.pi, detail: String(long.suffix(300)))
        #expect(error.localizedDescription.hasPrefix("pi did not return an answer. "))
        #expect(error.localizedDescription.hasSuffix("END"))
        #expect(throws: CLIOutputError.noAnswer(.pi, detail: String(long.suffix(300)))) { try answer(.pi, exit: 2, stderr: long) }
    }

    @Test func cliModelSendsPromptOnStdinInAFreshFolder() async throws {
        let runner = FakeRunner(result: ProcessResult(exitCode: 0, stdout: #"{"result":"Done."}"#, stderr: ""))
        let model = CLITextModel(tool: .claude, executable: "/bin/claude", model: "", effort: "", timeout: 42, runner: runner)
        #expect(try await model.clean(CleanupRequest(system: "SYS", user: "USER")) == "Done.")
        let call = try #require(runner.calls.first)
        #expect(call.executable == "/bin/claude")
        #expect(call.stdin == "SYS\n\nUSER")
        #expect(!call.arguments.contains("SYS") && !call.arguments.contains("USER"))
        #expect(call.timeout == 42)
        let wd = try #require(call.workingDirectory)
        #expect(!FileManager.default.fileExists(atPath: wd.path)) // removed after the call
    }

    @Test func cliModelReadsCodexAnswerFile() async throws {
        let runner = FakeRunner(codexAnswer: "From file")
        let model = CLITextModel(tool: .codex, executable: "/bin/codex", model: "", effort: "", timeout: 5, runner: runner)
        #expect(try await model.clean(CleanupRequest(system: "S", user: "U")) == "From file")
    }

    @Test func locatorUsesLoginShellAndVersion() async {
        let runner = FakeRunner()
        runner.results["-lc command -v claude /bin/zsh"] = ProcessResult(exitCode: 0, stdout: "profile noise\n/Users/x/.local/bin/claude\n", stderr: "")
        runner.results["--version /Users/x/.local/bin/claude"] = ProcessResult(exitCode: 0, stdout: "2.1.300 (Claude Code)\n", stderr: "")
        #expect(await CLILocator.locate(.claude, runner: runner) == CLIInfo(path: "/Users/x/.local/bin/claude", version: "2.1.300 (Claude Code)"))
        runner.results["-lc command -v pi /bin/zsh"] = ProcessResult(exitCode: 1, stdout: "", stderr: "")
        #expect(await CLILocator.locate(.pi, runner: runner) == nil)
    }
}
