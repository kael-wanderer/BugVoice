import Foundation

public enum CLIArguments {
    public static let claudeDeniedTools=["Bash","Edit","Write","NotebookEdit","WebFetch","Read","Glob","Grep","Agent","Workflow","Task","WebSearch","SendMessage","ScheduleWakeup","CronCreate","ListAgents","ReportFindings","ShareOnboardingGuide","Skill","ToolSearch"]
    public static func efforts(for tool:CLITool)->[String]{switch tool{case .claude:["low","medium","high","xhigh","max"];case .codex:["minimal","low","medium","high"];case .pi:["off","minimal","low","medium","high","xhigh","max"]}}
    public static func answerFile(in directory:URL)->URL{directory.appendingPathComponent("answer.txt")}
    static func safe(_ value:String)->String?{let text=value.trimmingCharacters(in:.whitespaces);return text.isEmpty || text.hasPrefix("-") ? nil:text}
    public static func arguments(for tool:CLITool,model:String,effort:String,workingDirectory:URL)->[String]{
        let model=safe(model),effort=safe(effort).flatMap{efforts(for:tool).contains($0) ? $0:nil}
        switch tool{
        case .claude:var a=["-p","--output-format","json","--restricted","--strict-mcp-config","--no-session-persistence"];if let model{a += ["--model",model]};if let effort{a += ["--effort",effort]};return a+["--disallowed-tools"]+claudeDeniedTools
        case .codex:var a=["exec","-s","read-only","--skip-git-repo-check","--ephemeral","--ignore-user-config","--ignore-rules","-C",workingDirectory.path,"--output-last-message",answerFile(in:workingDirectory).path];if let model{a += ["-m",model]};if let effort{a += ["-c",#"model_reasoning_effort="\#(effort)""#]};a.append("-");return a
        case .pi:var a=["-ne","-nt","--no-session","--mode","json"];if let model{a += ["--model",model]};if let effort{a += ["--thinking",effort]};a.append("-p");return a
        }
    }
}
public enum CLIOutputError:Error,Equatable,LocalizedError {
    case noAnswer(CLITool,detail:String),signedOut(CLITool),toolFailed(CLITool)
    public var errorDescription:String?{switch self{case .noAnswer(let tool,let detail):detail.isEmpty ? "\(tool.rawValue) did not return an answer.":"\(tool.rawValue) did not return an answer. \(detail)";case .signedOut(let tool):"\(tool.rawValue) is signed out. Run \(tool.rawValue) in Terminal to sign in.";case .toolFailed(let tool):"\(tool.rawValue) could not answer."}}
}
public enum CLIOutput {
    public static func answer(tool:CLITool,result:ProcessResult,codexAnswer:String?) throws -> String {
        let said=(result.stdout+" "+result.stderr).lowercased()
        if ["/login","not logged in","please log in","codex login","unauthorized"].contains(where:said.contains) { throw CLIOutputError.signedOut(tool) }
        guard result.exitCode == 0 else {
            throw CLIOutputError.noAnswer(tool,detail:String(result.stderr.trimmingCharacters(in:.whitespacesAndNewlines).suffix(300)))
        }
        switch tool {
        case .claude:if let object=json(result.stdout){if object["is_error"] as? Bool == true{throw CLIOutputError.toolFailed(.claude)};if let text=(object["result"] as? String)?.trimmingCharacters(in:.whitespacesAndNewlines),!text.isEmpty{return text}}
        case .codex:if result.exitCode == 0,let text=codexAnswer?.trimmingCharacters(in:.whitespacesAndNewlines),!text.isEmpty{return text}
        case .pi:var answer:String?;for line in result.stdout.split(whereSeparator:\.isNewline){guard let event=json(String(line)),let message=event["message"] as? [String:Any],message["role"] as? String == "assistant",message["stopReason"] as? String != "error" else{continue};let text=((message["content"] as? [[String:Any]]) ?? []).compactMap{$0["text"] as? String}.joined().trimmingCharacters(in:.whitespacesAndNewlines);if !text.isEmpty{answer=text}};if let answer{return answer}
        }
        throw CLIOutputError.noAnswer(tool,detail:String(result.stderr.trimmingCharacters(in:.whitespacesAndNewlines).suffix(300)))
    }
    static func json(_ text:String)->[String:Any]?{(try? JSONSerialization.jsonObject(with:Data(text.trimmingCharacters(in:.whitespacesAndNewlines).utf8))) as? [String:Any]}
}
public struct CLITextModel:TextModel {
    public var tool:CLITool;public var executable:String;public var model:String;public var effort:String;public var timeout:TimeInterval;public var runner:any ProcessRunner
    public init(tool:CLITool,executable:String,model:String,effort:String,timeout:TimeInterval,runner:any ProcessRunner){self.tool=tool;self.executable=executable;self.model=model;self.effort=effort;self.timeout=timeout;self.runner=runner}
    public func clean(_ request:CleanupRequest) async throws -> String {let fm=FileManager.default,dir=fm.temporaryDirectory.appendingPathComponent("bugvoice-cli-\(UUID().uuidString)",isDirectory:true);try fm.createDirectory(at:dir,withIntermediateDirectories:true);defer{try? fm.removeItem(at:dir)};let result=try await runner.run(executable:executable,arguments:CLIArguments.arguments(for:tool,model:model,effort:effort,workingDirectory:dir),stdin:request.system+"\n\n"+request.user,workingDirectory:dir,timeout:timeout);let answer=tool == .codex ? try? String(contentsOf:CLIArguments.answerFile(in:dir),encoding:.utf8):nil;return try CLIOutput.answer(tool:tool,result:result,codexAnswer:answer)}
}
public struct CLIInfo:Equatable,Sendable {public var path:String;public var version:String;public init(path:String,version:String){self.path=path;self.version=version}}
public enum CLILocator {
    public static func locate(_ tool:CLITool,runner:any ProcessRunner) async -> CLIInfo? {guard let found=try? await runner.run(executable:"/bin/zsh",arguments:["-lc","command -v \(tool.rawValue)"],stdin:"",workingDirectory:nil,timeout:10),found.exitCode == 0,let path=found.stdout.split(whereSeparator:\.isNewline).map(String.init).last(where:{$0.hasPrefix("/")}) else{return nil};let version=(try? await runner.run(executable:path,arguments:["--version"],stdin:"",workingDirectory:nil,timeout:10))?.stdout.split(whereSeparator:\.isNewline).first.map{$0.trimmingCharacters(in:.whitespaces)} ?? "";return CLIInfo(path:path,version:version)}
}
