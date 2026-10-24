import Foundation

/// Replays sequential transcription passes on the recording's virtual clock.
public enum IncrementalSimulation {
    public struct Pass: Sendable, Equatable {
        public var start: Double
        public var end: Double

        public init(start: Double, end: Double) {
            self.start = start
            self.end = end
        }
    }

    public struct Outcome: Sendable, Equatable {
        public var text: String
        public var parts: Int
        public var releaseToTranscript: Double
        public var passes: [Pass]
    }

    public static func run(
        samples: [Float], cuts: [SpeechChunker.Cut], previousTextInPrompt: Bool,
        transcribe: (AudioClip, String) async throws -> (text: String, seconds: Double)
    ) async throws -> Outcome {
        let release = Double(samples.count) / AudioClip.sampleRate
        var passes: [Pass] = []
        var texts: [String] = []
        var previousText = ""
        var previousEnd = 0.0
        var previousSample = 0
        var latency = 0.0
        for cut in cuts + [.init(sample: samples.count, decidedAt: samples.count)] {
            precondition(cut.sample >= previousSample && cut.sample <= samples.count)
            precondition(cut.decidedAt >= cut.sample && cut.decidedAt <= samples.count)
            let clip = AudioClip(samples: Array(samples[previousSample..<cut.sample]))
            previousSample = cut.sample
            guard clip.rms >= 0.003 else { continue }
            let close = Double(cut.decidedAt) / AudioClip.sampleRate
            let start = max(close, previousEnd)
            let result = try await transcribe(clip, previousTextInPrompt ? previousText : "")
            previousEnd = start + result.seconds
            passes.append(Pass(start: start, end: previousEnd))
            // Keep the pass duration separate to avoid cancellation when a tail starts at release.
            latency = max(0, (start - release) + result.seconds)
            previousText = clean(result.text)
            if !previousText.isEmpty { texts.append(previousText) }
        }
        return Outcome(text: texts.joined(separator: " "), parts: passes.count,
                       releaseToTranscript: latency, passes: passes)
    }

    public static func clean(_ raw: String) -> String {
        let text = HallucinationFilter.strip(DictationPipeline.stripPlaceholders(raw))
        return HallucinationFilter.isHallucination(text) ? "" : text
    }
}
