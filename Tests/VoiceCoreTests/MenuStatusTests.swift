import Testing
@testable import VoiceCore

@Suite struct MenuStatusTests {
    func resolve(missing: [String] = [], secure: String? = nil, listening: Bool = false,
                 speech: MenuSpeechState = .ready, hotkey: Bool = true, meeting: MenuMeetingState = .idle) -> MenuStatus {
        MenuStatus.resolve(missingPermissions: missing, secureInputApp: secure, listening: listening,
                           speech: speech, hotkeyActive: hotkey, meeting: meeting)
    }
    @Test func priorityMatchesTheNativeMenu() {
        #expect(resolve(missing: ["Microphone"], secure: "1Password", listening: true) == .needsPermissions(["Microphone"]))
        #expect(resolve(secure: "1Password", listening: true) == .secureInput(app: "1Password"))
        #expect(resolve(listening: true, speech: .loading) == .listening)
        #expect(resolve(speech: .downloading(0.404), hotkey: false) == .speechDownloading(percent: 40))
        #expect(resolve(speech: .loading, hotkey: false) == .speechLoading)
        #expect(resolve(speech: .failed, hotkey: false) == .speechFailed)
        #expect(resolve(hotkey: false, meeting: .recording) == .hotkeyInactive)
        #expect(resolve(meeting: .recording) == .meetingRecording)
        #expect(resolve(meeting: .paused) == .meetingPaused)
        #expect(resolve(meeting: .transcribing) == .ready)
        #expect(resolve() == .ready)
    }
    @Test func copyAndTone() {
        #expect(MenuStatus.ready.title == "Ready to dictate")
        #expect(MenuStatus.ready.detail(hotkey: "Right Option") == "Hold Right Option to speak · release to paste")
        #expect(MenuStatus.ready.tone == .good)
        #expect(MenuStatus.meetingRecording.title == "Recording a meeting")
        #expect(MenuStatus.meetingPaused.title == "Meeting paused")
        #expect(MenuStatus.meetingRecording.detail(hotkey: "Right Option") == "Dictation still works · hold Right Option")
        #expect(MenuStatus.meetingRecording.tone == .recording)
        #expect(MenuStatus.listening.title == "Listening…")
        #expect(MenuStatus.listening.tone == .recording)
        #expect(MenuStatus.listening.detail(hotkey: "x") == nil)
        #expect(MenuStatus.secureInput(app: "1Password").title == "Secure input is on")
        #expect(MenuStatus.secureInput(app: "1Password").detail(hotkey: "x") == "1Password · hotkey paused")
        #expect(MenuStatus.speechDownloading(percent: 40).title == "Speech model downloading")
        #expect(MenuStatus.speechDownloading(percent: 40).detail(hotkey: "x") == "40%")
        #expect(MenuStatus.speechLoading.title == "Speech model loading")
        #expect(MenuStatus.speechFailed.title == "Speech model failed to load")
        #expect(MenuStatus.hotkeyInactive.title == "Hotkey not active")
        #expect(MenuStatus.hotkeyInactive.tone == .warning)
    }
    @Test func permissionsDetailListsWhatIsOff() {
        #expect(MenuStatus.needsPermissions(["Microphone"]).title == "Needs permissions")
        #expect(MenuStatus.needsPermissions(["Microphone"]).detail(hotkey: "x") == "Microphone is off")
        #expect(MenuStatus.needsPermissions(["Microphone", "Accessibility"]).detail(hotkey: "x") == "Microphone and Accessibility are off")
        #expect(MenuStatus.needsPermissions(["Microphone", "Accessibility", "Input Monitoring"]).detail(hotkey: "x")
                == "Microphone, Accessibility and Input Monitoring are off")
        #expect(MenuStatus.needsPermissions([]).detail(hotkey: "x") == nil)
    }
    @Test func actions() {
        #expect(MenuStatus.needsPermissions(["Microphone"]).action == .fixPermissions)
        #expect(MenuStatus.needsPermissions(["Microphone"]).actionTitle == "Fix…")
        #expect(MenuStatus.speechFailed.action == .retrySpeech)
        #expect(MenuStatus.speechFailed.actionTitle == "Retry")
        #expect(MenuStatus.hotkeyInactive.action == .fixHotkey)
        #expect(MenuStatus.secureInput(app: "a").action == nil)
        #expect(MenuStatus.ready.actionTitle == nil)
    }
}
