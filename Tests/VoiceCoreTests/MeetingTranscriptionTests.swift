import Foundation
import Testing
@testable import VoiceCore

struct MeetingTranscriptionTests {
    @Test func plansBoundedOverlappingChunks() {
        let ranges = MeetingChunkPlanner.plan(sampleCount: 65 * 16_000, chunkSeconds: 30, overlapSeconds: 1)
        #expect(ranges.count == 3)
        #expect(ranges.allSatisfy { $0.count <= 30 * 16_000 })
        #expect(ranges[0].upperBound > ranges[1].lowerBound)
        #expect(ranges[1].upperBound > ranges[2].lowerBound)
    }

    @Test func liveCursorReturnsOnlyNewCompleteChunksPerTrack() {
        var cursor = MeetingLiveChunkCursor()
        let thirtySeconds = 30 * 16_000
        let fiftyNineSeconds = 59 * 16_000

        #expect(cursor.takeReadyRanges(track: .mic, sampleCount: thirtySeconds) == [0..<thirtySeconds])
        #expect(cursor.takeReadyRanges(track: .mic, sampleCount: thirtySeconds).isEmpty)
        #expect(cursor.takeReadyRanges(track: .system, sampleCount: thirtySeconds) == [0..<thirtySeconds])
        #expect(cursor.takeReadyRanges(track: .mic, sampleCount: fiftyNineSeconds) == [29 * 16_000..<fiftyNineSeconds])
        #expect(cursor.takeReadyRanges(track: .mic, sampleCount: 60 * 16_000).isEmpty)
    }

    @Test func shortSpeechInsideThirtySecondsOfSilencePassesGateAndReachesTranscriber() async throws {
        var samples = Array(repeating: Float.zero, count: 30 * 16_000)
        samples.replaceSubrange(29 * 16_000..<30 * 16_000, with: speechClip.samples)
        let probe = MeetingTranscriberProbe(replies: [.init(text: "hello", language: "en")])

        #expect(MeetingSilenceGate.hasSpeech(samples))
        let result = try await MeetingChunkProcessor().process(
            id: "speech-in-silence", track: .mic, offset: 0,
            clip: AudioClip(samples: samples), transcriber: probe
        )

        #expect(await probe.callCount == 1)
        #expect(result.record.state == .complete)
    }

    @Test func silentChunkDoesNotReachTranscriber() async throws {
        let probe = MeetingTranscriberProbe(replies: [])
        let result = try await MeetingChunkProcessor().process(
            id: "silent", track: .system, offset: 0,
            clip: AudioClip(samples: Array(repeating: 0, count: 30 * 16_000)), transcriber: probe
        )

        #expect(result.record.state == .empty)
        #expect(await probe.callCount == 0)
        #expect(result.segments.isEmpty)
    }

    @Test func meetingTranscriptionExplicitlyUsesMeetingPriorityAndTimestamps() async throws {
        let probe = MeetingTranscriberProbe(replies: [.init(
            text: "hello there",
            segments: [.init(start: 2, end: 3, text: "hello there")],
            language: "en"
        )])

        let result = try await MeetingChunkProcessor().process(
            id: "timestamped", track: .mic, offset: 10,
            clip: speechClip, transcriber: probe
        )

        let options = await probe.receivedOptions
        #expect(options.count == 1)
        #expect(options[0].priority == .meeting)
        #expect(options[0].timestamps)
        #expect(options[0].language == .auto)
        #expect(result.record.requestedLanguage == .auto)
        #expect(result.record.detectedLanguage == "en")
        #expect(result.record.attempts[0].mode == .timestamped)
        #expect(result.segments.count == 1)
        #expect(result.segments.first?.start == 12)
        #expect(result.segments.first?.end == 13)
        #expect(result.segments.first?.text == "hello there")
        #expect(result.segments.first?.track == .mic)
    }

    @Test func placeholderAndHallucinationDoNotEnterTranscript() async throws {
        let probe = MeetingTranscriberProbe(replies: [.init(text: "[BLANK_AUDIO] thank you", language: "en")])
        let result = try await MeetingChunkProcessor().process(
            id: "placeholder", track: .system, offset: 0,
            clip: speechClip, transcriber: probe
        )

        #expect(result.record.state == .empty)
        #expect(result.record.attempts[0].text == "thank you")
        #expect(result.segments.isEmpty)
        #expect(await probe.callCount == 1)
    }

    @Test func hallucinatedSegmentIsRemovedWhenOtherSegmentContainsSpeech() async throws {
        let probe = MeetingTranscriberProbe(replies: [.init(
            text: "hello there, thank you",
            segments: [
                .init(start: 0, end: 1, text: "hello there"),
                .init(start: 1, end: 2, text: "thank you")
            ],
            language: "en"
        )])

        let result = try await MeetingChunkProcessor().process(
            id: "mixed-segments", track: .system, offset: 0,
            clip: speechClip, transcriber: probe
        )

        #expect(result.segments.map(\.text) == ["hello there"])
    }

