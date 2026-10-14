import Foundation

public enum MeetingChunkPlanner {
    public static func plan(
        sampleCount: Int,
        chunkSeconds: TimeInterval = 30,
        overlapSeconds: TimeInterval = 1,
        sampleRate: Int = MeetingPCMJournal.sampleRate
    ) -> [Range<Int>] {
        guard sampleCount > 0, sampleRate > 0, chunkSeconds > 0 else { return [] }
        let maxSamples = max(1, Int((chunkSeconds * Double(sampleRate)).rounded()))
        let requestedOverlap = max(0, Int((overlapSeconds * Double(sampleRate)).rounded()))
        let overlap = min(requestedOverlap, maxSamples - 1)
        let stride = maxSamples - overlap
        var ranges: [Range<Int>] = []
        var lowerBound = 0
        while lowerBound < sampleCount {
            let upperBound = min(sampleCount, lowerBound + maxSamples)
            ranges.append(lowerBound..<upperBound)
            lowerBound += stride
        }
        return ranges
    }
}

public enum MeetingSilenceGate {
    public static func hasSpeech(
        _ samples: [Float],
        windowSeconds: TimeInterval = 0.1,
        threshold: Float = 0.003,
        sampleRate: Int = MeetingPCMJournal.sampleRate
    ) -> Bool {
        guard !samples.isEmpty, windowSeconds > 0, sampleRate > 0 else { return false }
        let windowSize = max(1, Int((windowSeconds * Double(sampleRate)).rounded()))
        var start = 0
        while start < samples.count {
            let end = min(samples.count, start + windowSize)
            var sumSquares: Float = 0
            for index in start..<end {
                sumSquares += samples[index] * samples[index]
            }
            let count = Float(end - start)
            if (sumSquares / count).squareRoot() > threshold { return true }
            start = end
        }
        return false
    }
}

public struct MeetingChunkProcessingResult: Equatable, Sendable {
    public var record: MeetingChunkRecord
    public var segments: [MeetingSegment]

    public init(record: MeetingChunkRecord, segments: [MeetingSegment]) {
        self.record = record
        self.segments = segments
    }
}

public struct MeetingChunkProcessor: Sendable {
    public init() {}

    public func process(
        id: String,
        track: MeetingTrack,
        offset: TimeInterval,
        clip: AudioClip,
        transcriber: any Transcriber
    ) async throws -> MeetingChunkProcessingResult {
        guard MeetingSilenceGate.hasSpeech(clip.samples) else {
            return MeetingChunkProcessingResult(record: MeetingChunkRecord(
                id: id,
                track: track,
                offset: offset,
                duration: clip.duration,
                requestedLanguage: .auto,
                state: .empty
            ), segments: [])
        }

        let autoAttempt: MeetingChunkAttempt
        do {
            let transcript = try await transcriber.transcribe(
                clip,
                options: TranscriptionOptions(language: .auto, timestamps: true, priority: .meeting)
            )
            autoAttempt = makeAttempt(transcript, mode: .timestamped, requestedLanguage: .auto, clip: clip)
        } catch {
            if error is CancellationError { throw error }
            autoAttempt = MeetingChunkAttempt(
                mode: .timestamped,
                requestedLanguage: .auto,
                state: .failed,
                errorMessage: String(describing: error)
            )
        }

        if autoAttempt.state == .complete {
            return result(id: id, track: track, offset: offset, clip: clip, attempts: [autoAttempt], chosen: 0)
        }
        guard autoAttempt.state == .empty else {
            return result(id: id, track: track, offset: offset, clip: clip, attempts: [autoAttempt], chosen: nil)
        }
        // Automatic forced-language retry is only for an empty auto result;
        // nonempty hallucinations have already been classified as empty but
        // must not retry. The helper marks filtered hallucinations separately.
        guard autoAttempt.text.isEmpty else {
            return result(id: id, track: track, offset: offset, clip: clip, attempts: [autoAttempt], chosen: nil)
        }

        do {
            let transcript = try await transcriber.transcribe(
                clip,
                options: TranscriptionOptions(language: .vi, timestamps: false, priority: .meeting)
            )
            let retry = makeAttempt(transcript, mode: .forcedVAD, requestedLanguage: .vi, clip: clip)
            let attempts = [autoAttempt, retry]
            return result(
                id: id,
                track: track,
                offset: offset,
                clip: clip,
                attempts: attempts,
                chosen: retry.state == .complete ? 1 : nil
            )
        } catch {
            if error is CancellationError { throw error }
            let retry = MeetingChunkAttempt(
                mode: .forcedVAD,
                requestedLanguage: .vi,
                state: .failed,
                errorMessage: String(describing: error)
            )
            return result(id: id, track: track, offset: offset, clip: clip, attempts: [autoAttempt, retry], chosen: nil)
        }
    }

