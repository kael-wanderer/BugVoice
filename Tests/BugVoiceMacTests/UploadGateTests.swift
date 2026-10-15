import Foundation
import Testing
@testable import BugVoiceMac
import VoiceCore

struct UploadGateTests {
    @Test func gatesBothAutoAndFallbackCalls() async throws {
        let probe = GateCallProbe()
        let base = EmptyThenSpeech()
        let transcriber = UploadGatedTranscriber(base: base, wait: { await probe.enter() })
        let clip = AudioClip(samples: Array(repeating: 0.3, count: 16_000))
        let result = try await MeetingChunkProcessor().process(
            id: "file-final-0-16000", track: .file, offset: 0,
            clip: clip, configuredLanguage: .en, transcriber: transcriber
        )
        #expect(await probe.calls == 2)
        #expect(result.record.attempts.count == 2)
        #expect(result.record.state == .complete)
    }
}

private actor GateCallProbe {
    var calls = 0
    func enter() { calls += 1 }
}

private actor EmptyThenSpeech: Transcriber {
    var calls = 0
    func transcribe(_ clip: AudioClip, options: TranscriptionOptions) async throws -> Transcript {
        calls += 1
        return Transcript(text: calls == 1 ? "" : "Actual speech", language: "en")
    }
}
