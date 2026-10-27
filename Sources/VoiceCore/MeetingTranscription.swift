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

/// Tracks the next unsent complete chunk independently for each audio track.
/// Partial trailing chunks are reconsidered on the next monitor tick.
public struct MeetingLiveChunkCursor: Sendable {
    private var nextIndex: [MeetingTrack: Int] = [:]

    public init() {}

    public func nextReadyRange(
        track: MeetingTrack,
        sampleCount: Int,
        chunkSeconds: TimeInterval = 30,
        overlapSeconds: TimeInterval = 1,
        sampleRate: Int = MeetingPCMJournal.sampleRate
    ) -> Range<Int>? {
        let ranges = MeetingChunkPlanner.plan(
            sampleCount: sampleCount,
            chunkSeconds: chunkSeconds,
            overlapSeconds: overlapSeconds,
            sampleRate: sampleRate
        )
        let chunkSize = max(1, Int((chunkSeconds * Double(sampleRate)).rounded()))
        let index = nextIndex[track, default: 0]
        guard ranges.indices.contains(index) else { return nil }
        let range = ranges[index]
        guard range.count == chunkSize, range.upperBound <= sampleCount else { return nil }
        return range
    }

    public mutating func markSent(track: MeetingTrack) {
        nextIndex[track, default: 0] += 1
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
        languages: [SpeechLanguage] = MeetingLanguages.defaults,
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

        let languages = MeetingLanguages.normalized(languages)
        let autoAttempt: MeetingChunkAttempt
        var autoTranscript: Transcript?
        do {
            let transcript = try await transcriber.transcribe(
                clip,
                options: TranscriptionOptions(
                    language: .auto,
                    timestamps: true,
                    priority: .meeting,
                    expectedLanguages: languages
                )
            )
            autoTranscript = transcript
            autoAttempt = makeAttempt(transcript, mode: .timestamped, requestedLanguage: .auto, clip: clip)
        } catch {
            if error is CancellationError { throw error }
            autoAttempt = MeetingChunkAttempt(
                mode: .timestamped,
                requestedLanguage: .auto,
                state: .failed,
                errorMessage: error.localizedDescription
            )
        }

        if autoAttempt.state == .complete, let detected = autoTranscript?.language,
           !languages.map(\.rawValue).contains(detected) {
            // Whisper guessed a language not chosen for this meeting, often from
            // a hesitation sound. Redo the chunk in the chosen language Whisper
            // scored highest.
            return try await forcedRedo(
                id: id, track: track, offset: offset, clip: clip, previous: autoAttempt,
                language: Self.bestLanguage(among: languages, scores: autoTranscript?.languageScores ?? [:]),
                transcriber: transcriber
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

        // Whisper's automatic detection most often returns nothing for Vietnamese.
        let retryLanguage: SpeechLanguage = languages.contains(.vi) ? .vi : languages[0]
        return try await forcedRedo(
            id: id, track: track, offset: offset, clip: clip,
            previous: autoAttempt, language: retryLanguage, transcriber: transcriber
        )
    }

    /// The chosen language with the highest score; the first chosen one when no scores are known.
    static func bestLanguage(among languages: [SpeechLanguage], scores: [String: Float]) -> SpeechLanguage {
        var best = languages[0]
        var bestScore = scores[best.rawValue] ?? -.infinity
        for language in languages.dropFirst() {
            let score = scores[language.rawValue] ?? -.infinity
            if score > bestScore { best = language; bestScore = score }
        }
        return best
    }

    private func forcedRedo(
        id: String,
        track: MeetingTrack,
        offset: TimeInterval,
        clip: AudioClip,
        previous: MeetingChunkAttempt,
        language: SpeechLanguage,
        transcriber: any Transcriber
    ) async throws -> MeetingChunkProcessingResult {
        do {
            let transcript = try await transcriber.transcribe(
                clip,
                options: TranscriptionOptions(language: language, timestamps: false, priority: .meeting)
            )
            let retry = makeAttempt(transcript, mode: .forcedVAD, requestedLanguage: language, clip: clip)
            return result(
                id: id,
                track: track,
                offset: offset,
                clip: clip,
                attempts: [previous, retry],
                chosen: retry.state == .complete ? 1 : nil
            )
        } catch {
            if error is CancellationError { throw error }
            let retry = MeetingChunkAttempt(
                mode: .forcedVAD,
                requestedLanguage: language,
                state: .failed,
                errorMessage: error.localizedDescription
            )
            return result(id: id, track: track, offset: offset, clip: clip, attempts: [previous, retry], chosen: nil)
        }
    }

    private func makeAttempt(
        _ transcript: Transcript,
        mode: MeetingTranscriptionMode,
        requestedLanguage: SpeechLanguage,
        clip: AudioClip
    ) -> MeetingChunkAttempt {
        var text = HallucinationFilter.strip(DictationPipeline.stripPlaceholders(transcript.text))
        let placeholderStrippedSegments = transcript.segments.compactMap { segment -> TranscriptSegment? in
            let clean = HallucinationFilter.strip(DictationPipeline.stripPlaceholders(segment.text))
            guard !clean.isEmpty else { return nil }
            return TranscriptSegment(start: segment.start, end: segment.end, text: clean)
        }
        if text.isEmpty, !placeholderStrippedSegments.isEmpty {
            text = placeholderStrippedSegments.map(\.text).joined(separator: " ")
        }

        guard !text.isEmpty, !HallucinationFilter.isHallucination(text), !FillerFilter.isOnlyFiller(text) else {
            return MeetingChunkAttempt(
                mode: mode,
                requestedLanguage: requestedLanguage,
                detectedLanguage: transcript.language,
                state: .empty,
                text: text
            )
        }

        let cleanedSegments = placeholderStrippedSegments.filter {
            !HallucinationFilter.isHallucination($0.text) && !FillerFilter.isOnlyFiller($0.text)
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
            MeetingSegment(start: offset + $0.start, end: offset + $0.end, text: $0.text, track: track, sourceChunkID: id)
        } ?? []
        return MeetingChunkProcessingResult(record: record, segments: segments)
    }
}

public enum MeetingTranscriptMerger {
    public static func merge(
        _ chunks: [MeetingChunkProcessingResult],
        overlapWindow: TimeInterval = 2
    ) -> [MeetingSegment] {
        let orderedChunks = chunks.sorted {
            if $0.record.track != $1.record.track {
                return trackOrder($0.record.track) < trackOrder($1.record.track)
            }
            if $0.record.offset != $1.record.offset { return $0.record.offset < $1.record.offset }
            return $0.record.id < $1.record.id
        }
        var previousChunkByTrack: [MeetingTrack: MeetingChunkProcessingResult] = [:]
        var merged: [MeetingSegment] = []

        for chunk in orderedChunks {
            let previousChunk = previousChunkByTrack[chunk.record.track]
            let orderedSegments = chunk.segments.sorted {
                if $0.start != $1.start { return $0.start < $1.start }
                if $0.end != $1.end { return $0.end < $1.end }
                return $0.id < $1.id
            }
            for var segment in orderedSegments {
                guard let previousChunk,
                      let previousIndex = orderedChunks.firstIndex(where: { $0.record.id == previousChunk.record.id }),
                      let currentIndex = orderedChunks.firstIndex(where: { $0.record.id == chunk.record.id }),
                      currentIndex == previousIndex + 1 else {
                    merged.append(segment)
                    continue
                }
                let candidates = previousChunk.segments.filter {
                    $0.track == segment.track
                        && $0.sourceChunkID != segment.sourceChunkID
                        && segment.start <= $0.end + overlapWindow
                        && $0.start <= segment.end + overlapWindow
                }.sorted { $0.start > $1.start }
                guard let previous = candidates.first else {
                    merged.append(segment)
                    continue
                }
                let currentWords = words(segment.text)
                let overlap = sharedBoundaryWordCount(words(previous.text), currentWords)
                guard overlap > 0, overlap >= 2 || overlap == currentWords.count else {
                    merged.append(segment)
                    continue
                }
                if overlap == currentWords.count { continue }
                let pieces = segment.text.split(whereSeparator: \.isWhitespace)
                segment.text = pieces.dropFirst(overlap).joined(separator: " ")
                // The English was for the longer text.
                segment.translation = nil
                if !segment.text.isEmpty { merged.append(segment) }
            }
            previousChunkByTrack[chunk.record.track] = chunk
        }

        return merged.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.track != $1.track { return trackOrder($0.track) < trackOrder($1.track) }
            if $0.end != $1.end { return $0.end < $1.end }
            return $0.id < $1.id
        }
    }

    private static func trackOrder(_ track: MeetingTrack) -> Int {
        track.order
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
