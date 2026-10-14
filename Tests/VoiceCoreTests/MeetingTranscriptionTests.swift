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

    @Test func mergerOffsetsSortsAndRemovesRepeatedOverlapPhrase() {
        let segments = [
            MeetingSegment(start: 12, end: 14, text: "ship it tomorrow after review", track: .mic),
            MeetingSegment(start: 10, end: 13, text: "we need to ship it tomorrow", track: .mic),
            MeetingSegment(start: 10, end: 11, text: "status update", track: .system)
        ]

        let merged = MeetingTranscriptMerger.merge(segments, overlapWindow: 2)

        #expect(merged.map(\.start) == [10, 10, 12])
        #expect(merged[0].track == .mic)
        #expect(merged[0].speaker == "You")
        #expect(merged[1].speaker == "Others")
        #expect(merged[2].text == "after review")
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
