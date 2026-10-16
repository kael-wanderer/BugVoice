import Foundation
import Testing
@testable import VoiceCore

struct MeetingRecoveryPolicyTests {
    @Test func oldSettingsDecodeWithMeetingDefaultsAndCurrentValuesRoundTrip() throws {
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"historyRetention":"forever"}"#.utf8))
        #expect(old.meetings.deleteAfter == .never)
        #expect(old.meetings.generationContextTokens == 8_192)
        #expect(old.meetings.generationOutputTokens == 2_048)
        #expect(old.meetings.languages == [.en, .vi])
        #expect(old.meetings.detectMeetings)
        #expect(old.meetings.mutedMeetingApps.isEmpty)
        #expect(!old.meetings.windowCollapsed)

        var current = MeetingSettings()
        current.deleteAfter = .days90
        current.generationContextTokens = 16_384
        current.generationOutputTokens = 4_096
        current.languages = [.en, .es]
        current.detectMeetings = false
        current.mutedMeetingApps = ["us.zoom.xos"]
        current.windowCollapsed = true
        let decoded = try JSONDecoder().decode(MeetingSettings.self, from: JSONEncoder().encode(current))
        #expect(decoded == current)
    }

    @Test func savedMeetingLanguagesAreNormalizedOnDecode() throws {
        let decoded = try JSONDecoder().decode(MeetingSettings.self, from: Data(#"{"languages":["auto","es","es"]}"#.utf8))
        #expect(decoded.languages == [.es])
        let none = try JSONDecoder().decode(MeetingSettings.self, from: Data(#"{"languages":[]}"#.utf8))
        #expect(none.languages == [.en, .vi])
    }

    @Test func recoveryActionsSeparateInterruptedCaptureAndPendingTranscription() {
        #expect(MeetingRecoveryPolicy.action(for: .interrupted) == .recoverCapture)
        #expect(MeetingRecoveryPolicy.action(for: .transcribing) == .retryTranscription)
        #expect(MeetingRecoveryPolicy.action(for: .recording) == .recoverCapture)
        #expect(MeetingRecoveryPolicy.action(for: .paused) == .recoverCapture)
        #expect(MeetingRecoveryPolicy.action(for: .ready) == nil)
        #expect(MeetingRecoveryPolicy.action(for: .failed) == nil)
    }
}
