import Foundation
import Testing
@testable import BugVoiceMac
import VoiceCore

struct AudioInputProcessesTests {
    @Test func listingProcessesSucceedsAndGivesBundleIDs() throws {
        let processes = try AudioInputProcesses.current()
        #expect(processes.allSatisfy { !$0.bundleID.isEmpty && $0.pid > 0 })
    }

    @Test func nonBrowserProcessesCarryNoTitles() throws {
        let processes = try AudioInputProcesses.current()
        let nonBrowsers = processes.filter { MeetingDetector.appBundleID(for: $0.bundleID).map { MeetingDetector.browsers[$0] == nil } ?? true }
        #expect(nonBrowsers.allSatisfy { $0.windowTitles.isEmpty })
    }

    @Test func unknownAppHasNoWindowTitles() {
        #expect(AudioInputProcesses.windowTitles(bundleID: "com.bugvoice.not-running").isEmpty)
    }
}
