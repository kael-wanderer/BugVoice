import Foundation

/// Finds pause boundaries using complete 20 ms frames of 16 kHz mono audio.
public struct SpeechChunker: Sendable {
    public struct Parameters: Sendable, Equatable, Hashable {
        public var pause: TimeInterval
        public var shortestPart: TimeInterval
        public var longestPart: TimeInterval
        public var silenceFactor: Float = 0.25
        public var floorRMS: Float = 0.003

        public init(pause: TimeInterval, shortestPart: TimeInterval, longestPart: TimeInterval) {
            precondition(pause >= 0.02 && shortestPart >= 0 && longestPart >= 0.2)
            self.pause = pause
            self.shortestPart = shortestPart
            self.longestPart = longestPart
        }
    }

    public struct Cut: Sendable, Equatable {
        public var sample: Int
        public var decidedAt: Int

        public init(sample: Int, decidedAt: Int) {
            self.sample = sample
            self.decidedAt = decidedAt
        }
    }

    public static let frameSamples = 320
    private let parameters: Parameters
    private var pending: [Float] = []
    private var processed = 0
    private var voicedLevels: [Float] = []
    private var history: [(end: Int, rms: Float, voiced: Bool)] = []
    private var silenceStart: Int?
    private var lastCut = 0
    private var hasVoice = false

    public init(parameters: Parameters) { self.parameters = parameters }

    public mutating func append(_ samples: [Float]) -> [Cut] {
        pending += samples
        var offset = 0
        var cuts: [Cut] = []
        let frame = Self.frameSamples
        let pauseFrames = Int(parameters.pause * 16_000) / frame
        while offset + frame <= pending.count {
            let rms = sqrt(pending[offset..<offset + frame].reduce(Float(0)) { $0 + $1 * $1 } / Float(frame))
            let start = processed
            processed += frame
            offset += frame
            let voiced = rms >= parameters.floorRMS
            if voiced {
                let insertion = voicedLevels.firstIndex(where: { $0 >= rms }) ?? voicedLevels.endIndex
                voicedLevels.insert(rms, at: insertion)
                hasVoice = true
            }
            let n = voicedLevels.count
            let median: Float = n == 0 ? 0 : (n.isMultiple(of: 2)
                ? (voicedLevels[n / 2 - 1] + voicedLevels[n / 2]) / 2 : voicedLevels[n / 2])
            history.append((processed, rms, voiced))
            history.removeAll { $0.end <= processed - 3 * 16_000 }
            if rms < max(parameters.floorRMS, parameters.silenceFactor * median) {
                if silenceStart == nil { silenceStart = start }
            } else {
                silenceStart = nil
            }
            var boundary: Int?
            if let pauseStart = silenceStart, hasVoice,
               pauseStart - lastCut >= Int(parameters.shortestPart * 16_000),
               processed - pauseStart >= pauseFrames * frame {
                boundary = pauseStart + (pauseFrames / 2) * frame
            } else if hasVoice, processed - lastCut >= Int(parameters.longestPart * 16_000) {
                let eligible = history.filter { $0.end - frame >= lastCut }
                if eligible.count >= 10 {
                    var best = Float.infinity
                    for i in 0...eligible.count - 10 {
                        let level = eligible[i..<i + 10].reduce(Float(0)) { $0 + $1.rms }
                        if level < best {
                            best = level
                            boundary = eligible[i].end - frame + 5 * frame
                        }
                    }
                }
            }
            if let boundary {
                cuts.append(Cut(sample: boundary, decidedAt: processed))
                lastCut = boundary
                hasVoice = history.contains { $0.end > boundary && $0.voiced }
                // Retained silence belongs to the new part, but cannot itself trigger another cut.
                silenceStart = nil
            }
        }
        pending.removeFirst(offset)
        return cuts
    }

    public static func cuts(in samples: [Float], parameters: Parameters) -> [Cut] {
        var chunker = Self(parameters: parameters)
        return chunker.append(samples)
    }
}
