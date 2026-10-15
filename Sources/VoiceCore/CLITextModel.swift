import Foundation

/// Argument lists measured on the maintainer's Mac (claude 2.1.300,
/// codex 0.162.1, pi 0.85.1) and taken from BugMind's `local_agent.rs`.
/// The prompt is never an argument.
public enum CLIArguments {
    /// Tools a one-shot text answer never needs. Variadic flag: keep it last.
    /// Do not add names without re-measuring: BugMind found that unknown
    /// names can void the whole list.
    public static let claudeDeniedTools = [
        "Bash", "Edit", "Write", "NotebookEdit", "WebFetch", "Read", "Glob", "Grep",
        "Agent", "Workflow", "Task", "WebSearch", "SendMessage", "ScheduleWakeup",
        "CronCreate", "ListAgents", "ReportFindings", "ShareOnboardingGuide", "Skill", "ToolSearch",
    ]

    public static func efforts(for tool: CLITool) -> [String] {
        switch tool {
        case .claude: ["low", "medium", "high", "xhigh", "max"]
        case .codex: ["minimal", "low", "medium", "high"]
        case .pi: ["off", "minimal", "low", "medium", "high", "xhigh", "max"]
        }
    }

    public static func answerFile(in directory: URL) -> URL {
        directory.appendingPathComponent("answer.txt")
    }

    /// Nil for empty values and anything a CLI would read as a flag.
    static func safe(_ value: String) -> String? {
        let text = value.trimmingCharacters(in: .whitespaces)
        return text.isEmpty || text.hasPrefix("-") ? nil : text
    }

    public static func arguments(for tool: CLITool, model: String, effort: String, workingDirectory: URL) -> [String] {
        let model = safe(model)
        let effort = safe(effort).flatMap { efforts(for: tool).contains($0) ? $0 : nil }
        switch tool {
        case .claude:
            var a = ["-p", "--output-format", "json", "--restricted", "--strict-mcp-config", "--no-session-persistence"]
            if let model { a += ["--model", model] }
            if let effort { a += ["--effort", effort] }
            return a + ["--disallowed-tools"] + claudeDeniedTools
        case .codex:
            var a = [
                "exec", "-s", "read-only", "--skip-git-repo-check", "--ephemeral", "--ignore-user-config", "--ignore-rules",
                "-C", workingDirectory.path, "--output-last-message", answerFile(in: workingDirectory).path,
            ]
            if let model { a += ["-m", model] }
            if let effort { a += ["-c", "model_reasoning_effort=\"\(effort)\""] }
            a.append("-")
            return a
        case .pi:
            var a = ["-ne", "-nt", "--no-session", "--mode", "json"]
            if let model { a += ["--model", model] }
            if let effort { a += ["--thinking", effort] }
            a.append("-p")
            return a
        }
    }
}

public enum CLIOutputError: Error, Equatable, LocalizedError {
    case noAnswer(CLITool, detail: String)
    case signedOut(CLITool)
    case toolFailed(CLITool)

    public var errorDescription: String? {
        switch self {
        case .noAnswer(let tool, let detail):
            detail.isEmpty ? "\(tool.rawValue) did not return an answer." : "\(tool.rawValue) did not return an answer. \(detail)"
        case .signedOut(let tool): "\(tool.rawValue) is signed out. Run \(tool.rawValue) in Terminal to sign in."
        case .toolFailed(let tool): "\(tool.rawValue) could not answer."
        }
    }
}

public enum CLIOutput {
    /// The answer of a process that exited 0. Sign-in wording is looked for
    /// only when there is no answer, since a summary may contain it too.
    public static func answer(tool: CLITool, result: ProcessResult, codexAnswer: String?) throws -> String {
        if result.exitCode == 0, let text = try parsed(tool: tool, stdout: result.stdout, codexAnswer: codexAnswer) {
            return text
        }
        let said = (result.stdout + " " + result.stderr).lowercased()
        if ["/login", "not logged in", "please log in", "codex login", "unauthorized"].contains(where: said.contains) {
            throw CLIOutputError.signedOut(tool)
        }
        var detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if detail.isEmpty, tool == .pi { detail = piError(result.stdout) ?? "" }
        throw CLIOutputError.noAnswer(tool, detail: String(detail.suffix(300)))
    }