    private func makeAttempt(
        _ transcript: Transcript,
        mode: MeetingTranscriptionMode,
        requestedLanguage: SpeechLanguage,
        clip: AudioClip
    ) -> MeetingChunkAttempt {
        var text = DictationPipeline.stripPlaceholders(transcript.text)
        let placeholderStrippedSegments = transcript.segments.compactMap { segment -> TranscriptSegment? in
            let clean = DictationPipeline.stripPlaceholders(segment.text)
            guard !clean.isEmpty else { return nil }
            return TranscriptSegment(start: segment.start, end: segment.end, text: clean)
        }
        if text.isEmpty, !placeholderStrippedSegments.isEmpty {
            text = placeholderStrippedSegments.map(\.text).joined(separator: " ")
        }

        guard !text.isEmpty, !HallucinationFilter.isHallucination(text) else {
            return MeetingChunkAttempt(
                mode: mode,
                requestedLanguage: requestedLanguage,
                detectedLanguage: transcript.language,
                state: .empty,
                text: text
            )
        }

        let cleanedSegments = placeholderStrippedSegments.filter {
            !HallucinationFilter.isHallucination($0.text)
        }
        guard transcript.segments.isEmpty || !cleanedSegments.isEmpty else {
            return MeetingChunkAttempt(
                mode: mode,
                requestedLanguage: requestedLanguage,
                detectedLanguage: transcript.language,
                state: .empty,
                text: text
            )
        }
        let segments = transcript.segments.isEmpty
            ? [TranscriptSegment(start: 0, end: clip.duration, text: text)]
            : cleanedSegments
        return MeetingChunkAttempt(
            mode: mode,
            requestedLanguage: requestedLanguage,
            detectedLanguage: transcript.language,
            state: .complete,
            text: text,
            segments: segments
        )
    }

    private func result(
        id: String,
        track: MeetingTrack,
        offset: TimeInterval,
        clip: AudioClip,
        attempts: [MeetingChunkAttempt],
        chosen: Int?
    ) -> MeetingChunkProcessingResult {
        let chosenAttempt = chosen.flatMap { attempts.indices.contains($0) ? attempts[$0] : nil }
        let finalState: MeetingChunkState
        if chosenAttempt != nil {
            finalState = .complete
        } else if attempts.contains(where: { $0.state == .failed }) {
            finalState = .failed
        } else {
            finalState = .empty
        }
        let record = MeetingChunkRecord(
            id: id,
            track: track,
            offset: offset,
            duration: clip.duration,
            requestedLanguage: .auto,
            detectedLanguage: chosenAttempt?.detectedLanguage,
            state: finalState,
            errorMessage: attempts.last(where: { $0.state == .failed })?.errorMessage,
            attempts: attempts,
            chosenAttempt: chosen
        )
        let segments = chosenAttempt?.segments.map {
            MeetingSegment(start: offset + $0.start, end: offset + $0.end, text: $0.text, track: track)
        } ?? []
        return MeetingChunkProcessingResult(record: record, segments: segments)
    }
}

public enum MeetingTranscriptMerger {
    public static func merge(_ segments: [MeetingSegment], overlapWindow: TimeInterval = 2) -> [MeetingSegment] {
        let ordered = segments.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.track != $1.track { return trackOrder($0.track) < trackOrder($1.track) }
            if $0.end != $1.end { return $0.end < $1.end }
            return $0.id < $1.id
        }

        var merged: [MeetingSegment] = []
        for var segment in ordered {
            guard let previousIndex = merged.indices.reversed().first(where: {
                merged[$0].track == segment.track
                    && segment.start <= merged[$0].end + overlapWindow
            }) else {
                merged.append(segment)
                continue
            }

            let previousWords = words(merged[previousIndex].text)
            let currentWords = words(segment.text)
            let overlap = sharedBoundaryWordCount(previousWords, currentWords)
            guard overlap > 0, overlap >= 2 || overlap == currentWords.count else {
                merged.append(segment)
                continue
            }
            if overlap == currentWords.count { continue }
            let pieces = segment.text.split(whereSeparator: \.isWhitespace)
            segment.text = pieces.dropFirst(overlap).joined(separator: " ")
            if !segment.text.isEmpty { merged.append(segment) }
        }
        return merged
    }

    private static func trackOrder(_ track: MeetingTrack) -> Int {
        track == .mic ? 0 : 1
    }

    private static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map { word in
            String(word)
                .lowercased()
                .trimmingCharacters(in: .punctuationCharacters)
        }
    }

    private static func sharedBoundaryWordCount(_ previous: [String], _ current: [String]) -> Int {
        let maximum = min(previous.count, current.count)
        guard maximum > 0 else { return 0 }
        for count in stride(from: maximum, through: 1, by: -1) {
            if Array(previous.suffix(count)) == Array(current.prefix(count)) { return count }
        }
        return 0
    }
}
