import Foundation
import Testing
@testable import VoiceCore

struct MeetingJournalTests {
    @Test func pcmJournalIsSignedInt16LittleEndianWithoutHeader() {
        let data = MeetingPCMJournal.encode(AudioClip(samples: [0, 1, -1]))
        #expect(data.count == 6)
        #expect(Array(data) == [0, 0, 255, 127, 0, 128])
    }

    @Test func recoveryClampsToCommittedBytesAndDropsPartialSample() {
        let bytes = Data([0, 0, 1, 2, 3, 4, 5])
        let recovered = MeetingPCMJournal.recover(bytes, committedByteCount: 5)
        #expect(recovered.committedData == Data([0, 0, 1, 2]))
        #expect(recovered.sampleCount == 2)
    }

    @Test func checkpointStoresIndependentProgressForEachTrack() throws {
        let checkpoint = MeetingCheckpoint(tracks: [
            .init(track: .mic, committedByteCount: 8, sampleCount: 4, startOffset: 0, endOffset: 0.00025),
            .init(track: .system, committedByteCount: 20, sampleCount: 10, startOffset: 0, endOffset: 0.000625)
        ])
        let decoded = try JSONDecoder().decode(MeetingCheckpoint.self, from: JSONEncoder().encode(checkpoint))
        #expect(decoded.track(.mic)?.committedByteCount == 8)
        #expect(decoded.track(.system)?.sampleCount == 10)
    }

    @Test func retentionKeepsDefaultAndMeetingBudgetsIndependent() throws {
        let settings = MeetingSettings()
        #expect(settings.deleteAfter == .never)
        #expect(settings.generationContextTokens == 8_192)
        #expect(settings.generationOutputTokens == 2_048)

        let oldSettings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"hotkey":"fn"}"#.utf8))
        #expect(oldSettings.meetings == MeetingSettings())
    }

    @Test func retentionExpiresReadyMeetingsAtBoundaryOnly() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let cutoff = now.addingTimeInterval(-30 * 86_400)
        let exact = MeetingManifest(startedAt: cutoff, endedAt: cutoff, state: .ready)
        let oneSecondNewer = MeetingManifest(startedAt: cutoff.addingTimeInterval(1), endedAt: cutoff.addingTimeInterval(1), state: .ready)
        let interrupted = MeetingManifest(startedAt: .distantPast, endedAt: .distantPast, state: .interrupted)

        #expect(MeetingRetention.expired(exact, policy: .days30, now: now))
        #expect(!MeetingRetention.expired(oneSecondNewer, policy: .days30, now: now))
        #expect(!MeetingRetention.expired(interrupted, policy: .days30, now: now))
        #expect(!MeetingRetention.expired(exact, policy: .never, now: now))
    }
}
