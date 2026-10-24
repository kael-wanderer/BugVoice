import Foundation
import Testing
@testable import VoiceCore

struct SpeechChunkerTests {
let p = SpeechChunker.Parameters(pause: 0.5, shortestPart: 4, longestPart: 25)

@Test func cutsInsidePause() {
    let audio = tone(seconds: 5, amplitude: 0.1) + silence(seconds: 1) + tone(seconds: 3, amplitude: 0.1)
    let cuts = SpeechChunker.cuts(in: audio, parameters: p)
    #expect(cuts.count == 1)
    #expect((5 * 16_000 ... 6 * 16_000).contains(cuts[0].sample))
    #expect(cuts[0].decidedAt == 5 * 16_000 + 8_000)   // pause start + 0.5 s
    #expect(cuts[0].sample == 5 * 16_000 + 3_840)      // pause start + 12 frames
}
@Test func pauseBeforeShortestPartGivesNoCut() {
    let audio = tone(seconds: 2, amplitude: 0.1) + silence(seconds: 1) + tone(seconds: 2, amplitude: 0.1)
    #expect(SpeechChunker.cuts(in: audio, parameters: p).isEmpty)
}
@Test func shortPauseGivesNoCut() {
    let audio = tone(seconds: 5, amplitude: 0.1) + silence(seconds: 0.3) + tone(seconds: 3, amplitude: 0.1)
    #expect(SpeechChunker.cuts(in: audio, parameters: p).isEmpty)
}
@Test func noPauseNoCut() { #expect(SpeechChunker.cuts(in: tone(seconds: 20, amplitude: 0.1), parameters: p).isEmpty) }
@Test func silenceOnlyNeverCuts() { #expect(SpeechChunker.cuts(in: silence(seconds: 40), parameters: p).isEmpty) }
@Test func forcedCutAtQuietestWindow() {
    // 23.5 s loud, 0.2 s quiet (above floor, below 0.25 × median), 3 s loud: no real pause.
    let audio = tone(seconds: 23.5, amplitude: 0.2) + tone(seconds: 0.2, amplitude: 0.01) + tone(seconds: 3, amplitude: 0.2)
    let cuts = SpeechChunker.cuts(in: audio, parameters: p)
    #expect(cuts.count == 1)
    #expect(abs(cuts[0].sample - Int(23.6 * 16_000)) <= SpeechChunker.frameSamples * 2)
    #expect(cuts[0].decidedAt == 25 * 16_000)
}
@Test func relativeThresholdCuts() {
    // Room noise at 0.008 is above the 0.003 floor but below 0.25 × the speaker's level: still a pause.
    let audio = tone(seconds: 5, amplitude: 0.1) + tone(seconds: 1, amplitude: 0.008) + tone(seconds: 3, amplitude: 0.1)
    #expect(SpeechChunker.cuts(in: audio, parameters: p).count == 1)
}
@Test func streamingMatchesBatch() {
    let audio = tone(seconds: 5, amplitude: 0.1) + silence(seconds: 1) + tone(seconds: 6, amplitude: 0.1) + silence(seconds: 0.8) + tone(seconds: 2, amplitude: 0.1)
    var chunker = SpeechChunker(parameters: p)
    var streamed: [SpeechChunker.Cut] = []
    for start in stride(from: 0, to: audio.count, by: 1_234) {   // odd size: frames straddle appends
        streamed += chunker.append(Array(audio[start ..< min(start + 1_234, audio.count)]))
    }
    #expect(streamed == SpeechChunker.cuts(in: audio, parameters: p))
    #expect(streamed.count == 2)
}

}
