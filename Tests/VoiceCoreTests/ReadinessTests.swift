import Testing
@testable import VoiceCore

@Suite struct ReadinessTests {
    func rows(missing: [String] = [], hotkey: Bool = true, speech: MenuSpeechState = .ready,
              onDevice: String? = "large-v3 turbo", server: String? = nil,
              cleanup: CleanupCheck = .reachable(name: "Qwen")) -> [ReadinessRow] {
        Readiness.rows(missingPermissions: missing, hotkeyActive: hotkey, hotkey: "Right Control",
                       speech: speech, onDeviceModel: onDevice, serverURL: server, cleanup: cleanup)
    }

    @Test func allGoodIsReady() {
        let r = rows()
        #expect(r.map(\.kind) == [.permissions, .hotkey, .speech, .cleanup])
        #expect(r.map(\.tone) == [.ok, .ok, .ok, .ok])
        #expect(r.map(\.detail) == [
            "Microphone, Accessibility and Input Monitoring are on",
            "Hold Right Control to speak",
            "large-v3 turbo on this Mac",
            "Qwen, server reachable",
        ])
        #expect(Readiness.isReady(r))
        #expect(Readiness.summary(r) == "Ready to dictate")
        #expect(r.allSatisfy { $0.action == nil })
    }

    @Test func missingPermissionsNameEach() {
        #expect(rows(missing: ["Accessibility"])[0].detail == "Accessibility is off")
        let two = rows(missing: ["Microphone", "Accessibility", "Input Monitoring"])[0]
        #expect(two.detail == "Microphone, Accessibility and Input Monitoring are off")
        #expect(two.tone == .problem)
        #expect(two.action == .openPermissions)
        #expect(two.actionTitle == "Open permissions")
    }

    @Test func inactiveHotkeyOffersRetry() {
        let row = rows(hotkey: false)[1]
        #expect(row.detail == "Right Control is not being watched")
        #expect(row.tone == .problem)
        #expect(row.action == .retryHotkey)
    }

    @Test func speechStates() {
        #expect(rows(speech: .downloading(0.404))[2].detail == "Downloading large-v3 turbo, 40%")
        #expect(rows(speech: .downloading(0.404))[2].tone == .waiting)
        #expect(rows(speech: .loading)[2].tone == .waiting)
        let failed = rows(speech: .failed)[2]
        #expect(failed.detail == "large-v3 turbo failed to load")
        #expect(failed.action == .retrySpeech)
        let server = rows(speech: .failed, onDevice: nil, server: "http://localhost:9000")[2]
        #expect(server.detail == "Speech server at http://localhost:9000")
        #expect(server.tone == .ok)
    }

    @Test func cleanupStates() {
        let off = rows(cleanup: .off)
        #expect(off[3].tone == .off)
        #expect(off[3].action == .openModels)
        #expect(Readiness.isReady(off))
        let unchecked = rows(cleanup: .unchecked(name: "Qwen"))[3]
        #expect(unchecked.detail == "Qwen, not checked yet")
        #expect(unchecked.action == .checkCleanup)
        let failed = rows(cleanup: .failed(name: "Qwen", message: "The key was refused."))[3]
        #expect(failed.detail == "Qwen: The key was refused.")
        #expect(failed.actionTitle == "Check again")
        #expect(rows(cleanup: .local(name: "Apple Intelligence"))[3].tone == .ok)
        #expect(rows(cleanup: .unavailable("Codex was not found on this Mac."))[3].action == .openModels)
    }

    @Test func summaryCountsProblemsAndWaiting() {
        #expect(Readiness.summary(rows(speech: .loading, cleanup: .unchecked(name: "Qwen"))) == "Getting ready")
        #expect(Readiness.summary(rows(hotkey: false)) == "1 item needs attention")
        #expect(Readiness.summary(rows(missing: ["Microphone"], hotkey: false)) == "2 items need attention")
        #expect(!Readiness.isReady(rows(speech: .loading)))
    }
}
