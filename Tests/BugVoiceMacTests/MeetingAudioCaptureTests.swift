import Foundation
import CoreAudio
import Testing
@testable import BugVoiceMac
import VoiceCore

struct MeetingAudioCaptureTests {
    @Test func captureStartsBothSourcesAndRollsBackOnSecondSourceFailure() async throws {
        let root = try testDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let mic = AudioSourceProbe(track: .mic)
        let system = AudioSourceProbe(track: .system, failToStart: true)
        let coordinator = MeetingAudioCaptureCoordinator(
            sources: [.mic: mic, .system: system],
            writer: MeetingPCMJournalWriter(directory: root)
        )

        do {
            try await coordinator.start(track: .mic)
            try await coordinator.start(track: .system)
            Issue.record("Expected system source failure")
        } catch {}

        #expect(await mic.stopCount == 1)
        #expect(await system.stopCount == 1)
    }

    @Test func journalCheckpointsKeepTrackBytesIndependentAndDurable() async throws {
        let root = try testDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = MeetingPCMJournalWriter(directory: root)
        try writer.start(track: .mic)
        try writer.start(track: .system)
        writer.append([0.5, -0.5], track: .mic, offset: 0.2)
        writer.append([0.25], track: .system, offset: 0.4)

        let checkpoint = try writer.checkpoint()
        #expect(checkpoint.track(.mic)?.committedByteCount == 4)
        #expect(checkpoint.track(.system)?.committedByteCount == 2)
        #expect(try Data(contentsOf: root.appendingPathComponent("mic.pcm")).count == 4)
        #expect(try Data(contentsOf: root.appendingPathComponent("system.pcm")).count == 2)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("checkpoint.json").path))
    }

    @Test func journalReaderStreamsBoundedBlocksWithoutLoadingWholeTrack() async throws {
        let root = try testDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = MeetingPCMJournalWriter(directory: root)
        try writer.start(track: .mic)
        let samples = (0..<32_000).map { Float($0 % 100) / 100 }
        writer.append(samples, track: .mic, offset: 0)
        _ = try writer.checkpoint()

        let reader = try writer.makeReader(for: .mic)
        #expect(reader.totalSampleCount == 32_000)
        #expect(try reader.readSamples(maxCount: 16_000).count == 16_000)
        #expect(reader.remainingSampleCount == 16_000)
        let secondBlock = try reader.readSamples(maxCount: 16_000)
        #expect(secondBlock.count == 16_000)
        #expect(zip(secondBlock, samples.suffix(16_000)).allSatisfy { abs($0 - $1) < 0.0001 })
        #expect(reader.remainingSampleCount == 0)
        #expect(try reader.readSamples(maxCount: 16_000).isEmpty)
        writer.close()
    }

    @Test func recoveryDropsUncheckpointedJournalTail() async throws {
        let root = try testDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = MeetingPCMJournalWriter(directory: root)
        try writer.start(track: .mic)
        writer.append([0.5, 0.25], track: .mic, offset: 0)
        _ = try writer.checkpoint()
        writer.append([0.75, 0.5], track: .mic, offset: 1)

        let recovered = try MeetingPCMJournalWriter(directory: root).recover()
        #expect(recovered.track(.mic)?.sampleCount == 2)
        #expect(try Data(contentsOf: root.appendingPathComponent("mic.pcm")).count == 4)
    }

    @Test func recoveryClampsCheckpointIfJournalIsShorterThanRecordedCommit() async throws {
        let root = try testDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = MeetingPCMJournalWriter(directory: root)
        try writer.start(track: .mic)
        writer.append([0.5, 0.25, 0.75, 0.5], track: .mic, offset: 0)
        _ = try writer.checkpoint()
        let journal = root.appendingPathComponent("mic.pcm")
        let handle = try FileHandle(forWritingTo: journal)
        try handle.truncate(atOffset: 2)
        try handle.close()

        let recovered = try MeetingPCMJournalWriter(directory: root).recover()
        #expect(recovered.track(.mic)?.committedByteCount == 2)
        #expect(recovered.track(.mic)?.sampleCount == 1)
        #expect(try Data(contentsOf: journal).count == 2)
    }

    @Test func activeJournalWritesPeriodicCheckpointWithoutPauseOrStop() async throws {
        let root = try testDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = MeetingPCMJournalWriter(directory: root)
        try writer.start(track: .mic)
        writer.append([0.5, 0.25], track: .mic, offset: 0)

        try await Task.sleep(for: .milliseconds(1_200))
        let recovered = try MeetingPCMJournalWriter(directory: root).recover()

        #expect(recovered.track(.mic)?.committedByteCount == 4)
    }

    private func testDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BugVoiceMeetingCapture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private actor AudioSourceProbe: MeetingAudioSource {
    let track: MeetingTrack
    let failToStart: Bool
    private(set) var stopCount = 0
    init(track: MeetingTrack, failToStart: Bool = false) { self.track = track; self.failToStart = failToStart }
    func start(onBuffer: @escaping @Sendable (AudioClip, TimeInterval, Float) -> Void) async throws {
        if failToStart { throw SourceError.failed }
    }
    func pause() async throws {}
    func resume() async throws {}
    func stop() async throws { stopCount += 1 }
}

private enum SourceError: Error { case failed }

struct MeetingTapSampleConverterTests {
    private static let tapFormat = AudioStreamBasicDescription(
        mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
        mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
        mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0
    )

    @Test func convertsFortyEightKilohertzTapAudioToSixteenKilohertz() throws {
        let converter = try #require(MeetingTapSampleConverter(tapFormat: Self.tapFormat))
        let sine = (0..<4_800).map { Float(0.5 * sin(2 * Double.pi * 440 * Double($0) / 48_000)) }
        var output: [Float] = []
        for start in stride(from: 0, to: sine.count, by: 512) {
            let chunk = Array(sine[start..<min(start + 512, sine.count)])
            output += chunk.withUnsafeBufferPointer { converter.convert($0) }
        }
        #expect((1_400...1_700).contains(output.count))
        #expect(abs(AudioClip(samples: output).rms - 0.354) < 0.05)
    }

    @Test func rejectsATapFormatThatIsNotFloatPCM() {
        var integerFormat = Self.tapFormat
        integerFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
        integerFormat.mBitsPerChannel = 16
        integerFormat.mBytesPerFrame = 2
        integerFormat.mBytesPerPacket = 2
        #expect(MeetingTapSampleConverter(tapFormat: integerFormat) == nil)
    }

    @Test func emptyInputGivesNoSamples() throws {
        let converter = try #require(MeetingTapSampleConverter(tapFormat: Self.tapFormat))
        let output = [Float]().withUnsafeBufferPointer { converter.convert($0) }
        #expect(output.isEmpty)
    }
}
