import Testing
@testable import VoiceCore

struct IncrementalSimulationTests {
@Test func noCutsMeansOnePass() async throws {
    let audio = tone(seconds: 3, amplitude: 0.1)
    let out = try await IncrementalSimulation.run(samples: audio, cuts: [], previousTextInPrompt: false) { _, _ in ("hello", 1.2) }
    #expect(out.parts == 1); #expect(out.releaseToTranscript == 1.2); #expect(out.text == "hello")
}
@Test func partsFinishedBeforeReleaseLeaveOnlyTail() async throws {
    // 20 s audio, cuts decided at 5 s and 12 s; each pass 1 s; release at 20 s.
    let audio = tone(seconds: 20, amplitude: 0.1)
    let cuts = [SpeechChunker.Cut(sample: 4 * 16_000, decidedAt: 5 * 16_000), .init(sample: 11 * 16_000, decidedAt: 12 * 16_000)]
    let out = try await IncrementalSimulation.run(samples: audio, cuts: cuts, previousTextInPrompt: false) { _, _ in ("w", 1.0) }
    #expect(out.passes == [.init(start: 5, end: 6), .init(start: 12, end: 13), .init(start: 20, end: 21)])
    #expect(out.releaseToTranscript == 1.0); #expect(out.parts == 3)
}
@Test func tailWaitsForRunningPass() async throws {
    // Cut decided at 9.5 s of a 10 s clip, pass takes 1 s: tail starts at 10.5.
    let audio = tone(seconds: 10, amplitude: 0.1)
    let cuts = [SpeechChunker.Cut(sample: 9 * 16_000, decidedAt: 9 * 16_000 + 8_000)]
    let out = try await IncrementalSimulation.run(samples: audio, cuts: cuts, previousTextInPrompt: false) { _, _ in ("w", 1.0) }
    #expect(out.passes.last == .init(start: 10.5, end: 11.5)); #expect(out.releaseToTranscript == 1.5)
}
@Test func silentTailIsSkipped() async throws {
    let audio = tone(seconds: 6, amplitude: 0.1) + silence(seconds: 2)
    let cuts = [SpeechChunker.Cut(sample: 6 * 16_000 + 4_000, decidedAt: 6 * 16_000 + 8_000)]
    let out = try await IncrementalSimulation.run(samples: audio, cuts: cuts, previousTextInPrompt: false) { _, _ in ("Thank you.", 1.0) }
    #expect(out.parts == 1); #expect(out.releaseToTranscript == 0)   // pass ended at 7.5 s, release at 8 s
}
@Test func textJoinedAndCleaned() async throws {
    // Second part returns only a hallucination: dropped from the text.
    let audio = tone(seconds: 12, amplitude: 0.1)
    let cuts = [SpeechChunker.Cut(sample: 5 * 16_000, decidedAt: 5 * 16_000), .init(sample: 9 * 16_000, decidedAt: 9 * 16_000)]
    var n = 0
    let out = try await IncrementalSimulation.run(samples: audio, cuts: cuts, previousTextInPrompt: false) { _, _ in
        n += 1; return ([" first [BLANK_AUDIO] part", "Thank you.", "last part"][n - 1], 0.5)
    }
    #expect(out.text == "first part last part")
}
@Test func previousTextOnlyWhenEnabled() async throws {
    for enabled in [true, false] {
        var prompts: [String] = []
        var n = 0
        _ = try await IncrementalSimulation.run(samples: tone(seconds: 12, amplitude: 0.1), cuts: [.init(sample: 64_000, decidedAt: 80_000), .init(sample: 128_000, decidedAt: 144_000)], previousTextInPrompt: enabled) { _, prompt in
            prompts.append(prompt)
            n += 1
            return (["a", "b", "c"][n - 1], 1.0)
        }
        #expect(prompts == (enabled ? ["", "a", "b"] : ["", "", ""]))
    }
}
@Test func partAudioBoundaries() async throws {
    var counts: [Int] = []
    _ = try await IncrementalSimulation.run(samples: tone(seconds: 12, amplitude: 0.1), cuts: [.init(sample: 64_000, decidedAt: 80_000), .init(sample: 128_000, decidedAt: 144_000)], previousTextInPrompt: false) { clip, _ in
        counts.append(clip.samples.count)
        return ("part", 1.0)
    }
    #expect(counts == [64_000, 64_000, 64_000])
}

}
