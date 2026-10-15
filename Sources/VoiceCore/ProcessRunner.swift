import Foundation

public struct ProcessResult: Equatable, Sendable {
    public var exitCode:Int32; public var stdout:String; public var stderr:String
    public init(exitCode:Int32,stdout:String,stderr:String){self.exitCode=exitCode;self.stdout=stdout;self.stderr=stderr}
}
public enum ProcessRunnerError:Error,Equatable,LocalizedError {
    case timedOut,launchFailed(String)
    public var errorDescription:String? { switch self { case .timedOut:"The tool took too long and was stopped."; case .launchFailed(let path):"Could not start \(path)." } }
}
public protocol ProcessRunner:Sendable {
    func run(executable:String,arguments:[String],stdin:String,workingDirectory:URL?,timeout:TimeInterval) async throws -> ProcessResult
}
public struct FoundationProcessRunner:ProcessRunner {
    public init(){}
    public func run(executable:String,arguments:[String],stdin:String,workingDirectory:URL?,timeout:TimeInterval) async throws -> ProcessResult {
        let process=Process(); process.executableURL=URL(fileURLWithPath:executable); process.arguments=arguments
        if let workingDirectory { process.currentDirectoryURL=workingDirectory }
        let input=Pipe(),output=Pipe(),errors=Pipe(); process.standardInput=input;process.standardOutput=output;process.standardError=errors
        let out=PipeCollector(output.fileHandleForReading),err=PipeCollector(errors.fileHandleForReading),handle=ProcessHandle(process)
        let exit=AsyncStream.makeStream(of:Int32.self); process.terminationHandler={ finished in exit.continuation.yield(finished.terminationStatus);exit.continuation.finish() }
        do { try process.run() } catch { throw ProcessRunnerError.launchFailed(executable) }
        let writer=input.fileHandleForWriting, data=Data(stdin.utf8); Thread.detachNewThread { try? writer.write(contentsOf:data); try? writer.close() }
        let timer=Task { try? await Task.sleep(for:.seconds(timeout));if !Task.isCancelled {handle.stop(timedOut:true)} }
        let status=await withTaskCancellationHandler { var code:Int32 = -1;for await value in exit.stream {code=value};return code } onCancel: { handle.stop(timedOut:false) }
        timer.cancel();let stdout=await out.finish(),stderr=await err.finish()
        if Task.isCancelled { throw CancellationError() };if handle.timedOut {throw ProcessRunnerError.timedOut}
        return ProcessResult(exitCode:status,stdout:stdout,stderr:stderr)
    }
}
final class ProcessHandle:@unchecked Sendable {
    private let process:Process;private let lock=NSLock();private var didTimeOut=false
    init(_ process:Process){self.process=process}
    var timedOut:Bool{lock.withLock{didTimeOut}}
    func stop(timedOut:Bool){lock.withLock{if timedOut{didTimeOut=true}};guard process.isRunning else{return};process.terminate();let pid=process.processIdentifier;DispatchQueue.global().asyncAfter(deadline:.now()+2){[process] in if process.isRunning{kill(pid,SIGKILL)}}}
}
final class PipeCollector:@unchecked Sendable {
    private let lock=NSLock();private var data=Data();private var ended=false;private let handle:FileHandle
    init(_ handle:FileHandle){self.handle=handle;handle.readabilityHandler={[weak self] h in let chunk=h.availableData;guard let self else{return};self.lock.withLock{if chunk.isEmpty{self.ended=true}else{self.data.append(chunk)}};if chunk.isEmpty{h.readabilityHandler=nil}}
    }
    func finish() async -> String { for _ in 0..<20 {if lock.withLock({ended}){break};try? await Task.sleep(for:.milliseconds(50))};handle.readabilityHandler=nil;return lock.withLock{String(decoding:data,as:UTF8.self)} }
}