    @Test func emptyAutoResultRetriesVietnameseWithoutTimestampsAndOffsetsVadTimes() async throws {
        let probe = MeetingTranscriberProbe(replies: [
            .init(text: "", language: "en"),
            .init(text: "xin chào", segments: [.init(start: 1, end: 2, text: "xin chào")], language: "vi")
        ])

        let result = try await MeetingChunkProcessor().process(
            id: "fallback", track: .system, offset: 20,
            clip: speechClip, transcriber: probe
        )

        let options = await probe.receivedOptions
        #expect(options.map(\.language) == [.auto, .vi])
        #expect(options.map(\.timestamps) == [true, false])
        #expect(options.allSatisfy { $0.priority == .meeting })
        #expect(result.record.attempts.map(\.mode) == [.timestamped, .forcedVAD])
        #expect(result.record.chosenAttempt == 1)
        #expect(result.record.detectedLanguage == "vi")
        #expect(result.segments.count == 1)
        #expect(result.segments.first?.start == 21)
        #expect(result.segments.first?.end == 22)
        #expect(result.segments.first?.text == "xin chào")
        #expect(result.segments.first?.track == .system)
    }

    @Test func configuredEnglishRetriesWithEnglish() async throws {
        let probe = MeetingTranscriberProbe(replies: [
            .init(text: "", language: "vi"),
            .init(text: "hello there", language: "en")
        ])

        let result = try await MeetingChunkProcessor().process(
            id: "english-retry", track: .mic, offset: 0,
            clip: speechClip, configuredLanguage: .en, transcriber: probe
        )

        #expect(await probe.receivedOptions.map(\.language) == [.auto, .en])
        #expect(result.record.attempts.map(\.requestedLanguage) == [.auto, .en])
        #expect(result.record.detectedLanguage == "en")
    }

    @Test func repeatedTextWithinOneChunkIsKept() {
        let chunk = chunkResult("mic-0", track: .mic, offset: 0, duration: 30, segments: [
            .init(start: 1, end: 2, text: "Okay.", track: .mic, sourceChunkID: "mic-0"),
            .init(start: 2.3, end: 2.8, text: "Okay.", track: .mic, sourceChunkID: "mic-0")
        ])

        let merged = MeetingTranscriptMerger.merge([chunk], overlapWindow: 2)

        #expect(merged.map(\.text) == ["Okay.", "Okay."])
    }

    @Test func repeatedPhraseAcrossAdjacentSameTrackChunksIsKeptOnce() {
        let first = chunkResult("mic-0", track: .mic, offset: 0, duration: 30, segments: [
            .init(start: 28, end: 29.5, text: "we should ship Friday", track: .mic, sourceChunkID: "mic-0")
        ])
        let second = chunkResult("mic-1", track: .mic, offset: 29, duration: 30, segments: [
            .init(start: 29, end: 30, text: "ship Friday after review", track: .mic, sourceChunkID: "mic-1")
        ])
        let otherTrack = chunkResult("system-0", track: .system, offset: 0, duration: 30, segments: [
            .init(start: 28, end: 29, text: "ship Friday", track: .system, sourceChunkID: "system-0")
        ])

        let merged = MeetingTranscriptMerger.merge([second, otherTrack, first], overlapWindow: 2)

        #expect(merged.filter { $0.track == .mic }.map(\.text) == ["we should ship Friday", "after review"])
        #expect(merged.first(where: { $0.track == .system })?.text == "ship Friday")
        #expect(merged.map(\.start) == [28, 28, 29])
    }

    private func chunkResult(
        _ id: String,
        track: MeetingTrack,
        offset: TimeInterval,
        duration: TimeInterval,
        segments: [MeetingSegment]
    ) -> MeetingChunkProcessingResult {
        MeetingChunkProcessingResult(
            record: MeetingChunkRecord(
                id: id, track: track, offset: offset, duration: duration,
                requestedLanguage: .auto, state: .complete
            ),
            segments: segments
        )
    }
}

private actor MeetingTranscriberProbe: Transcriber {
    let replies: [Transcript]
    private(set) var receivedOptions: [TranscriptionOptions] = []
    private(set) var callCount = 0

    init(replies: [Transcript]) {
        self.replies = replies
    }

    func transcribe(_ clip: AudioClip, options: TranscriptionOptions) async throws -> Transcript {
        receivedOptions.append(options)
        let index = callCount
        callCount += 1
        guard replies.indices.contains(index) else { return Transcript(text: "") }
        return replies[index]
    }
}
