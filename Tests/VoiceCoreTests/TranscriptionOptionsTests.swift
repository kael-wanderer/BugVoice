import Testing
@testable import VoiceCore

struct TranscriptionOptionsTests {
    @Test func vadChunkingDefaultsOn() {
        #expect(TranscriptionOptions().vadChunking)
        #expect(TranscriptionOptions(vadChunking: false) != TranscriptionOptions())
    }
}
