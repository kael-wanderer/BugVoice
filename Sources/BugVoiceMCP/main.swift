import Foundation
import MCPKit

// bugvoice-mcp: the MCP stdio server agents start. It lives in
// BugVoice.app/Contents/MacOS and forwards tool calls to the running app.
// Only protocol lines go to stdout; diagnostics (never content) go to stderr.

let executable = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath()
let appBundle = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

func bundleVersion(_ bundle: URL) -> String {
    let plist = bundle.appendingPathComponent("Contents/Info.plist")
    guard let data = try? Data(contentsOf: plist),
          let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
          let version = info["CFBundleShortVersionString"] as? String
    else { return "0" }
    return version
}

func diagnose(_ message: String) {
    FileHandle.standardError.write(Data("bugvoice-mcp: \(message)\n".utf8))
}

final class StandardOutput: @unchecked Sendable {
    private let lock = NSLock()

    func write(_ data: Data) {
        lock.withLock { FileHandle.standardOutput.write(data) }
    }
}

let stdout = StandardOutput()
let bridge = MCPBridge(
    paths: .standard(),
    appVersion: bundleVersion(appBundle),
    launchApp: {
        diagnose("BugVoice is not running; opening it in the background.")
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-g", "-a", appBundle.path]
        open.standardOutput = FileHandle.nullDevice
        open.standardError = FileHandle.standardError
        do { try open.run() } catch { diagnose("Could not open BugVoice.") }
    },
    output: { stdout.write($0) }
)

// Requests run concurrently so a ping is answered while an ask is still running.
// At end of input, unfinished calls complete before the process exits.
await withTaskGroup(of: Void.self) { group in
    while let line = readLine(strippingNewline: true) {
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
        group.addTask { await bridge.handle(line: Data(line.utf8)) }
    }
}
exit(0)