    /// Pi reports a provider failure as an assistant message with
    /// `stopReason: "error"` on stdout.
    private static func piError(_ stdout: String) -> String? {
        var found: String?
        for line in stdout.split(whereSeparator: \.isNewline) {
            guard let event = json(String(line)), let message = event["message"] as? [String: Any],
                  message["role"] as? String == "assistant", message["stopReason"] as? String == "error"
            else { continue }
            found = nonEmpty(message["errorMessage"] as? String) ?? found
        }
        return found
    }

    private static func parsed(tool: CLITool, stdout: String, codexAnswer: String?) throws -> String? {
        switch tool {
        case .claude:
            guard let object = json(stdout) else { return nil }
            if object["is_error"] as? Bool == true { throw CLIOutputError.toolFailed(.claude) }
            return nonEmpty(object["result"] as? String)
        case .codex:
            return nonEmpty(codexAnswer)
        case .pi:
            var answer: String?
            for line in stdout.split(whereSeparator: \.isNewline) {
                guard let event = json(String(line)), let message = event["message"] as? [String: Any],
                      message["role"] as? String == "assistant", message["stopReason"] as? String != "error"
                else { continue }
                let parts = (message["content"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }
                if let text = nonEmpty(parts.joined()) { answer = text }
            }
            return answer
        }
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    static func json(_ text: String) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(text.trimmingCharacters(in: .whitespacesAndNewlines).utf8))) as? [String: Any]
    }
}

/// One text answer from a coding CLI, run in a fresh temporary folder that
/// is removed afterwards.
public struct CLITextModel: TextModel {
    public var tool: CLITool
    public var executable: String
    public var model: String
    public var effort: String
    public var timeout: TimeInterval
    public var runner: any ProcessRunner

    public init(tool: CLITool, executable: String, model: String, effort: String, timeout: TimeInterval, runner: any ProcessRunner) {
        self.tool = tool
        self.executable = executable
        self.model = model
        self.effort = effort
        self.timeout = timeout
        self.runner = runner
    }

    public func clean(_ request: CleanupRequest) async throws -> String {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("bugvoice-cli-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let result = try await runner.run(
            executable: executable,
            arguments: CLIArguments.arguments(for: tool, model: model, effort: effort, workingDirectory: dir),
            stdin: request.system + "\n\n" + request.user,
            workingDirectory: dir,
            timeout: timeout
        )
        let codexAnswer = tool == .codex ? try? String(contentsOf: CLIArguments.answerFile(in: dir), encoding: .utf8) : nil
        return try CLIOutput.answer(tool: tool, result: result, codexAnswer: codexAnswer)
    }
}

public struct CLIInfo: Equatable, Sendable {
    public var path: String
    public var version: String

    public init(path: String, version: String) {
        self.path = path
        self.version = version
    }
}

public enum CLILocator {
    /// A Finder-launched app has a short PATH, so the user's login shell finds the tool.
    public static func locate(_ tool: CLITool, runner: any ProcessRunner) async -> CLIInfo? {
        guard let found = try? await runner.run(
            executable: "/bin/zsh", arguments: ["-lc", "command -v \(tool.rawValue)"], stdin: "", workingDirectory: nil, timeout: 10
        ), found.exitCode == 0,
            let path = found.stdout.split(whereSeparator: \.isNewline).map(String.init).last(where: { $0.hasPrefix("/") })
        else { return nil }
        let version = (try? await runner.run(executable: path, arguments: ["--version"], stdin: "", workingDirectory: nil, timeout: 10))?
            .stdout.split(whereSeparator: \.isNewline).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return CLIInfo(path: path, version: version)
    }
}
