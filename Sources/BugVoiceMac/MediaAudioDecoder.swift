import AVFoundation
import AudioToolbox
import Foundation
import VoiceCore

public struct UploadMediaMetadata: Sendable {
    public var fileName: String
    public var kind: UploadMediaKind
    public var duration: TimeInterval
    public var byteSize: Int64
    public var creationDate: Date?
}

public struct UploadPCMStream: Sendable {
    private let totalSamples: Int
    private let sink: @Sendable ([Float], TimeInterval) async throws -> Void
    private let checkpoint: @Sendable () async throws -> Void
    private var position = 0
    private var sinceCheckpoint = 0

    public init(
        totalSamples: Int,
        sink: @escaping @Sendable ([Float], TimeInterval) async throws -> Void,
        checkpoint: @escaping @Sendable () async throws -> Void
    ) {
        self.totalSamples = totalSamples
        self.sink = sink
        self.checkpoint = checkpoint
    }

    public mutating func push(_ samples: [Float], at start: Int) async throws {
        while position < min(start, totalSamples) {
            try await emit(Array(repeating: 0, count: min(16_000 - sinceCheckpoint, min(start, totalSamples) - position)))
        }
        var index = max(0, position - start)
        while index < samples.count, position < totalSamples {
            let count = min(16_000 - sinceCheckpoint, samples.count - index, totalSamples - position)
            try await emit(Array(samples[index..<(index + count)]))
            index += count
        }
    }

    public mutating func finish() async throws {
        while position < totalSamples {
            try await emit(Array(repeating: 0, count: min(16_000 - sinceCheckpoint, totalSamples - position)))
        }
        try await checkpoint()
    }

    private mutating func emit(_ samples: [Float]) async throws {
        try Task.checkCancellation()
        try await sink(samples, Double(position) / 16_000)
        position += samples.count
        sinceCheckpoint += samples.count
        if sinceCheckpoint >= 16_000 {
            try await checkpoint()
            sinceCheckpoint = 0
        }
    }
}

public enum MediaAudioDecoder {
    public static let extensions = ["mp3", "wav", "m4a", "aiff", "caf", "mp4", "mov", "m4v"]

    public static func probe(_ url: URL) async throws -> UploadMediaMetadata {
        do {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .creationDateKey])
            guard values.isDirectory != true,
                  extensions.contains(url.pathExtension.lowercased()),
                  let size = values.fileSize, size > 0 else { throw UploadFailure.unreadable }
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration).seconds
            guard duration.isFinite, duration > 0,
                  duration < Double(Int.max / 16_000) else { throw UploadFailure.unreadable }
            let audio = try await asset.loadTracks(withMediaType: .audio)
            guard !audio.isEmpty else { throw UploadFailure.noAudio }
            let video = try await asset.loadTracks(withMediaType: .video)
            var creationDate: Date?
            let metadata = try await asset.load(.commonMetadata)
            for item in metadata where item.commonKey == .commonKeyCreationDate {
                if let date = try? await item.load(.dateValue), date.timeIntervalSince1970.isFinite {
                    creationDate = date
                    break
                }
                if let value = try? await item.load(.stringValue) {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    creationDate = formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
                    if creationDate != nil { break }
                }
            }
            return UploadMediaMetadata(
                fileName: url.lastPathComponent,
                kind: video.isEmpty ? .audio : .video,
                duration: duration,
                byteSize: Int64(size),
                creationDate: creationDate ?? values.creationDate
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as UploadFailure {
            throw failure
        } catch {
            throw UploadFailure.unreadable
        }
    }

    public static func decode(
        _ url: URL,
        metadata: UploadMediaMetadata,
        writer: MeetingPCMJournalWriter,
        boundary: @escaping @Sendable () async throws -> Void,
        progress: @escaping @Sendable (Double?) async -> Void
    ) async throws {
        let asset = AVURLAsset(url: url)
        let tracks: [AVAssetTrack]
        do {
            tracks = try await asset.loadTracks(withMediaType: .audio)
        } catch {
            throw UploadFailure.unreadable
        }
        guard !tracks.isEmpty else { throw UploadFailure.noAudio }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw UploadFailure.unreadable }
        reader.add(output)
        var expectedAudioEnd = 0.0
        for track in tracks {
            let range = try await track.load(.timeRange)
            expectedAudioEnd = max(expectedAudioEnd, CMTimeRangeGetEnd(range).seconds)
        }
        let total = Int((metadata.duration * 16_000).rounded())
        try writer.start(track: .file)
        defer { writer.close() }
        var stream = UploadPCMStream(totalSamples: total, sink: { samples, offset in
            writer.append(samples, track: .file, offset: offset)
        }, checkpoint: {
            _ = try writer.checkpoint()
            try await boundary()
        })
        guard reader.startReading() else { throw UploadFailure.unreadable }
        defer { reader.cancelReading() }
        var decodedEnd = 0.0
        while let buffer = output.copyNextSampleBuffer() {
            defer { withExtendedLifetime(buffer) {} }
            try Task.checkCancellation()
            let time = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
            guard time.isFinite, let block = CMSampleBufferGetDataBuffer(buffer) else { throw UploadFailure.unreadable }
            let count = CMSampleBufferGetNumSamples(buffer)
            var pointer: UnsafeMutablePointer<Int8>?
            var contiguous = 0
            var length = 0
            guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: &contiguous, totalLengthOut: &length, dataPointerOut: &pointer) == noErr,
                  let pointer, contiguous == length, length >= count * 4 else { throw UploadFailure.unreadable }
            let floats = UnsafeRawPointer(pointer).assumingMemoryBound(to: Float.self)
            let start = Int((time * 16_000).rounded())
            var offset = 0
            while offset < count {
                let size = min(16_000, count - offset)
                let samples = Array(UnsafeBufferPointer(start: floats.advanced(by: offset), count: size))
                try await stream.push(samples, at: start + offset)
                offset += size
                await progress(min(1, max(0, Double(start + offset) / Double(total))))
            }
            decodedEnd = max(decodedEnd, time + Double(count) / 16_000)
        }
        guard reader.status == .completed,
              decodedEnd + 0.1 >= min(metadata.duration, expectedAudioEnd) else {
            throw UploadFailure.unreadable
        }
        await progress(nil)
        try await stream.finish()
        _ = try writer.checkpoint()
        try Task.checkCancellation()
    }
}
