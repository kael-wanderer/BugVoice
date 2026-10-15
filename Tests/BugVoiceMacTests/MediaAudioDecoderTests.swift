import AVFoundation
import Foundation
import Testing
@testable import BugVoiceMac
import VoiceCore

@Suite(.serialized)
struct MediaAudioDecoderTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func emptyAndVideoOnlyAreRejected() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let empty = root.appendingPathComponent("empty.m4a")
        try Data().write(to: empty)
        await #expect(throws: UploadFailure.unreadable) {
            try await MediaAudioDecoder.probe(empty)
        }
        let video = root.appendingPathComponent("video.mov")
        try await UploadAssetFactory.make(at: video, audio: false, video: true)
        await #expect(throws: UploadFailure.noAudio) {
            try await MediaAudioDecoder.probe(video)
        }
    }

    @Test func metadataCreationDateFallsBackAndProbeRejectsDirectory() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let dated = root.appendingPathComponent("dated.m4a")
        try await UploadAssetFactory.make(at: dated, creationDate: "2024-01-02T03:04:05Z")
        let expected = try #require(ISO8601DateFormatter().date(from: "2024-01-02T03:04:05Z"))
        #expect(try await MediaAudioDecoder.probe(dated).creationDate == expected)
        let invalid = root.appendingPathComponent("invalid.m4a")
        try await UploadAssetFactory.make(at: invalid, creationDate: "not-a-date")
        let filesystem = try invalid.resourceValues(forKeys: [.creationDateKey]).creationDate
        #expect(try await MediaAudioDecoder.probe(invalid).creationDate == filesystem)
        await #expect(throws: UploadFailure.unreadable) {
            try await MediaAudioDecoder.probe(root)
        }
    }

    @Test func cancellationStopsAtCheckpointWithoutRecognitionCommit() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("cancel.m4a")
        try await UploadAssetFactory.make(at: url, seconds: 5)
        let metadata = try await MediaAudioDecoder.probe(url)
        let writer = MeetingPCMJournalWriter(directory: root.appendingPathComponent(".capture"))
        await #expect(throws: CancellationError.self) {
            try await MediaAudioDecoder.decode(url, metadata: metadata, writer: writer, boundary: {
                throw CancellationError()
            }, progress: { _ in })
        }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("meeting.json").path))
        #expect((try writer.storedCheckpoint().track(.file)?.sampleCount ?? 0) < 80_000)
    }

    @Test func resamplesAndDownmixes() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        for channels in [1, 2, 6] {
            let url = root.appendingPathComponent("audio-\(channels).m4a")
            try await UploadAssetFactory.make(at: url, rate: channels == 1 ? 16_000 : 48_000, channels: channels)
            let metadata = try await MediaAudioDecoder.probe(url)
            #expect(metadata.kind == .audio)
            #expect(abs(metadata.duration - 3) < 0.1)
            let writer = MeetingPCMJournalWriter(directory: root.appendingPathComponent("capture-\(channels)"))
            try await MediaAudioDecoder.decode(url, metadata: metadata, writer: writer, boundary: {}, progress: { _ in })
            let checkpoint = try writer.storedCheckpoint()
            #expect(checkpoint.tracks.map(\.track) == [.file])
            #expect(abs((checkpoint.track(.file)?.sampleCount ?? 0) - 48_000) < 1_600)
            let reader = try writer.makeReader(for: .file)
            let block = try reader.readSamples(maxCount: 16_000)
            let rms = AudioClip(samples: block).rms
            // Apple's 5.1-to-mono matrix lowers level more than a stereo average does.
            #expect(rms > (channels == 6 ? 0.10 : 0.20))
            #expect(rms <= 0.8)
        }
        let mov = root.appendingPathComponent("av.mov")
        try await UploadAssetFactory.make(at: mov, rate: 48_000, channels: 2, video: true)
        let movie = try await MediaAudioDecoder.probe(mov)
        #expect(movie.kind == .video)
        let movieWriter = MeetingPCMJournalWriter(directory: root.appendingPathComponent("capture-mov"))
        try await MediaAudioDecoder.decode(mov, metadata: movie, writer: movieWriter, boundary: {}, progress: { _ in })
        #expect(abs((try movieWriter.storedCheckpoint().track(.file)?.sampleCount ?? 0) - 48_000) < 1_600)
    }

    @Test func threeHourTimelineUsesBoundedBlocks() async throws {
        let probe = StreamProbe()
        var stream = UploadPCMStream(totalSamples: 10_800 * 16_000, sink: { block, _ in
            await probe.accept(block.count)
        }, checkpoint: {
            await probe.checkpoint()
        })
        for second in 0..<10_800 {
            try await stream.push(Array(repeating: 0.25, count: 16_000), at: second * 16_000)
        }
        try await stream.finish()
        #expect(await probe.maximum <= 16_000)
        #expect(await probe.maximumPending <= 16_000)
        #expect(await probe.total == 10_800 * 16_000)
        #expect(await probe.barriers >= 10_800)
    }

    @Test func removedSourceNeverCommitsTruncatedReading() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("source.m4a")
        try await UploadAssetFactory.make(at: url, seconds: 5)
        let metadata = try await MediaAudioDecoder.probe(url)
        let writer = MeetingPCMJournalWriter(directory: root.appendingPathComponent("capture"))
        let remover = RemoveOnce(url: url)
        do {
            try await MediaAudioDecoder.decode(url, metadata: metadata, writer: writer, boundary: {}, progress: { _ in
                await remover.remove()
            })
            #expect(try writer.storedCheckpoint().track(.file)?.sampleCount == Int((metadata.duration * 16_000).rounded()))
        } catch {
            #expect(error as? UploadFailure == .unreadable)
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func timelineGapsEOFAndCheckpointFailures() async throws {
        let probe = StreamProbe()
        var stream = UploadPCMStream(totalSamples: 32_000, sink: { block, _ in
            await probe.accept(block.count)
        }, checkpoint: {
            await probe.checkpoint()
        })
        try await stream.push(Array(repeating: 0.5, count: 8_000), at: 16_000)
        try await stream.finish()
        #expect(await probe.total == 32_000)
        var broken = UploadPCMStream(totalSamples: 16_000, sink: { _, _ in }, checkpoint: {
            throw UploadFailure.diskFull
        })
        await #expect(throws: UploadFailure.diskFull) {
            try await broken.push(Array(repeating: 0, count: 16_000), at: 0)
        }
    }
}

private actor StreamProbe {
    var maximum = 0
    var pending = 0
    var maximumPending = 0
    var total = 0
    var barriers = 0
    func accept(_ count: Int) {
        maximum = max(maximum, count)
        pending += count
        maximumPending = max(maximumPending, pending)
        total += count
    }
    func checkpoint() {
        barriers += 1
        pending = 0
    }
}

private actor RemoveOnce {
    let url: URL
    private var removed = false
    init(url: URL) { self.url = url }
    func remove() {
        guard !removed else { return }
        removed = true
        try? FileManager.default.removeItem(at: url)
    }
}
