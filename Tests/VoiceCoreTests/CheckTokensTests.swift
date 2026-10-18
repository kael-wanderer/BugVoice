import Foundation
import Testing

struct CheckTokensTests {
    @Test func checkTokensPasses() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["Scripts/check-tokens.sh"]
        process.currentDirectoryURL = packageRoot
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}
