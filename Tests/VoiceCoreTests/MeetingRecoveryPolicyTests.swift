import Foundation
import Testing
@testable import VoiceCore

struct MeetingRecoveryPolicyTests {
    @Test func oldSettingsDecodeWithMeetingDefaultsAndCurrentValuesRoundTrip() throws {
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"historyRetention":"forever"}"#.utf8))
        #expect(old.meetings.deleteAfter == .never)
        #expect(old.meetings.generationContextTokens == 8_192)
        #expect(old.meetings.generationOutputTokens == 2_048)

        var current = MeetingSettings()
        current.deleteAfter = .days90
        current.generationContextTokens = 16_384
        current.generationOutputTokens = 4_096
        let decoded = try JSONDecoder().decode(MeetingSettings.self, from: JSONEncoder().encode(current))
        #expect(decoded == current)
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
